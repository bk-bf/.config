# Memory reclaim — leaked processes on the Galaxy Book

**Machine:** CachyOS, 15.9 GB RAM, zram-only swap (15.2 G, zstd, `vm.swappiness=150`).
**Related:** `MEMORY_PRESSURE.md` · vault `notes/projects/infrastructure/CachyOS-Setup/Laptop-RAM-Pressure-Standing-Record.md`

Three classes of process outlive the thing that owned them and are never cleaned up. Together
they held **~5 GB committed** on 2026-07-27, roughly a third of physical RAM.

**Reclaimed on 2026-07-27: 4.2 GB committed** — 1.31 GB of deleted Claude sessions, 2.90 GB of
abandoned dev servers. Available RAM 2.8 → 4.0 GB, swap 13.0 → 10.8 GB, zram data 12.2 → 9.3 GB,
memory PSI `full avg300` 0.81 → 0.55.

## Measure committed memory, not RSS

On a box sitting 13 GB deep in zram, `VmRSS` describes only what survived eviction. An idle
process — a session on hiatus, a dev server nobody is hitting — has its heap compressed out of
the resident set while still occupying the zram pool, i.e. still occupying RAM. Always sum
`VmRSS + VmSwap`:

```bash
# committed memory for a single pid
awk '/VmRSS|VmSwap/{s+=$2} END{printf "%.0f MB\n", s/1024}' /proc/<pid>/status
```

Measuring RSS alone understated the Claude Code family by 2.8× and the dev servers by 4.9×.

---

## 1. Deleted VS Code Claude Code sessions

**The leak.** Deleting a session in the extension sidebar only appends its UUID to
`hiddenSessionIds` inside VS Code's `state.vscdb` (239 entries on 2026-07-27). The helper process
is never signalled and the 29 MB transcript is never removed. Five live helpers belonged to
already-deleted sessions and held **1.31 GB committed**.

**The fix.** `scripts/claude-vscode-session-gc.sh` + `systemd/user/claude-vscode-session-gc.timer`
(every 60 s). Reads the hidden list read-only, matches it against `~/.claude/sessions/<pid>.json`,
SIGTERMs the matches.

Safety: only `entrypoint == claude-vscode` is a candidate, so terminal/herdr sessions, the
`bg-spare` pool, the daemon and the Chrome MCP bridge are structurally excluded. PID reuse is
guarded by comparing `/proc` starttime against the recorded `procStart`. Nothing younger than
120 s is touched, so a session recreated right after a delete cannot be shot in the back.

```bash
scripts/claude-vscode-session-gc.sh --dry-run      # what it would kill
systemctl --user enable --now claude-vscode-session-gc.timer
journalctl --user -u claude-vscode-session-gc.service -n 20
```

**Status:** ✅ live since 2026-07-27, freed 1.31 GB on its first pass.

### Inspect the hidden list by hand

```bash
sqlite3 -readonly ~/.config/Code/User/globalStorage/state.vscdb \
  "select value from ItemTable where key='Anthropic.claude-code';" \
  | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["hiddenSessionIds"]))'
```

---

## 2. Abandoned node/vite dev servers

**The leak.** `pnpm dev` started in a terminal survives the terminal closing — it is reparented to
the systemd user manager and listens forever. The next `pnpm dev` finds the port taken and picks
the next one, so they stack up. On 2026-07-27: **twelve `dashboard/web` servers on ports
5201–5310**, plus `codegraph` on 5185 alive since 2026-07-16 (11 days) and `vault-ask` on 5200.
Total **~3.7 GB committed**, almost all of it swapped out and invisible in `top`.

The incrementing ports are the tell — each one is a restart that failed to kill its predecessor.

**The fix.** `scripts/dev-server-gc.sh`. Reaps only when **all five** hold:

1. the process holds a `LISTEN` socket (a server, not a build step),
2. its process tree is rooted at the systemd user manager — the launching shell is gone,
3. it is **not a managed systemd unit** (see below),
4. it has **zero** established connections,
5. it is older than `DEV_SERVER_GC_MIN_AGE` (default 3600 s).

Criterion 4 protects a server you are actively hitting in a browser; criterion 2 protects one you
are about to hit from a terminal you still have open.

**Criterion 3 exists because the first run got it wrong.** A supervised service's parent is *also*
the systemd user manager, so parentage alone cannot distinguish "orphaned" from "supervised" — the
first run killed `codegraph.service`, which systemd restarted three seconds later. The cgroup is
the reliable discriminator:

| | cgroup |
|---|---|
| managed unit | `…/app.slice/codegraph.service` |
| orphaned dev server | keeps the launching terminal's scope, e.g. `…/app.slice/app-code-491143.scope` |

A cgroup path ending in `.service` means supervised — skip it.

**Result, 2026-07-27.** 14 abandoned servers reaped: **node processes 29 → 6, committed
3.90 GB → 1.00 GB.** Correctly kept Fantasia4x `:5174` (one live connection), VS Code's own
listeners, `codegraph.service` (after the fix), and ignored an in-progress vitest run entirely.

```bash
scripts/dev-server-gc.sh --dry-run                 # always look first
scripts/dev-server-gc.sh
DEV_SERVER_GC_MIN_AGE=86400 scripts/dev-server-gc.sh   # only reap >1 day old
```

**Tradeoff to know:** a dev server deliberately left running detached, with nothing connected to
it for over an hour, is indistinguishable from an abandoned one and will be reaped. Raise
`DEV_SERVER_GC_MIN_AGE` if that ever bites. Restarting costs one `pnpm dev`.

---

## 3. Orphaned Claude Code background spares

**The leak.** The `bg-pty-host` / `bg-spare` pairs are a pre-warmed worker pool — by design, not a
leak. But a pair can outlive the daemon that owns it and get reparented to the systemd user
manager. On 2026-07-27 one such pair was 3 d 14 h old against a 2 d 17 h daemon.

**Detection** — a spare older than the daemon that should own it:

```bash
ps -o pid=,etime=,args= -C claude | grep bg-
systemctl --user show claude 2>/dev/null   # or: pgrep -af 'claude daemon'
```

No automated reaper. Killing a spare is harmless — the pool refills on demand.

---

## The age-based backstop

`scripts/claude-reaper.sh` (daily, >24 h) predates all of the above and stays. It covers the case
the session GC cannot see: a helper abandoned without ever being deleted in the UI. Its window
leaves a permanent residue of 5–8 helpers under the 24 h threshold — lower
`CLAUDE_REAPER_MAX_AGE` and run the timer hourly if that matters.

Note it also matches the `--claude-in-chrome-mcp` bridge, which is not a session; that gets killed
at 24 h and respawns.

---

## What this does not fix

Reclaiming leaked processes buys back ~5 GB. It does not change the ceiling: 15.9 GB of soldered
LPDDR5X with no upgrade path. Under a genuine runaway — one Claude Code process at 5.8 GB, as on
2026-07-23 — none of these reapers help, because the offender is neither idle nor orphaned. The
guard for that case is `OOMPolicy=continue` on `wayland-wm@hyprland.desktop.service`, which keeps
an OOM kill from tearing down the whole desktop.

# Memory Pressure Management — Galaxy Book Gen4

**Date:** June 28, 2026 · **Revised:** July 28, 2026  
**Status:** ✓ Applied — reaper active; the session soft cap was **inverted into protection**;
oomd re-adopted, but scoped

> **Revision note (2026-07-28).** The original `session.slice MemoryHigh=11G` was backwards and
> is gone — see [The inversion](#the-inversion-2026-07-28) below. Priority policy across CPU,
> memory and IO now lives in [CPU_PRIORITY.md](./CPU_PRIORITY.md); this doc covers the reaper
> and the pressure background.

---

## Problem

15 GB RAM laptop, frequently exhausted → deep into zram swap (~10 GB used) →
swap-thrash → system-wide lag, VS Code unusable. Two distinct causes:

1. **Leak:** VS Code's Claude Code extension spawns a helper process per session
   but does **not** kill it when the session is deleted in the UI. They pile up
   (26 found, some >1 day old) and bleed RAM.
2. **Pressure:** too much running (VS Code ~6 GB + browser + builds) for 15 GB.

---

## Current Status

| Mechanism | Role | Kills procs? | State |
| --- | --- | --- | --- |
| `claude-reaper` user timer | Daily reap of leaked Claude Code helpers >1 day | No (orphans only) | ✅ Active |
| `session.slice` `MemoryLow=6G` | **Protects** the desktop from reclaim | No | ✅ Active |
| `app-code-*.scope` `MemoryHigh=9G` | Per-instance soft cap on VS Code | **No — throttles only** | ✅ Active |
| `app.slice` `MemoryHigh` | slice-wide cap on dev work | — | ❌ **Removed same night — see below** |
| `systemd-oomd`, scoped | Kills worst offender in `app`/`background` only | Yes | ✅ Active |

> **A slice-wide `MemoryHigh=6G` on `app.slice` was set and removed on 2026-07-28.** It was
> mis-sized from an idle reading and was reachable in ordinary loaded use. Do not reintroduce
> it — the per-instance `app-code-.scope.d` cap is the right layer. Full reasoning in
> [CRASH_HISTORY.md](./CRASH_HISTORY.md#2026-07-28--user-manager-sigkill-unresolved).

### The inversion (2026-07-28)

The original policy put `MemoryHigh=11G` on **`session.slice`**. That is a soft **cap applied to
the cgroup it names** — so it throttled the compositor, browser and terminals, the things that
must stay responsive, while `app.slice` (VS Code, test runners) was uncapped at the slice level.
The session sat at ~7.2 GB against that ceiling in ordinary use, so reclaim pressure genuinely
landed on the desktop. This is a plausible cause of long-standing desktop sluggishness.

The knobs are not symmetric, and this is the trap:

| Knob | Meaning |
| --- | --- |
| `MemoryLow` | soft **protection** from reclaim — the real priority lever |
| `MemoryMin` | hard protection, never reclaimed — pushes OOM onto other cgroups |
| `MemoryHigh` | soft **cap**, throttles via reclaim pressure |
| `MemoryMax` | hard cap, OOM kill |

Protection went to the desktop. The matching cap on dev work was tried at the slice level and
withdrawn the same night (above); capping now happens only per-instance, on `app-code-*.scope`.

> **Watch for a shadow.** A `systemctl set-property` without `--runtime` writes a permanent
> override into `~/.config/systemd/user.control/<unit>.d/`, which **takes precedence over the
> tracked drop-in**. One such file held the old `MemoryHigh=11G` and would have silently
> defeated the edit. Always pass `--runtime` when applying live, and check `user.control/`
> before concluding a change did not take.

### systemd-oomd: rejected in June, re-adopted scoped in July

The June objection was correct and still is: on this setup **every app Hyprland spawns directly
shares one cgroup** —

```
.../user@1000.service/session.slice/wayland-wm@hyprland.desktop.service
```

— so an unscoped oomd would not kill "the worst offender", it would take the whole session.

The fix is not to reject oomd but to control *where it may act*. It is now opted in on
`app.slice` and `background.slice` **only**, never `session.slice`, at 70% sustained pressure
(vs the 60% default). Pressure relief therefore lands on dev work and batch jobs.

```
systemd/user/app.slice.d/60-oomd.conf
systemd/user/background.slice.d/60-oomd.conf   → ManagedOOMMemoryPressure=kill, limit 70%
```

Rationale: the kernel OOM killer picks by heuristic and has previously taken down desktop
processes (see [CRASH_HISTORY.md](./CRASH_HISTORY.md)). A killed test
runner is a re-run; a killed compositor is the session.

**Trade-off:** this can kill a VS Code instance with unsaved editor state under sustained severe
pressure. The alternative is the kernel choosing.

The system service is running. It is **not** enabled at boot — start it again after a reboot,
or `systemctl enable systemd-oomd` to make it permanent:

```bash
sudo systemctl enable --now systemd-oomd
```

> Note: oomd was running during the 2026-07-28 session loss and killed nothing — its log is
> empty for that boot. It is not implicated. See [CRASH_HISTORY.md](./CRASH_HISTORY.md).

---

## What Was Done

### 1. Claude Code process reaper (user-level, no sudo)

Leaked extension helpers (`anthropic.claude-code.*resources`) older than 1 day
are terminated daily. Matched by cmdline, so the real `claude` CLI and VS Code
itself are never touched.

- Script: `~/.config/scripts/claude-reaper.sh` (supports `--dry-run`)
- Service: `~/.config/systemd/user/claude-reaper.service` (`Type=oneshot`)
- Timer: `~/.config/systemd/user/claude-reaper.timer` (`OnCalendar=daily`,
  `Persistent=true`, catches up after sleep)

Enabled with:
```bash
systemctl --user enable --now claude-reaper.timer
```

> Note: chosen over a cron job because `cronie` isn't running on this box, and a
> systemd user timer lives in the dotfiles repo (portable to a new machine).

### 2. Protect the desktop, throttle dev work (user-level, no sudo)

Neither knob kills — both work through reclaim. `MemoryLow` makes the kernel take pages from
*somewhere else* first; `MemoryHigh` makes it reclaim from *this* cgroup sooner. zram compresses
what is reclaimed (~3.3:1 measured), so this frees real RAM rather than hitting disk.

- `systemd/user/session.slice.d/memory.conf` → `MemoryLow=6G` (protection, no ceiling)
- `systemd/user/app-code-.scope.d/` → `MemoryHigh=9G` (per-instance cap, predates this work)
- `systemd/user/app.slice.d/50-memory.conf` → `MemoryHigh=infinity` (**deliberately no cap**)

A slice-wide cap on `app.slice` was tried at 6 GB and removed the same night. The sizing was
taken from a 1.7–2.0 GB idle reading, but `app.slice` reaches **3.4 GB within minutes of a fresh
boot** and much more under vitest workers plus a headless test browser — so the cap was
reachable in normal loaded use, not only under bloat. Worse, sustained `MemoryHigh` reclaim
pushes pages into zram, and zram is compressed RAM, so it consumes physical RAM and tightens the
pressure it was meant to relieve.

**Size any future cap from the loaded case, never from an idle reading.**

Applied live (note `--runtime`, see the shadow warning above):
```bash
systemctl --user set-property --runtime session.slice MemoryLow=6G MemoryHigh=infinity
systemctl --user set-property --runtime app.slice MemoryHigh=infinity
```

**Limit worth stating:** VS Code's UI and its background work share one
`app-code-<pid>.scope`, and cgroup limits apply per-cgroup, so this cannot perfectly separate
them. For a true split, start heavy jobs with `bgr` (see
[CPU_PRIORITY.md](./CPU_PRIORITY.md)), which puts them in `background.slice` and leaves the
editor's scope untouched.

---

## Quick Commands

### Monitoring
```bash
free -h                                         # RAM + swap usage
zramctl                                          # zram compression ratio
btop                                             # per-process overview
ps -eo pid,%cpu,%mem,etime,comm --sort=-%mem | head
```

### Check status
```bash
systemctl --user list-timers claude-reaper.timer   # next reap run
~/.config/scripts/claude-reaper.sh --dry-run            # what it WOULD reap now
systemctl --user show session.slice -p MemoryLow -p MemoryHigh
systemctl --user show app.slice -p MemoryHigh
systemctl is-active systemd-oomd.service            # needs enabling (see above)
ls ~/.config/systemd/user.control/ 2>/dev/null      # stale overrides that shadow drop-ins
```

Verify against the kernel rather than the unit file:
```bash
B=/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service
grep . "$B"/{session,app,background}.slice/memory.{low,high,current}
```

### Manual reap (immediate relief)
```bash
~/.config/scripts/claude-reaper.sh
```

---

## Tuning

- **Reaper too aggressive / too lax?** Change the age threshold:
  `CLAUDE_REAPER_MAX_AGE=43200 ~/.config/scripts/claude-reaper.sh` (seconds), or edit
  the default in the script.
- **Dev work feels throttled?** There is no slice-wide cap by design. The per-instance limit is
  `app-code-.scope.d` → `MemoryHigh=9G`; raise that rather than adding one to `app.slice`.
- **Desktop still stutters under pressure?** Raise the protection —
  `session.slice.d/memory.conf` → `MemoryLow=8G`. Do **not** put a `MemoryHigh` back on
  `session.slice`; that is the inversion this doc exists to warn about.

---

## Honest Limits

No setting conjures RAM. zram already compresses cold pages; `MemoryHigh` just
forces that to happen earlier and more aggressively instead of letting the whole
system thrash. The real ceiling is 15 GB physical RAM — the durable fix is
running fewer heavyweight apps (VS Code + browser + node builds) at once, or more
RAM. These mechanisms buy margin gracefully; they don't remove the ceiling.

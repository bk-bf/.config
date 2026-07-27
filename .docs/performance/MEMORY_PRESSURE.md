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
| `app.slice` `MemoryHigh=6G` | Soft cap on dev work → reclaim lands here | **No — throttles only** | ✅ Active |
| `systemd-oomd`, scoped | Kills worst offender in `app`/`background` only | Yes | ⚠️ Configured; needs the system service enabled |

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

Protection went to the desktop and the cap moved to dev work, where being slowed costs nothing.

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
processes (see [CRASH_HISTORY_2026-07-23.md](./CRASH_HISTORY_2026-07-23.md)). A killed test
runner is a re-run; a killed compositor is the session.

**Trade-off:** this can kill a VS Code instance with unsaved editor state under sustained severe
pressure. The alternative is the kernel choosing.

Requires the system service, which is **not currently enabled**:

```bash
sudo systemctl enable --now systemd-oomd
```

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
- `systemd/user/app.slice.d/50-memory.conf` → `MemoryHigh=6G` (cap on dev work)

The `app.slice` figure is sized so only bloat reaches it: normal use sits at ~2.0 GB, so there
is 3× headroom and the VS Code UI is never reclaimed against. What does reach 6 GB is
background growth — extension host, language servers, node test workers holding heaps.

Applied live (note `--runtime`, see the shadow warning above):
```bash
systemctl --user set-property --runtime session.slice MemoryLow=6G MemoryHigh=infinity
systemctl --user set-property --runtime app.slice MemoryHigh=6G
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
- **Dev work feels throttled?** Raise `app.slice`'s cap — edit
  `app.slice.d/50-memory.conf` and re-run
  `systemctl --user set-property --runtime app.slice MemoryHigh=8G`. Lower it to reclaim sooner.
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

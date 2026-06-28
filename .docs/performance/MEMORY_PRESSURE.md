# Memory Pressure Management — Galaxy Book Gen4

**Date:** June 28, 2026  
**Status:** ✓ Applied — reaper + soft cap active, oomd rejected

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

| Mechanism                          | Role                                              | Kills procs? | State |
| ---------------------------------- | ------------------------------------------------- | ------------ | ----- |
| `claude-reaper` user timer         | Daily reap of leaked Claude Code helpers >1 day   | No (orphans only) | ✅ Active |
| `session.slice` `MemoryHigh=11G`   | Soft cap → kernel compresses cold pages into zram | **No — throttles only** | ✅ Active |
| `systemd-oomd`                     | —                                                 | Yes (whole cgroup) | ❌ Rejected & disabled |

### Why systemd-oomd was rejected

oomd only **kills** — it has no graceful mode. Worse, on this Hyprland setup
**every GUI app shares one cgroup**:

```
.../user@1000.service/session.slice/wayland-wm@hyprland.desktop.service
```

So oomd under pressure would not kill "the worst offender" — it would kill the
**entire Hyprland session at once**. Unsuitable here. Disabled including its
socket:

```bash
sudo systemctl disable --now systemd-oomd systemd-oomd.socket
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

### 2. Graceful soft cap on the GUI session (user-level, no sudo)

`MemoryHigh` is a **soft** cgroup limit: when `session.slice` exceeds it, the
kernel reclaims cold pages into zram (compressed ~4:1, freeing real RAM) and
throttles allocation if needed — it **never kills**. This is the "unload instead
of kill" behaviour.

- Drop-in: `~/.config/systemd/user/session.slice.d/memory.conf` → `MemoryHigh=11G`

Applied live with:
```bash
systemctl --user set-property session.slice MemoryHigh=11G
```

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
systemctl --user show session.slice -p MemoryHigh  # current soft cap
systemctl is-active systemd-oomd.service systemd-oomd.socket  # both: inactive
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
- **Apps feel throttled?** Raise the soft cap — edit
  `session.slice.d/memory.conf` and re-run
  `systemctl --user set-property session.slice MemoryHigh=12G`. Lower it to
  reclaim sooner.

---

## Honest Limits

No setting conjures RAM. zram already compresses cold pages; `MemoryHigh` just
forces that to happen earlier and more aggressively instead of letting the whole
system thrash. The real ceiling is 15 GB physical RAM — the durable fix is
running fewer heavyweight apps (VS Code + browser + node builds) at once, or more
RAM. These mechanisms buy margin gracefully; they don't remove the ceiling.

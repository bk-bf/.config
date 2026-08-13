# `.docs` — history

Documentation of how this laptop is currently set up lives in Claude Code
skills at `~/.claude/skills/`, not here. A skill loads itself when it is
relevant; a markdown file is only read if someone goes looking for it.

| Subject | Skill |
|---|---|
| Heat, battery, suspend, idle blanking, scx/VRR, workspace restore | `laptop-power` |
| Speakers, touchpad/touchscreen, battery not detected, greeter scaling | `laptop-hardware` |
| cgroup priority, memory pressure, leaked processes, session losses | `system-resources` |
| This repo: `/etc` symlinks, package tracking, pacdim, Limine | `dotfiles` |
| sudo/PAM failures, faillock, the polkit agent | `sudo-and-polkit` |
| Compositor, UWSM session targets, portals, frame drops | `hyprland` |
| Theme propagation from Noctalia to GTK/kitty/Qt | `noctalia` |
| Browser prefs, hardware decode, the RAM leak | `zen-browser` |
| Journal notifications and automatic triage | `watcher` |

The originals are kept at `~/.docs-converted-2026-08-13/`.

---

## What is still here, and why

Nothing below describes the current machine, so none of it belongs in a skill —
a skill that fires and describes a subsystem that no longer exists is worse than
no skill at all.

- `archived/` — subsystems that have been removed. `taildrop-obsidian/` (sync
  scripts and vault path both gone), `hibernation/` (superseded by s2idle),
  `gdm/` (superseded by SDDM), `swayfx+waybar/` (the pre-Hyprland desktop, plus
  its package list). Kept for history; never treat as current.
- `misc/HELIUM_OPTIMISATIONS.md` — the Chromium evaluation that preceded
  returning to Zen. Historical: Helium is not the daily browser.
- `SESSION-PACKAGE-PROFILES.md` — an open research note on activating
  per-compositor package sets without uninstalling, unresolved and with its
  conclusion still untested. It also references a `NIRI-MIGRATION.md` that does
  not exist.

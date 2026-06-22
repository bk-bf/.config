# Workspace / Session Restore (hyprflow)

**Device:** Samsung Galaxy Book 4 Pro (NP940XGK), CachyOS / Arch, Hyprland + Noctalia

Restores which apps were open on which workspaces after a reboot or power loss. Replaces the
old hand-rolled `workspace-snapshot.sh` / `workspace-restore.sh` scripts (removed 2026-06-22),
which were fragile and never preserved terminal state. Itself a replacement for hibernate, which
was removed due to hardware incompatibilities — see `.docs/archived/hibernation/HIBERNATION.md`.

---

## What it is

[hyprflow](https://github.com/isorensen/hyprflow) — a maintained Rust tool from the AUR
(`hyprflow`, depends only on `hyprland`). It captures window state via `hyprctl clients -j`,
reads terminal CWD from `/proc`, stores sessions as JSON, and on restore re-launches the apps
on their original workspaces and re-positions the windows.

Install:
```bash
yay -S hyprflow
```

---

## What is / is NOT preserved

**Preserved:** which app is on which workspace, window positions/geometry, terminal working
directory. Transient surfaces (Waybar/Noctalia bar, launchers, popups) are filtered out.

**NOT preserved:** live terminal state — running processes, scrollback, shell history. hyprflow
(like any relaunch-based tool) re-runs the original command; it does not freeze/thaw a process.
If terminal-content persistence is ever wanted, that is a separate layer (tmux-resurrect +
tmux-continuum via the already-installed tpm — not currently wired up). Browser tabs are handled
by Firefox/Chromium's own session restore and need no help here.

---

## Wiring in this repo

| Where | What |
|---|---|
| `hypr/hyprland.conf` | `exec-once = hyprflow restore --max-age 24h` — restores last autosave on login, skips sessions older than 24h |
| systemd user timer | `hyprflow autosave --install` installs the periodic autosave timer/service (lives under `~/.config/systemd/user/`, **not** tracked in this repo) |

The old `battery-snapshot.timer`, `workspace-restore.service`, and the `before-sleep` snapshot
trigger in `idle-action.sh` were all removed. Autosave is now periodic (timer-driven) rather
than battery/lid triggered.

---

## Manual commands

```bash
hyprflow save                 # save current session as "latest"
hyprflow save work            # named session
hyprflow restore              # restore "latest"
hyprflow restore --max-age 24h
hyprflow list                 # list saved sessions
hyprflow autosave --install   # (re)install the autosave systemd timer
```

Session data lives under hyprflow's own state dir, not in this dotfiles repo.

---

## Relationship to other power docs

| Doc | Status |
|---|---|
| `.docs/archived/hibernation/HIBERNATION.md` | Removed — full failure post-mortem |
| `.docs/power/BATTERY_DETECTION.md` | Active — BAT1 ACPI probe race workaround |
| `.docs/battery/S2IDLE_OPTIMIZATION.md` | Active — s2idle drain optimisation |
| `.docs/audio/SPEAKER_FIX.md` | Active — MAX98390 DKMS speaker fix |

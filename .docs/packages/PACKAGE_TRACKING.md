# Package Tracking

## Overview

Explicitly installed packages are tracked in `pkglist.txt` and auto-committed to a private git
repository. The goal is fast machine replication — `pkglist.txt` is the single source of truth
for what belongs on the system.

`~/.config/pkglist.txt` is a symlink to the canonical file in the private repo. It is not
tracked in this public repo. See `documentation/private/PKGLIST_INFRA.md` for infrastructure
details (local only, not in public repo).

---

## File Map

| File                                                         | Purpose                                                           |
| ------------------------------------------------------------ | ----------------------------------------------------------------- |
| `~/.local/share/pkglist/pkglist.txt`                         | Canonical package list (`pacman -Qqe` output) — private git repo  |
| `~/.config/pkglist.txt`                                      | Symlink → `~/.local/share/pkglist/pkglist.txt`                    |
| `~/.config/pkg-tracker.sh`                                   | Regenerates list, commits + pushes to private server              |
| `~/.config/systemd/user/pkg-tracker.service`                 | oneshot service that runs the script                              |
| `~/.config/systemd/user/pkg-tracker.timer`                   | Fires the service daily                                           |
| `~/.config/pkg-tracker.hook`                                 | Hook source — symlinked to `/etc/pacman.d/hooks/pkg-tracker.hook` |
| `~/.config/sddm/sddm.conf`                                   | SDDM config — symlinked to `/etc/sddm.conf`                       |
| `~/.config/grub/grub`                                        | GRUB config — symlinked to `/etc/default/grub`                    |
| `~/.config/intel-undervolt/intel-undervolt.conf`             | Power limits — symlinked to `/etc/intel-undervolt.conf`           |
| `~/.config/s2idle/s2idle-optimize.service`                   | S2idle systemd unit — symlinked to `/etc/systemd/system/`         |
| `~/.config/s2idle/s2idle-optimize.sh`                        | S2idle script — symlinked to `/usr/local/bin/`                    |
| `~/.config/documentation/archived/swayfx+waybar/pkglist.txt` | Preserved package list from old swayfx setup                      |

---

## How It Works

Two triggers keep `pkglist.txt` up to date automatically:

**Pacman hook** — fires immediately after any `yay`/`pacman` transaction (install, remove,
upgrade). Defined in `/etc/pacman.d/hooks/pkg-tracker.hook` with `Target = *` so it catches
every package operation without exception.

**Daily systemd timer** — `pkg-tracker.timer` fires once per day as a safety net for any changes
the hook might miss (e.g. manual edits, AUR helpers that bypass hooks).

Both invoke `pkg-tracker.sh`, which:
1. Runs `pacman -Qqe` and writes the output to `pkglist.txt`
2. `git add`s the file and commits only if it actually changed

---

## Restoring on a New Machine

```bash
# Clone your config repo
git clone <your-repo> ~/.config

# Set up the private pkglist repo — see documentation/private/PKGLIST_INFRA.md
# (requires private infrastructure to be accessible)

# Install all packages (yay handles both official and AUR)
yay -S --needed - < ~/.config/pkglist.txt
```

Dependencies not in `pkglist.txt` are pulled in automatically by pacman's resolver — only
top-level explicit packages need to be listed.

---

## Manual Resync

If the list gets out of sync (e.g. after undoing edits):

```bash
~/.config/pkg-tracker.sh
```

---

## Setup (on a fresh system)

See `documentation/private/PKGLIST_INFRA.md` for the full setup procedure including private
repository initialisation and infrastructure requirements.

```bash
# After private repo is cloned and symlink is in place:
chmod +x ~/.config/pkg-tracker.sh

# Symlink all system-level config files (requires root)
sudo ln -sf ~/.config/pkg-tracker.hook /etc/pacman.d/hooks/pkg-tracker.hook
sudo ln -sf ~/.config/sddm/sddm.conf /etc/sddm.conf
sudo ln -sf ~/.config/grub/grub /etc/default/grub
sudo ln -sf ~/.config/intel-undervolt/intel-undervolt.conf /etc/intel-undervolt.conf
sudo ln -sf ~/.config/s2idle/s2idle-optimize.service /etc/systemd/system/s2idle-optimize.service
sudo chmod +x ~/.config/s2idle/s2idle-optimize.sh
sudo ln -sf ~/.config/s2idle/s2idle-optimize.sh /usr/local/bin/s2idle-optimize.sh
sudo systemctl daemon-reload

# Enable the daily timer
systemctl --user enable --now pkg-tracker.timer

# Generate initial list
~/.config/pkg-tracker.sh
```

---

## Checking Status

```bash
# Timer next fire time
systemctl --user status pkg-tracker.timer

# Last run log
journalctl --user -u pkg-tracker.service
```

---

## Related

- `documentation/archived/swayfx+waybar/pkglist.txt` — packages from the old swayfx + waybar
  config, preserved for reference but not installed on the current Hyprland system

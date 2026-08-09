# Package Tracking

## Overview

Explicitly installed packages are tracked in a `pkglist.txt` and auto-committed to a private git
repository. The goal is fast machine replication — each machine's `pkglist.txt` is the single
source of truth for what belongs on that system.

The private repo is **shared by every machine**. To avoid machines clobbering each other's list,
each host writes to its own directory, `hosts/<tailscale-hostname>/pkglist.txt`, keyed by the
machine's Tailscale name (e.g. `hosts/cachyos-x8664-desktop/pkglist.txt`).

`~/.config/pkglist.txt` is a symlink to *this* host's canonical file in the private repo. It is
not tracked in this public repo. See `documentation/private/PKGLIST_INFRA.md` for infrastructure
details (local only, not in public repo).

---

## File Map

| File                                                         | Purpose                                                           |
| ------------------------------------------------------------ | ----------------------------------------------------------------- |
| `~/.local/share/pkglist/`                                    | Clone of the shared private repo (`ubuntu:git/pkglist.git`)        |
| `~/.local/share/pkglist/hosts/<tailscale-host>/pkglist.txt`  | This host's canonical package list (`pacman -Qqe` output)         |
| `~/.config/pkglist.txt`                                      | Symlink → this host's `hosts/<tailscale-host>/pkglist.txt`        |
| `~/.config/pkg-tracker.sh`                                   | Bootstraps repo, regenerates list, commits + pushes to server     |
| `~/.config/systemd/user/pkg-tracker.service`                 | oneshot service that runs the script                              |
| `~/.config/systemd/user/pkg-tracker.timer`                   | Fires the service daily                                           |
| `~/.config/pkg-tracker.hook`                                 | Hook source — symlinked to `/etc/pacman.d/hooks/pkg-tracker.hook` |
| `~/.config/sddm/sddm.conf`                                   | SDDM config — symlinked to `/etc/sddm.conf`                       |
| ~~`~/.config/grub/grub`~~                                     | **Stale (Jul 2026)** — this machine boots Limine, not GRUB; neither path exists. See [../boot/LIMINE.md](../boot/LIMINE.md) |
| `~/.config/intel-undervolt/intel-undervolt.conf`             | Power limits — symlinked to `/etc/intel-undervolt.conf`           |
| `~/.config/s2idle/s2idle-optimize.service`                   | S2idle systemd unit — symlinked to `/etc/systemd/system/`         |
| `~/.config/s2idle/s2idle-optimize.sh`                        | S2idle script — symlinked to `/usr/local/bin/`                    |
| `~/.config/documentation/archived/swayfx+waybar/pkglist.txt` | Preserved package list from old swayfx setup                      |

---

## How It Works

Two triggers keep the list up to date automatically:

**Pacman hook** — fires immediately after any `yay`/`pacman` transaction (install, remove,
upgrade). Defined in `/etc/pacman.d/hooks/pkg-tracker.hook` with `Target = *` so it catches
every package operation without exception.

**Daily systemd timer** — `pkg-tracker.timer` fires once per day as a safety net for any changes
the hook might miss (e.g. manual edits, AUR helpers that bypass hooks).

Both invoke `pkg-tracker.sh`, which:
1. **Bootstraps** on first run — clones `ubuntu:git/pkglist.git` into `~/.local/share/pkglist/`
   if it's missing, so a fresh machine works straight from the hook (no manual setup).
2. Resolves this host's Tailscale name and ensures `hosts/<tailscale-host>/` exists, then points
   `~/.config/pkglist.txt` at that host's `pkglist.txt`.
3. Runs `pacman -Qqe` and writes the output to `hosts/<tailscale-host>/pkglist.txt`.
4. `git add`s the file and commits only if it actually changed, then `git pull --rebase` (to pick
   up other machines' pushes) and `git push`. A failed push is logged and retried next run, so it
   never reports the pacman hook as failed.

---

## Restoring on a New Machine

```bash
# Clone your config repo
git clone <your-repo> ~/.config

# Bootstrap the private pkglist repo (clones it + sets up the symlink).
# Requires the private infra to be reachable (Tailscale up, SSH key present) —
# see documentation/private/PKGLIST_INFRA.md.
~/.config/pkg-tracker.sh

# Install this machine's packages, OR replicate another machine's:
yay -S --needed - < ~/.config/pkglist.txt                                  # this host
yay -S --needed - < ~/.local/share/pkglist/hosts/<other-host>/pkglist.txt  # clone another host
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
chmod +x ~/.config/pkg-tracker.sh

# First run clones the private repo, creates hosts/<tailscale-host>/, and
# sets up the ~/.config/pkglist.txt symlink automatically.
~/.config/pkg-tracker.sh

# Symlink all system-level config files (requires root)
sudo ln -sf ~/.config/pkg-tracker.hook /etc/pacman.d/hooks/pkg-tracker.hook
sudo ln -sf ~/.config/sddm/sddm.conf /etc/sddm.conf
# sudo ln -sf ~/.config/grub/grub /etc/default/grub   # STALE: Limine now, see ../boot/LIMINE.md
sudo ln -sf ~/.config/intel-undervolt/intel-undervolt.conf /etc/intel-undervolt.conf
sudo ln -sf ~/.config/s2idle/s2idle-optimize.service /etc/systemd/system/s2idle-optimize.service
sudo chmod +x ~/.config/s2idle/s2idle-optimize.sh
sudo ln -sf ~/.config/s2idle/s2idle-optimize.sh /usr/local/bin/s2idle-optimize.sh
sudo systemctl daemon-reload

# Enable the daily timer
systemctl --user enable --now pkg-tracker.timer
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

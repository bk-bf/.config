# System Config Symlink Pattern

## Overview

System-level config files that live outside `~/.config` by default are moved into this repo and
replaced with symlinks. This makes them git-tracked, version-controlled, and included in the
standard machine restore flow alongside dotfiles.

---

## The Pattern

```
~/.config/<app>/<config-file>   ← source of truth, git-tracked
        ↑
        symlink
        |
/etc/<config-file>              ← what the system reads
```

1. Copy the file into a logical location under `~/.config/`
2. Delete (or backup) the original
3. `sudo ln -sf ~/.config/<app>/<file> /etc/<file>`

The system reads the file from its expected path as normal — it never knows it's a symlink.

---

## Tracked System Files

| `~/.config` source                     | System path                                   | Purpose                                                                                                                                                        |
| -------------------------------------- | --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sddm/sddm.conf`                       | `/etc/sddm.conf`                              | Reference template — `install.sh` writes this file directly (not symlinked) so `QT_SCALE_FACTOR` can be set conditionally based on detected display resolution |
| `limine/default-limine`                | `/etc/default/limine`                         | Limine `ENABLE_SORT` (linux-cachyos before -lts). Galaxy Book kernel params ride the live `/proc/cmdline` — see [boot/LIMINE.md](./boot/LIMINE.md)             |
| `limine/theme.conf`                    | `<ESP>/limine.conf` (header)                  | Catppuccin-Mocha theme keys, injected into the Limine config header by `install.sh`                                                                            |
| `limine/limine-splash.png`             | `<ESP>/limine-splash.png`                     | Limine boot wallpaper (copied to the ESP)                                                                                                                      |
| `intel-undervolt/intel-undervolt.conf` | `/etc/intel-undervolt.conf`                   | PL1/PL2 power limits                                                                                                                                           |
| `s2idle/s2idle-optimize.service`       | `/etc/systemd/system/s2idle-optimize.service` | Runtime PM systemd unit                                                                                                                                        |
| `s2idle/s2idle-optimize.sh`            | `/usr/local/bin/s2idle-optimize.sh`           | Runtime PM script                                                                                                                                              |
| `pkg-tracker.hook`                     | `/etc/pacman.d/hooks/pkg-tracker.hook`        | Auto-updates pkglist.txt on package changes                                                                                                                    |
| `.docs/udev/99-disable-touchscreen.rules`    | `/etc/udev/rules.d/99-disable-touchscreen.rules` | Suppresses GXTP7936 touchscreen from libinput — see [TOUCHSCREEN_UDEV.md](./TOUCHSCREEN_UDEV.md) |

---

## Restoring on a New Machine

After cloning the repo and installing packages, run:

```bash
sudo mkdir -p /etc/pacman.d/hooks

sudo ln -sf ~/.config/sddm/sddm.conf /etc/sddm.conf
sudo install -m 0644 ~/.config/limine/default-limine /etc/default/limine
sudo ln -sf ~/.config/intel-undervolt/intel-undervolt.conf /etc/intel-undervolt.conf
sudo ln -sf ~/.config/s2idle/s2idle-optimize.service /etc/systemd/system/s2idle-optimize.service
sudo chmod +x ~/.config/s2idle/s2idle-optimize.sh
sudo ln -sf ~/.config/s2idle/s2idle-optimize.sh /usr/local/bin/s2idle-optimize.sh
sudo ln -sf ~/.config/pkg-tracker.hook /etc/pacman.d/hooks/pkg-tracker.hook
sudo cp ~/.config/.docs/udev/99-disable-touchscreen.rules /etc/udev/rules.d/

sudo systemctl daemon-reload
sudo limine-update
sudo systemctl enable --now s2idle-optimize.service
sudo systemctl enable --now intel-undervolt
```

---

## What Belongs Here vs Not

**Good candidates** — files you've meaningfully customised, that have no sensitive content, and
that would silently degrade the system if missing after a restore:

- Display manager config (SDDM)
- Bootloader config & kernel cmdline (Limine)
- Hardware tuning (undervolting, power limits)
- System service units you authored
- Pacman hooks

**Not suitable** — files that contain secrets, are machine-specific to the point of being
useless elsewhere, or that package updates are expected to own entirely:

- `/etc/fstab`, `/etc/crypttab` — UUIDs are machine-specific
- `/etc/shadow`, `/etc/passwd` — sensitive
- PAM config — high breakage risk if blindly restored
- Network credentials (NetworkManager keyfiles under `/etc/`)

---

## Package Update Behaviour

For files marked as `backup` in their package (e.g. `/etc/intel-undervolt.conf`), pacman compares
checksums. Since the symlink target differs from the package default, pacman places a `.pacnew`
file instead of overwriting — your tracked file is left untouched.

After any relevant package update, check for `.pacnew` files:

```bash
sudo find /etc -name "*.pacnew" 2>/dev/null
```

Merge any relevant changes into the `~/.config` source, then delete the `.pacnew`.

---

## Related

- [packages/PACKAGE_TRACKING.md](./packages/PACKAGE_TRACKING.md) — full file map and restore steps including these symlinks
- [sddm/HIDPI.md](./sddm/HIDPI.md) — why `sddm.conf` exists outside `~/.config` natively
- [battery/S2IDLE_OPTIMIZATION.md](./battery/S2IDLE_OPTIMIZATION.md) — s2idle service and script
- [performance/THERMAL_OPTIMIZATION.md](./performance/THERMAL_OPTIMIZATION.md) — intel-undervolt config

The same symlink pattern is also used for **private content** excluded from the public repo: `~/.config/opencode/commands` and `documentation/private/` are symlinks into `~/.local/share/` and tracked in a private bare repo on the local server. See `documentation/private/OPENCODE_INFRA.md` / `documentation/private/PKGLIST_INFRA.md`.

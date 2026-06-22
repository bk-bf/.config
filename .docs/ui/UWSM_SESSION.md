# UWSM Session Dependency

## Why This Setup Requires UWSM

Three services in this setup carry `PartOf=graphical-session.target` and
`xdg-desktop-portal-gnome` carries `Requisite=graphical-session.target`. This means all four
refuse to start unless `graphical-session.target` is already active:

| Service / unit                     | Dependency on `graphical-session.target`       |
| ---------------------------------- | ---------------------------------------------- |
| `theme-watch.service`              | `PartOf=` + `WantedBy=`                        |
| `polkit-agent.service`             | `PartOf=`                                      |
| `xdg-desktop-portal-gnome.service` | `Requisite=` (fails immediately if not active) |
| `xdg-desktop-portal.service`       | `After=` (ordering only)                       |

UWSM activates `graphical-session.target` **before the compositor's first window appears**, via a
chain of systemd targets it creates at session start:

```
wayland-session@hyprland.desktop.target
    BindsTo=graphical-session.target
    Before=graphical-session.target
    PropagatesStopTo=graphical-session.target
```

Plain `start-hyprland` does none of this. It is a compiled binary with no environment propagation
or session target activation code.

### Why `exec-once` Cannot Replace UWSM

`exec-once` runs **after** the compositor is already rendering frames and autostarts have fired.
By the time `systemctl --user start hyprland-session.target` would execute, apps (VS Code,
Firefox) have already made D-Bus calls to `xdg-desktop-portal`, which triggered
`xdg-desktop-portal-gnome`, which failed its `Requisite=` check because
`graphical-session.target` was still inactive. A `sleep 5s` prefix mitigates the race but is not
reliable on cold boot or slow hardware and leaves a 5-second window where polkit auth cannot spawn.

UWSM exposes no such window because session target activation is part of its pre-compositor
initialization sequence.

---

## SDDM Configuration

SDDM must be configured to use the UWSM-managed session entry:

**`/etc/sddm.conf`**
```ini
[Autologin]
User=kirill
Session=hyprland-uwsm
```

- `Session=hyprland-uwsm` launches `/usr/share/wayland-sessions/hyprland-uwsm.desktop`
  (`Exec=uwsm start hyprland.desktop`)
- `Session=hyprland` launches `/usr/share/wayland-sessions/hyprland.desktop`
  (`Exec=start-hyprland`) — **no session management**
- If `User=` is absent, SDDM silently ignores ` [Autologin]` and shows the greeter, which may
  default to the last manually-selected session

---

## Spotting UWSM Failure

### Compositor fails to start (black screen / back to SDDM greeter)

UWSM itself failed before launching Hyprland. Check the system journal:

```bash
journalctl -b --no-pager | grep -E "uwsm|wayland-session|hyprland" | tail -30
```

Common causes:
- A unit file UWSM depends on failed (check `Failed` units below)
- PAM or login session issue (rare)

### Compositor starts but services are all dead

`graphical-session.target` is inactive despite Hyprland running — UWSM launched but did not
complete session activation. Check:

```bash
systemctl --user is-active graphical-session.target
systemctl --user list-units --state=failed
```

### File picker opens wrong dialog (GTK file chooser instead of Nautilus)

`xdg-desktop-portal-gnome` failed its `Requisite=` check. Check:

```bash
systemctl --user status xdg-desktop-portal-gnome.service
journalctl --user -b -u xdg-desktop-portal-gnome.service --no-pager
```

If the status shows `result: dependency` the failure is `graphical-session.target` was inactive
at activation time — UWSM is not running or did not complete.

### Polkit auth dialogs do not appear

`polkit-agent.service` did not start. Check:

```bash
systemctl --user status polkit-agent.service
```

If inactive with no recent start time, `graphical-session.target` never activated.

### Theme watcher is not running

```bash
systemctl --user status theme-watch.service
```

If inactive, same root cause.

---

## Troubleshooting

### Full session state snapshot

```bash
# Are the key targets active?
systemctl --user is-active graphical-session.target
systemctl --user is-active wayland-session@hyprland.desktop.target

# What failed this boot?
systemctl --user list-units --state=failed

# UWSM's own service
systemctl --user status wayland-wm@hyprland.desktop.service

# All portal services
systemctl --user status xdg-desktop-portal.service xdg-desktop-portal-gnome.service xdg-desktop-portal-hyprland.service

# Theme pipeline
systemctl --user status theme-watch.service polkit-agent.service
```

### Confirm SDDM used the right session

```bash
# Shows which session entry SDDM launched
journalctl -b --no-pager | grep -i "sddm\|session" | head -20
cat /etc/sddm.conf
```

### Force-restart portal stack without rebooting

```bash
systemctl --user restart xdg-desktop-portal-gnome.service
systemctl --user restart xdg-desktop-portal.service
```

Only works if `graphical-session.target` is currently active.

### Force-restart theme pipeline

```bash
systemctl --user restart theme-watch.service
~/.config/hypr/scripts/theme-sync.sh   # manual one-shot resync
```

### If UWSM itself is broken after a package update

```bash
# Check UWSM version and whether the package is intact
pacman -Qi uwsm
uwsm --version

# Reinstall if necessary
sudo pacman -S uwsm

# Verify the session desktop file is still present
cat /usr/share/wayland-sessions/hyprland-uwsm.desktop
```

### Nuclear option — verify the chain manually from a running session

```bash
# This is what UWSM does; if these work you know the pieces are fine
dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
systemctl --user is-active graphical-session.target   # should be: active
systemctl --user status theme-watch.service polkit-agent.service xdg-desktop-portal-gnome.service
```

---

## Why Not Switch to Plain Hyprland + Manual Session Target?

This was tested on 2026-03-02. Summary of findings:

- `start-hyprland` is a compiled binary — zero env propagation or session target code
- `exec-once = systemctl --user start hyprland-session.target` fires **inside** the compositor
  after auto-launched apps have already attempted D-Bus portal calls; `Requisite=` fails before
  the target activates
- `sway-systemd`'s `session.sh` is designed to run **as a systemd service before the compositor**
  — it does not solve the race when used from `exec-once`
- Adding `sleep 5s` works around the race but leaves a window where polkit auth cannot spawn and
  is fragile on cold boot
- UWSM's `wayland-session@.target` uses `BindsTo= / Before= / PropagatesStopTo=` which is
  **identical** to what a manual `hyprland-session.target` would need — UWSM is not doing anything
  exotic, it is just doing it at the right time (pre-compositor)

The Hyprland wiki's "not recommended for most users" note is accurate for users without systemd
user services. This setup specifically requires `graphical-session.target` and UWSM is the
correct tool.

---

## Related

- [THEME_SYNC.md](THEME_SYNC.md) — the theme pipeline whose `theme-watch.service` depends on `graphical-session.target`; also restarts `polkit-agent.service` on every sync
- [POLKIT_AGENT.md](../auth/POLKIT_AGENT.md) — polkit agent service that carries `PartOf=graphical-session.target` and therefore requires UWSM to auto-start

# GTK Theme Sync — Implementation Reference

## Overview

GTK3, GTK4, Qt, and Noctalia are fully independent theming systems. This pipeline syncs them
automatically whenever Noctalia's active color scheme changes, reading directly from Noctalia's
`colors.json` and writing CSS variables, kitty colors, and import glue in one shot.

Qt apps inherit GTK colors via `QT_QPA_PLATFORMTHEME=gtk3` passthrough — no separate Qt theming
needed.

---

## Architecture

```
~/.config/noctalia/colors.json   ← written by Noctalia on any scheme change
          │
          │  inotifywait (directory watch, close_write + moved_to)
          ▼
  theme-watch.service  (systemd user service, persistent, auto-restarts)
          │
          │  spawns on change
          ▼
  theme-sync.sh
          │
          ├─ reads all mXxx tokens via jq
          │
          ├─ writes  gtk-3.0/noctalia-colors.css  (@define-color variables)
          ├─ writes  gtk-4.0/noctalia-colors.css  (@define-color variables)
          │
          ├─ ensures gtk-3.0/gtk.css  has  @import url("noctalia-colors.css")
          ├─ ensures gtk-4.0/gtk.css  has  @import url("noctalia-colors.css")
          │
          ├─ writes  kitty/current-theme.conf  (background, foreground, 16 colors)
          ├─ sends   SIGUSR1 to kitty  (live reload, no restart needed)
          ├─ restarts polkit-agent.service  (GTK3 has no live reload — must restart)
          │
          └─ notify-send  "Theme Sync"  (desktop notification on completion)

  QT_QPA_PLATFORMTHEME=gtk3  →  Qt apps inherit GTK theme automatically
```

Also triggered directly (without the watcher) by one Noctalia hook in `settings.json`:
- **`darkModeChange`** — on dark/light mode toggle

---

## Why inotifywait, Not Just Noctalia Hooks

Noctalia's `darkModeChange` hook only fires when toggling the dark/light switch — **not** when
switching predefined color schemes (e.g. Catppuccin → Tokyo Night). There is no hook for scheme
changes.

The file watcher fills this gap: whenever Noctalia writes a new `colors.json` for any reason
(scheme change, dark mode toggle, startup generation), the sync fires automatically.

Noctalia writes `colors.json` atomically (delete + recreate), so the watcher targets the
**directory** with `moved_to` + `close_write` events and filters for `colors.json` by filename.
Watching the file directly would lose the inotify watch on each atomic replace.

---

## File Map

| File                                                 | Status            | Purpose                                      |
| ---------------------------------------------------- | ----------------- | -------------------------------------------- |
| `~/.config/hypr/scripts/theme-watch.sh`              | source-controlled | inotifywait loop, filters colors.json events |
| `~/.config/hypr/scripts/theme-sync.sh`               | source-controlled | Reads colors.json, writes all outputs        |
| `~/.config/systemd/user/theme-watch.service`         | source-controlled | Runs theme-watch.sh persistently             |
| `~/.config/noctalia/settings.json`                   | source-controlled | Noctalia darkModeChange hook → theme-sync.sh |
| `~/.config/gtk-3.0/noctalia-colors.css`              | **generated**     | Do not edit — overwritten on every sync      |
| `~/.config/gtk-4.0/noctalia-colors.css`              | **generated**     | Do not edit — overwritten on every sync      |
| `~/.config/kitty/current-theme.conf`                 | **generated**     | Do not edit — overwritten on every sync      |
| `~/.config/gtk-3.0/gtk.css`                          | source-controlled | `@import` + custom widget overrides          |
| `~/.config/gtk-4.0/gtk.css`                          | source-controlled | `@import` only                               |
| `~/.config/gtk-3.0/settings.ini`                     | source-controlled | Base theme: `adw-gtk3-dark`                  |
| `~/.config/gtk-4.0/settings.ini`                     | source-controlled | Base theme: `adw-gtk3-dark`                  |
| `~/.config/environment.d/qt.conf`                    | source-controlled | Qt platform env vars                         |
| `~/.config/xdg-desktop-portal/hyprland-portals.conf` | source-controlled | Portal routing (file picker → gtk backend)   |

---

## File Watcher

**`~/.config/hypr/scripts/theme-watch.sh`**

Watches the `~/.config/noctalia/` directory for `close_write` or `moved_to` events, filters for
`colors.json`, debounces 300ms, then calls `theme-sync.sh`.

```bash
#!/usr/bin/env bash
WATCH_DIR="$HOME/.config/noctalia"
SYNC_SCRIPT="$HOME/.config/hypr/scripts/theme-sync.sh"

inotifywait -m -e close_write -e moved_to --format '%f' "$WATCH_DIR" 2>/dev/null \
| while read -r filename; do
    [[ "$filename" != "colors.json" ]] && continue
    sleep 0.3
    "$SYNC_SCRIPT"
done
```

**`~/.config/systemd/user/theme-watch.service`**

```ini
[Unit]
Description=Noctalia color scheme file watcher
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.config/hypr/scripts/theme-watch.sh
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
```

Manage with standard systemctl:
```bash
systemctl --user status theme-watch.service
systemctl --user restart theme-watch.service
journalctl --user -u theme-watch.service -f
```

---

## Sync Script

**`~/.config/hypr/scripts/theme-sync.sh`**

Reads all relevant Noctalia color tokens from `colors.json` via `jq`, then generates all outputs
in a single pass. Colors are written directly from the token values — no external tools invoked.

### Noctalia Token → GTK Variable Mapping

| GTK `@define-color`                                                                                | Noctalia token    | Role                                    |
| -------------------------------------------------------------------------------------------------- | ----------------- | --------------------------------------- |
| `accent_color`, `accent_bg_color`                                                                  | `mPrimary`        | Accent / highlight color                |
| `accent_fg_color`                                                                                  | `mOnPrimary`      | Text on accent                          |
| `destructive_color`, `destructive_bg_color`                                                        | `mError`          | Destructive actions                     |
| `destructive_fg_color`                                                                             | `mOnError`        | Text on destructive                     |
| `success_color`                                                                                    | `mTertiary`       | Success state                           |
| `warning_color`                                                                                    | `mSecondary`      | Warning state                           |
| `error_color`                                                                                      | `mError`          | Error state                             |
| `window_bg_color`, `view_bg_color`                                                                 | `mSurface`        | Window / content background             |
| `window_fg_color`, `view_fg_color`                                                                 | `mOnSurface`      | Primary text                            |
| `headerbar_bg_color`, `popover_bg_color`, `card_bg_color`, `dialog_bg_color`, `thumbnail_bg_color` | `mSurfaceVariant` | Elevated surfaces                       |
| `sidebar_bg_color`, `sidebar_backdrop_color`                                                       | `mSurface`        | Sidebar (focused + unfocused)           |
| `secondary_sidebar_bg_color`, `secondary_sidebar_backdrop_color`                                   | `mSurfaceVariant` | Secondary sidebar (focused + unfocused) |
| `headerbar_backdrop_color`                                                                         | `mSurface`        | Headerbar unfocused state               |
| `all *_fg_color` (surface roles)                                                                   | `mOnSurface`      | Text on surfaces                        |
| `headerbar_border_color`                                                                           | `mOutline`        | Borders and dividers                    |

### Kitty Color Mapping

| kitty key                                  | Noctalia token                 |
| ------------------------------------------ | ------------------------------ |
| `background`                               | `mSurface`                     |
| `foreground`                               | `mOnSurface`                   |
| `cursor`                                   | `mPrimary`                     |
| `cursor_text_color`                        | `mOnPrimary`                   |
| `selection_background`                     | `mSurfaceVariant`              |
| `selection_foreground`                     | `mOnSurface`                   |
| `color0` / `color8` (black / bright black) | `mSurface` / `mSurfaceVariant` |
| `color1` / `color9` (red)                  | `mError`                       |
| `color2` / `color10` (green)               | `mPrimary`                     |
| `color3` / `color11` (yellow)              | `mSecondary`                   |
| `color4` / `color12` (blue)                | `mOnSurfaceVariant`            |
| `color5` / `color13` (magenta)             | `mPrimary`                     |
| `color6` / `color14` (cyan)                | `mSecondary`                   |
| `color7` / `color15` (white)               | `mOnSurface`                   |

Kitty is live-reloaded via `SIGUSR1` — no restart needed.

---

## Base GTK Theme

Both GTK3 and GTK4 `settings.ini` set `gtk-theme-name=adw-gtk3-dark` (from `adw-gtk-theme`).
This provides widget shapes, borders, and structural layout. The `@define-color` variables in
`noctalia-colors.css` override its color palette without touching widget structure.

**CSS load order:**
1. `adw-gtk3-dark` base theme — widget structure and fallback colors
2. `@import url("noctalia-colors.css")` — generated `@define-color` overrides
3. Custom rules in `gtk.css` — widget-specific tweaks using `@color_name` references

The custom rules in `gtk-3.0/gtk.css` use `@define-color` names (e.g. `@window_bg_color`) rather
than hardcoded hex, so they automatically track whatever scheme is active.

> **Note:** VS Code's CSS linter flags `@color_name` references as errors because it doesn't
> understand GTK's CSS extension syntax. This is suppressed by `"css.validate": false` in
> `.vscode/settings.json` — the file is correct for GTK.

---

## Qt Theming

Qt apps inherit the active GTK theme automatically. Set in two places for full session coverage:

**`~/.config/environment.d/qt.conf`** — PAM / systemd user session:
```ini
QT_QPA_PLATFORM=wayland
QT_QPA_PLATFORMTHEME=gtk3
```

**`~/.config/hypr/hyprland.conf`** — Hyprland compositor env:
```properties
env = QT_QPA_PLATFORM, wayland
env = QT_QPA_PLATFORMTHEME, gtk3
```

`qt6ct` is installed but inactive — `gtk3` passthrough takes precedence.

---

## GNOME dconf Accent Color

GTK's polkit agent and some other GTK3 apps read `/org/gnome/desktop/interface/accent-color`
from dconf at runtime and use it as the entry focus ring color — bypassing `@define-color`
overrides in user CSS. The value must match the active Noctalia primary hue.

`theme-sync.sh` sets this on every sync:
```bash
gsettings set org.gnome.desktop.interface accent-color 'purple'
```

Valid values: `blue` `teal` `green` `yellow` `orange` `red` `pink` `purple` `slate`

If you switch to a Noctalia scheme with a different dominant hue, update this line in
`theme-sync.sh` to match (e.g. `orange` for Everforest, `blue` for Tokyo Night).

---

## File Picker (xdg-desktop-portal)

VS Code and other portal-aware apps delegate open/save dialogs to `xdg-desktop-portal`.
`xdg-desktop-portal-gnome` (which uses Nautilus as the file picker) requires
`graphical-session.target` to be active — which UWSM activates automatically as part of
proper session management.

**Root cause of the janky picker:** SDDM was launching the plain `hyprland.desktop` session
(`Exec=/usr/bin/start-hyprland`), bypassing UWSM and leaving `graphical-session.target` inactive.
Fixed by two things:
1. Switching SDDM to the **`hyprland-uwsm.desktop`** session
2. Adding the missing `User=` field to `/etc/sddm.conf` (without it SDDM ignores `[Autologin]` entirely
   and shows the greeter, defaulting to the last manually-selected session)

`/etc/sddm.conf`:
```ini
[Autologin]
User=kirill
Session=hyprland-uwsm
```

With UWSM managing the session, `graphical-session.target` activates correctly and
`xdg-desktop-portal-gnome` starts, providing Nautilus as the file picker everywhere.

See [UWSM_SESSION.md](UWSM_SESSION.md) for the full UWSM dependency rationale, failure
detection, and troubleshooting steps.

Portal routing is configured in **`~/.config/xdg-desktop-portal/hyprland-portals.conf`**:
```ini
[preferred]
default=hyprland;gnome
org.freedesktop.impl.portal.FileChooser=gnome
```

`hyprland` handles Screenshot/ScreenCast/GlobalShortcuts natively; `gnome` handles everything else
including file dialogs (Nautilus), print, notifications, and account portals.

---

## Manual Resync

```bash
~/.config/hypr/scripts/theme-sync.sh
```

Useful after editing `colors.json` manually or if the watcher was down.

---

## Extending to New Apps

Add the app's color config to `theme-sync.sh` following the existing pattern:

1. Read the tokens you need (already available as `$mPrimary`, `$mSurface`, etc.)
2. Write the app's config file using a heredoc
3. Live-reload the app if it supports it (signal, IPC, or restart)

No template files needed — the script writes configs directly from shell variables.

---

## Related

- [UWSM_SESSION.md](UWSM_SESSION.md) — why UWSM is required for `graphical-session.target`, failure detection, and troubleshooting; `theme-watch.service` and `polkit-agent.service` both depend on this target
- [POLKIT_AGENT.md](../auth/POLKIT_AGENT.md) — polkit agent setup; `theme-sync.sh` restarts it on every sync because GTK3 has no CSS live-reload

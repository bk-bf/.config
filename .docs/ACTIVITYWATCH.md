# ActivityWatch — Time Tracking Setup

CachyOS (Hyprland/Wayland) time-tracking stack built around ActivityWatch, with per-project
opencode session tracking and a hand-tuned category tree visible in the Summary view.

---

## Architecture overview

```
Hyprland (exec-once)
├── aw-qt                          — AW tray daemon, manages aw-server + aw-watcher-afk
└── aw-watcher-window-wayland      — Wayland-native window watcher (replaces bundled watcher)

systemd --user
└── aw-watcher-opencode.service    — Custom watcher: tracks active opencode project
```

### Why not the bundled window watcher?

`aw-watcher-window` (bundled with AW) uses X11 APIs and produces no events under Wayland.
It is replaced by `aw-watcher-window-wayland-git` (AUR), which uses the Hyprland IPC socket.

The bundled watcher is excluded from `aw-qt` autostart so it does not conflict:

```toml
# ~/.config/activitywatch/aw-qt/aw-qt.toml
[aw-qt]
autostart_modules = ["aw-server", "aw-watcher-afk"]
```

`aw-watcher-window-wayland` is started directly by Hyprland:

```
# ~/.config/hypr/hyprland.conf  (~line 320)
exec-once = aw-qt
exec-once = aw-watcher-window-wayland
```

---

## Buckets

| Bucket ID | Type | Source |
|---|---|---|
| `aw-watcher-afk_cachyos-x8664` | `afkstatus` | aw-watcher-afk (via aw-qt) |
| `aw-watcher-window_cachyos-x8664` | `currentwindow` | aw-watcher-window-wayland |
| `aw-watcher-web-firefox_cachyos-x8664` | `web.tab.current` | Browser extension |
| `aw-watcher-opencode_cachyos-x8664` | `opencode.project` | aw-watcher-opencode |
| `aw-watcher-editor_cachyos-x8664` | `app.editor.activity` | aw-watcher-opencode |

The AW server listens on `127.0.0.1:5600` (not `localhost` — IPv6 resolves first and fails).

---

## aw-watcher-opencode

**Script:** `~/.local/bin/aw-watcher-opencode`
**Service:** `~/.config/systemd/user/aw-watcher-opencode.service`

### What it does

1. Polls the opencode SQLite DB (`~/.local/share/opencode/opencode.db`) every 5 seconds for
   the most recently updated non-archived session.
2. Only sends heartbeats while opencode is the focused window — checked by polling the
   `aw-watcher-window` bucket for the latest event and testing `app` / `title`.
3. Derives a project name from the session directory:
   - Git repo with GitHub/GitLab remote → last path component of `owner/repo`
   - Otherwise → `basename` of the directory
   - Leading dot stripped (`.config` → `config`)
4. Writes to two buckets:
   - `aw-watcher-opencode_*` (`opencode.project`) — primary project tracking
   - `aw-watcher-editor_*` (`app.editor.activity`) — feeds the AW Editor view with per-project
     time (uses the full directory path as the `project` field)
5. Sets the Alacritty terminal title to `opencode: <project>` via a PTY escape sequence so
   the window watcher picks up the project name. The PTY is located by resolving
   `/proc/<child-pid>/fd/0` for the shell child of the Alacritty process.
6. Auto-injects a per-project category rule (`Work > Programming > AI Coding > <project>`)
   into `settings.json` and pushes it live to the AW API the first time a new project is
   seen. Rules are appended at the end of the list (last-match-wins — see below).

### Focus detection

```python
OPENCODE_APPS   = {"opencode-desktop", "opencode"}   # app field matches
OPENCODE_TITLES = {"opencode", "opencode-desktop"}   # Alacritty title substring match
```

An Alacritty window whose title contains `opencode` or `opencode-desktop` also counts —
this covers the normal terminal workflow (`alacritty -e opencode`).

### Deduplication on startup

On startup the watcher reads existing category rules from the AW API and seeds
`known_projects` from any rule whose regex starts with `opencode: `. This prevents
re-injecting rules that were manually placed (e.g. under `Chore > config`).

### SIGTERM race guard

`systemd` sends SIGTERM to the old process on restart before the new one starts.
The new process ignores SIGTERM for the first 3 seconds (monotonic clock) to avoid
catching the stale signal from the previous unit.

### Service file

```ini
[Unit]
Description=ActivityWatch OpenCode project watcher
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/aw-watcher-opencode
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
```

Enable once: `systemctl --user enable --now aw-watcher-opencode`

---

## Category system

Settings live in `~/.config/activitywatch/aw-server/settings.json` under the `classes` key.
Push changes live without restarting AW:

```bash
curl -s http://127.0.0.1:5600/api/0/settings/classes \
  | python3 -c "import json,sys; print(len(json.load(sys.stdin)), 'rules')"

# To push a new classes list from settings.json:
python3 -c "
import json, urllib.request
s = json.load(open('/home/kirill/.config/activitywatch/aw-server/settings.json'))
data = json.dumps(s['classes']).encode()
req = urllib.request.Request('http://127.0.0.1:5600/api/0/settings/classes',
      data=data, method='POST', headers={'Content-Type': 'application/json'})
urllib.request.urlopen(req)
print('done')
"
```

### Critical: last-match-wins

AW's `categorize()` function uses **last-match-wins** at the same depth. A child rule
(longer name path) always beats its parent regardless of order. This means:

- **Catch-all rules must come early** (e.g. `Leisure > Browsing` with `^zen$`)
- **Specific overrides must come late** (e.g. `Research > Web` for Psychology titles,
  `Chore > config` for `opencode: config` titles)
- **New project rules are appended at the end** so they win over the generic
  `Work > Programming > AI Coding` catch-all

### Current rule order and palette

| # | Category | Colour | Rule |
|---|---|---|---|
| 0 | Work | `#4A148C` | (none) |
| 1 | Chore | `#F9A825` | (none) |
| 2 | Leisure | `#0D47A1` | (none) |
| 3 | Comms | `#29B6F6` | (none) |
| 4 | System | `#9E9E9E` | (none) |
| 5 | Uncategorized | `#616161` | (none) |
| 6 | Comms > IM | `#81D4FA` | `WhatsApp\|Discord\|Telegram\|Signal\|Slack\|…` |
| 7 | Comms > Email | `#B3E5FC` | `Gmail\|Thunderbird\|mutt\|…` |
| 8 | System > Settings | `#BDBDBD` | `pamac\|pavucontrol\|nm-applet\|…` |
| 9 | System > Monitor | `#E0E0E0` | `btop\|htop\|System Monitor\|…` |
| 10 | Leisure > Browsing | `#64B5F6` | `^zen$\|Zen Browser$` ← catch-all, early |
| 11 | Leisure > Music | `#1976D2` | `Spotify\|Deezer\|soundcloud` |
| 12 | Leisure > Games | `#1E88E5` | `Cataclysm\|Steam\|Minecraft\|…` |
| 13 | Leisure > Pictures | `#42A5F5` | `^feh\|imv\|eog\|…` |
| 14 | Work > Programming | `#6A1B9A` | (none) |
| 15 | Work > Programming > Terminal | `#8E24AA` | `Alacritty` |
| 16 | Work > Programming > AI Coding | `#AB47BC` | `opencode\|opencode-desktop\|OpenCode` |
| 17 | Work > Programming > GitHub | `#CE93D8` | `github\.com\|GitHub — \|bk-bf/\|…` |
| 18 | Work > Programming > Editor | `#E1BEE7` | `nvim\|neovim\|vim\|kate\|…` |
| 19 | Work > Documents | `#9C27B0` | `libreoffice\|Obsidian\|okular\|…` |
| 20 | Work > Design | `#BA68C8` | `GIMP\|Inkscape\|Figma\|Krita` |
| 21 | Leisure > Video | `#1565C0` | `YouTube\|mpv\|VLC\|Plex\|Twitch\|…` ← after Research so YouTube-in-zen wins |
| 22 | Research | `#1B5E20` | (none) |
| 23 | Research > Web | `#388E3C` | `Perplexity\|Psychology — Zen Browser\|Wikipedia\|arxiv\|…` |
| 24 | Chore > ActivityWatch | `#FDD835` | `ActivityWatch\|aw-` |
| 25 | Chore > config | `#FFEE58` | `opencode: config` |
| 26+ | Work > Programming > AI Coding > \<project\> | purple cycle | `opencode: <project>` (auto-injected) |

**Colour palette intent:**
- Work → purple shades (`#4A148C` … `#E1BEE7`)
- Research → green (`#1B5E20`, `#388E3C`) — top-level, not under Work
- Leisure → deep blue (`#0D47A1` … `#64B5F6`)
- Chore → yellow (`#F9A825` … `#FFEE58`)
- Comms → light blue (`#29B6F6` … `#B3E5FC`)
- System → grey

### Notable rule decisions

- `^zen$` matches the Zen Browser **app name field**, not the title. It fires for every
  Zen window. It is placed early (index 10) so later specific rules can override it.
- `Psychology — Zen Browser` is the title of the Perplexity space in Zen. It lands in
  `Research > Web` (index 23), which comes after Browsing (10), so Research wins.
- `YouTube|…` is in `Leisure > Video` (index 21), placed after `Research > Web` (23 would
  beat 21 — but Video is at 21 and Research at 23, so Research beats Video for any title
  matching both. YouTube titles don't match Research, so Video is fine).
- `opencode: config` (Chore > config) wins over `Alacritty` (Terminal) and `opencode`
  (AI Coding) because it is at index 25, later than both.
- `Work > Programming > AI Coding > <project>` rules are appended after index 25 and win
  over the generic AI Coding catch-all at index 16.

### Colour assignment for Top Apps / Top Titles widgets

The AW web UI colours each bar in Top Apps and Top Titles by running the app name or window
title through the same regex matching engine (`getCategoryColorFromString`). There is no
per-row "dominant category" colouring — each entry is coloured by whichever category rule
its name/title matches last. This means:

- `zen` → `Leisure > Browsing` → blue `#64B5F6`
- `Alacritty` → `Work > Programming > Terminal` → purple `#8E24AA`
- `opencode-desktop` → `Work > Programming > AI Coding` → purple `#AB47BC`
- `ActivityWatch — Zen Browser` → `Chore > ActivityWatch` → yellow `#FDD835`
- `opencode: config` → `Chore > config` → yellow `#FFEE58`
- `Psychology — Zen Browser` → `Research > Web` → green `#388E3C`

Changing this behaviour (colouring by dominant category of time in that app) would require
patching the compiled JS bundle in `/opt/activitywatch/aw-server/aw_server/static/js/` —
not worth doing given update fragility.

---

## Known limitations / deferred work

- **SSH session tracking** (ubuntu server) — not implemented
- **iPhone integration** — not implemented
- The `aw-watcher-web-firefox` bucket name still says `firefox` even though Zen Browser is
  used; this is cosmetic only

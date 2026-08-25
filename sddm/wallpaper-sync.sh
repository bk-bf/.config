#!/usr/bin/env bash
set -u

USER_HOME="/home/kirill"
STATE_JSON="$USER_HOME/.cache/noctalia/wallpapers.json"
DEST="/usr/share/sddm/themes/silent/backgrounds/wallpaper.png"

current_wallpaper() {
    python3 - "$STATE_JSON" <<'PY' 2>/dev/null
import json, sys
try:
    w = json.load(open(sys.argv[1])).get("wallpapers", {})
    for mon in w.values():
        p = mon.get("dark") or mon.get("light")
        if p:
            print(p); break
except Exception:
    pass
PY
}

apply() {
    local src; src="$(current_wallpaper)"
    [[ -n "$src" && -f "$src" ]] || return 0
    if   command -v magick  &>/dev/null; then magick  "$src" "$DEST" 2>/dev/null
    elif command -v convert &>/dev/null; then convert "$src" "$DEST" 2>/dev/null
    elif command -v ffmpeg  &>/dev/null; then ffmpeg -y -i "$src" "$DEST" &>/dev/null
    else install -m 0644 "$src" "$DEST"; fi
    chmod 0644 "$DEST" 2>/dev/null
    echo "[sddm-wallpaper] synced $src -> $DEST"
}

apply

WATCH_DIR="$(dirname "$STATE_JSON")"
while [[ ! -d "$WATCH_DIR" ]]; do sleep 2; done
inotifywait -m -e close_write -e moved_to --format '%f' "$WATCH_DIR" 2>/dev/null | while read -r f; do
    [[ "$f" == "wallpapers.json" ]] || continue
    sleep 0.3
    apply
done

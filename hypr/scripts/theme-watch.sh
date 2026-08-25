#!/usr/bin/env bash

COLORS_JSON="$HOME/.config/noctalia/colors.json"
WATCH_DIR="$HOME/.config/noctalia"
SYNC_SCRIPT="$HOME/.config/hypr/scripts/theme-sync.sh"

echo "[theme-watch] Watching $WATCH_DIR for colors.json changes"

while [[ ! -d "$WATCH_DIR" ]]; do
    sleep 1
done

inotifywait -m -e close_write -e moved_to --format '%f' "$WATCH_DIR" 2>/dev/null | while read -r filename; do
    [[ "$filename" != "colors.json" ]] && continue
    echo "[theme-watch] Detected change to colors.json — running sync"
    sleep 0.3
    "$SYNC_SCRIPT"
done

#!/usr/bin/env bash
# ~/.config/hypr/scripts/theme-watch.sh
# Watches ~/.config/noctalia/colors.json for changes and runs theme-sync.sh.
# Runs as a systemd user service (theme-watch.service).

COLORS_JSON="$HOME/.config/noctalia/colors.json"
WATCH_DIR="$HOME/.config/noctalia"
SYNC_SCRIPT="$HOME/.config/hypr/scripts/theme-sync.sh"

echo "[theme-watch] Watching $WATCH_DIR for colors.json changes"

# Wait for the directory to exist
while [[ ! -d "$WATCH_DIR" ]]; do
    sleep 1
done

# Watch the directory for close_write or moved_to (atomic rename) on colors.json
inotifywait -m -e close_write -e moved_to --format '%f' "$WATCH_DIR" 2>/dev/null | while read -r filename; do
    [[ "$filename" != "colors.json" ]] && continue
    echo "[theme-watch] Detected change to colors.json — running sync"
    # Small debounce: Noctalia may write the file multiple times in quick succession
    sleep 0.3
    "$SYNC_SCRIPT"
done

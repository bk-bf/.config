#!/usr/bin/env bash
# Notify-only clipboard watcher: consume stdin (wl-paste feeds it) and fire a notification.
# cliphist store is handled separately by qs/Noctalia.
cat > /dev/null
notify-send -t 1000 -u low "Clipboard" "Copied to clipboard"

#!/usr/bin/env bash
# swap-monitors.sh — swap the active workspaces shown on the two monitors.
# The content (workspaces) swaps between screens; the physical monitor layout
# and the mouse cursor stay put. Bound to SUPER+S in hyprland.conf.
set -euo pipefail

readarray -t mons < <(hyprctl monitors -j | jq -r '.[].name')

if (( ${#mons[@]} != 2 )); then
    notify-send -i video-display "Monitor swap" \
        "Need exactly 2 monitors (found ${#mons[@]})" -t 2500 2>/dev/null || true
    exit 0
fi

hyprctl dispatch swapactiveworkspaces "${mons[0]}" "${mons[1]}"

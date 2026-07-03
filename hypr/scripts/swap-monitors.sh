#!/usr/bin/env bash
# swap-monitors.sh — swap the left/right (positional) arrangement of the two
# connected monitors. Each monitor keeps its own resolution/refresh/scale; only
# their x/y positions are exchanged. Bound to SUPER+S in config/keybinds.lua.
set -euo pipefail

readarray -t M < <(hyprctl monitors -j \
    | jq -r '.[] | [.name, .width, .height, .refreshRate, .x, .y, .scale] | @tsv')

if (( ${#M[@]} != 2 )); then
    notify-send -i video-display "Monitor swap" \
        "Need exactly 2 monitors (found ${#M[@]})" -t 2500 2>/dev/null || true
    exit 0
fi

IFS=$'\t' read -r n1 w1 h1 r1 x1 y1 s1 <<< "${M[0]}"
IFS=$'\t' read -r n2 w2 h2 r2 x2 y2 s2 <<< "${M[1]}"

# Give each monitor the other's position; keep its own mode + scale.
hyprctl --batch "\
keyword monitor ${n1},${w1}x${h1}@${r1},${x2}x${y2},${s1} ; \
keyword monitor ${n2},${w2}x${h2}@${r2},${x1}x${y1},${s2}"

notify-send -i video-display "Monitor swap" "${n1} ↔ ${n2}" -t 2000 2>/dev/null || true

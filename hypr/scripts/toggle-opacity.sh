#!/usr/bin/env bash

DATA=$(hyprctl -j activewindow | python3 -c "import sys,json; w=json.load(sys.stdin); print(w['address'],w['class'])" 2>/dev/null)
ADDR=$(echo "$DATA" | awk '{print $1}')
[[ -z "$ADDR" ]] && exit 1

STATE_FILE="/tmp/hypr-opacity-${ADDR//0x/}"

if [[ -f "$STATE_FILE" ]]; then
    hyprctl dispatch setprop "address:$ADDR" opacity 0.7
    hyprctl dispatch setprop "address:$ADDR" opacity_override 1
    hyprctl dispatch setprop "address:$ADDR" opacity_inactive 0.7
    hyprctl dispatch setprop "address:$ADDR" opacity_inactive_override 1
    rm -f "$STATE_FILE"
else
    hyprctl dispatch setprop "address:$ADDR" opacity 1.0
    hyprctl dispatch setprop "address:$ADDR" opacity_override 1
    hyprctl dispatch setprop "address:$ADDR" opacity_inactive 1.0
    hyprctl dispatch setprop "address:$ADDR" opacity_inactive_override 1
    touch "$STATE_FILE"
fi

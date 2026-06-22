#!/usr/bin/env bash
# Toggle focused window between transparent (0.9 override) and fully opaque (1.0 override).
# Default state is transparent — windowrule sets kitty to 0.9 at spawn.
# State file present means we have forced it opaque; absent means transparent.
# Uses opacity + opacity_override (absolute, not multiplicative).

DATA=$(hyprctl -j activewindow | python3 -c "import sys,json; w=json.load(sys.stdin); print(w['address'],w['class'])" 2>/dev/null)
ADDR=$(echo "$DATA" | awk '{print $1}')
[[ -z "$ADDR" ]] && exit 1

STATE_FILE="/tmp/hypr-opacity-${ADDR//0x/}"

if [[ -f "$STATE_FILE" ]]; then
    # Currently opaque — restore transparency
    hyprctl dispatch setprop "address:$ADDR" opacity 0.7
    hyprctl dispatch setprop "address:$ADDR" opacity_override 1
    hyprctl dispatch setprop "address:$ADDR" opacity_inactive 0.7
    hyprctl dispatch setprop "address:$ADDR" opacity_inactive_override 1
    rm -f "$STATE_FILE"
else
    # Currently transparent — make opaque
    hyprctl dispatch setprop "address:$ADDR" opacity 1.0
    hyprctl dispatch setprop "address:$ADDR" opacity_override 1
    hyprctl dispatch setprop "address:$ADDR" opacity_inactive 1.0
    hyprctl dispatch setprop "address:$ADDR" opacity_inactive_override 1
    touch "$STATE_FILE"
fi

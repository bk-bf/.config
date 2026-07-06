#!/usr/bin/env bash
# CTRL+MOD+up/down window mover for the dwm-style scrolling layout.
#
# Moves the focused window within its vertical column stack; once the window is
# at the top/bottom of the column, pushes it to the adjacent workspace on the
# same monitor instead (up = lower number, down = higher number). Stops at the
# monitor's first/last workspace so a window never lands on the phantom ws 10
# gap between the two monitors.
#
# Workspace scheme (see ws-dwm.sh): DP-3 = 1-9, HDMI-A-1 = 11-19.
#
# Usage: ws-push.sh <up|down>
set -euo pipefail
dir=${1:?usage: ws-push.sh <up|down>}

active=$(hyprctl activewindow -j 2>/dev/null) || exit 0
addr=$(jq -r '.address // empty' <<<"$active")
[ -n "$addr" ] || exit 0

aws=$(jq -r '.workspace.id' <<<"$active")
ax=$(jq -r '.at[0]'   <<<"$active")
aw=$(jq -r '.size[0]' <<<"$active")
ay=$(jq -r '.at[1]'   <<<"$active")
floating=$(jq -r '.floating' <<<"$active")

mv=u; [ "$dir" = down ] && mv=d

# Floating windows: just nudge in that direction, never push across workspaces.
if [ "$floating" = "true" ]; then
  hyprctl dispatch movewindow "$mv"
  exit 0
fi

# Another tiled window in the same column (horizontal overlap) on the up/down
# side? If so, move within the stack.
neighbors=$(hyprctl clients -j | jq --arg addr "$addr" --argjson aws "$aws" \
  --argjson ax "$ax" --argjson aw "$aw" --argjson ay "$ay" --arg dir "$dir" '
  [ .[]
    | select(.address != $addr and .workspace.id == $aws and .floating == false)
    | select(.at[0] < ($ax + $aw) and (.at[0] + .size[0]) > $ax)
    | select(if $dir == "up" then .at[1] < $ay else .at[1] > $ay end)
  ] | length')

if [ "${neighbors:-0}" -gt 0 ]; then
  hyprctl dispatch movewindow "$mv"
  exit 0
fi

# At the edge of the column -> push to the adjacent workspace on this monitor.
base=0; { [ "$aws" -ge 11 ] && [ "$aws" -le 19 ]; } && base=10
idx=$((aws - base))                 # 1..9 within the monitor's block
if [ "$dir" = up ]; then
  [ "$idx" -le 1 ] && exit 0        # already on this monitor's first workspace
  target=$((base + idx - 1))
else
  [ "$idx" -ge 9 ] && exit 0        # already on this monitor's last workspace
  target=$((base + idx + 1))
fi
hyprctl dispatch movetoworkspace "$target"

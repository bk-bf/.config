#!/usr/bin/env bash
# dwm-style per-monitor workspaces for Hyprland.
#
# Each monitor gets its own independent 1-9 stack. To do this with Hyprland's
# global workspaces, the second monitor's workspaces live at ids 11-19 under
# the hood; Noctalia relabels them back to 1-9 in the bar (see
# noctalia/patch-workspace-numbers.sh). Pressing SUPER+<n> acts on the 1-9
# stack of whichever monitor currently has focus.
#
#   DP-3      -> workspaces 1-9   (offset 0)
#   HDMI-A-1  -> workspaces 11-19 (offset 10)
#
# Usage: ws-dwm.sh <switch|move|movesilent> <1-9>

set -euo pipefail

action=${1:?usage: ws-dwm.sh <switch|move|movesilent> <1-9>}
n=${2:?missing workspace number (1-9)}

# Map focused monitor -> workspace-id offset. Add monitors here if the layout
# grows; anything unlisted falls through to offset 0 (raw 1-9).
offset_for() {
  case "$1" in
    HDMI-A-1) echo 10 ;;
    *)        echo 0  ;;
  esac
}

focused=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
target=$(( n + $(offset_for "$focused") ))

case "$action" in
  switch)     hyprctl dispatch workspace "$target" ;;
  move)       hyprctl dispatch movetoworkspace "$target" ;;
  movesilent) hyprctl dispatch movetoworkspacesilent "$target" ;;
  *) echo "ws-dwm.sh: unknown action '$action'" >&2; exit 1 ;;
esac

#!/usr/bin/env bash
# Reopen the kitty windows saved by session-save.py — each on its workspace and
# re-running whatever it was running. Pure kitty, no multiplexer, so scrollback
# and selection behave exactly like a normal kitty.
#
# hyprflow restores every OTHER window class (kitty is in its ignore_classes),
# so this runs alongside `hyprflow restore` from hyprland.conf.
#
#   session-restore.sh [--dry-run]   # --dry-run prints the commands, opens nothing
set -euo pipefail

state="$HOME/.local/share/kitty-session/session.json"
win="$HOME/.config/kitty/session-window.sh"
dry=0
[ "${1:-}" = "--dry-run" ] && dry=1

[ -r "$state" ] || { echo "kitty-session: nothing saved yet"; exit 0; }

# Skip a stale snapshot, mirroring hyprflow's `restore --max-age 24h`.
saved=$(jq -r '.saved_at // 0' "$state")
now=$(date +%s)
if [ "$saved" -gt 0 ] && [ $((now - saved)) -gt $((24 * 3600)) ]; then
  echo "kitty-session: last snapshot >24h old, skipping restore"
  exit 0
fi

n=$(jq '.windows | length' "$state")
for ((i = 0; i < n; i++)); do
  ws=$(jq -r ".windows[$i].workspace" "$state")
  if [ "$dry" = 1 ]; then
    line=$(jq -r ".windows[$i] | \"ws=\(.workspace)  cwd=\(.cwd)  cmd=\(if .cmd == \"\" then \"<shell>\" else .cmd end)\"" "$state")
    echo "hyprctl dispatch exec \"[workspace $ws silent] $win $i\""
    echo "    -> $line"
  else
    hyprctl dispatch exec "[workspace $ws silent] $win $i"
    sleep 0.3  # let Hyprland place the window before the next (cf. hyprflow restore_delay)
  fi
done

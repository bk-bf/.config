#!/usr/bin/env bash
set -euo pipefail

state="$HOME/.local/share/kitty-session/session.json"
win="$HOME/.config/kitty/session-window.sh"
dry=0
[ "${1:-}" = "--dry-run" ] && dry=1

[ -r "$state" ] || { echo "kitty-session: nothing saved yet"; exit 0; }

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
    sleep 0.3
  fi
done

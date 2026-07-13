#!/usr/bin/env bash
# Launch one kitty window from the saved session (entry index $1). Invoked by
# session-restore.sh via:
#   hyprctl dispatch exec "[workspace N silent] session-window.sh <i>"
# so Hyprland places the window on the right workspace; this script restores the
# directory and re-runs whatever was running there.
#
# Set KITTY_SESSION_DRY=1 to print the kitty command instead of executing it.
set -euo pipefail

i="${1:?usage: session-window.sh <index>}"
state="$HOME/.local/share/kitty-session/session.json"
[ -r "$state" ] || exec kitty

cwd=$(jq -r ".windows[$i].cwd // empty" "$state")
cmd=$(jq -r ".windows[$i].cmd // empty" "$state")
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$HOME"

if [ -n "$cmd" ]; then
  # Re-run the program, then exec an interactive shell so the window stays
  # usable after the program exits (tmux-resurrect-style). $cmd is already
  # shell-quoted by session-save.py (shlex.join).
  set -- --directory "$cwd" zsh -c "$cmd; exec zsh"
else
  set -- --directory "$cwd"
fi

if [ "${KITTY_SESSION_DRY:-0}" = 1 ]; then
  printf 'kitty'; printf ' %q' "$@"; printf '\n'
  exit 0
fi
exec kitty "$@"

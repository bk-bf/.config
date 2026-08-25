#!/usr/bin/env bash
set -euo pipefail

i="${1:?usage: session-window.sh <index>}"
state="$HOME/.local/share/kitty-session/session.json"
[ -r "$state" ] || exec kitty

cwd=$(jq -r ".windows[$i].cwd // empty" "$state")
cmd=$(jq -r ".windows[$i].cmd // empty" "$state")
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$HOME"

if [ -n "$cmd" ]; then
  set -- --directory "$cwd" zsh -c "$cmd; exec zsh"
else
  set -- --directory "$cwd"
fi

if [ "${KITTY_SESSION_DRY:-0}" = 1 ]; then
  printf 'kitty'; printf ' %q' "$@"; printf '\n'
  exit 0
fi
exec kitty "$@"

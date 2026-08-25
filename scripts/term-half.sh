#!/usr/bin/env bash

term="${1:-kitty}"

hyprctl keyword scrolling:column_width 0.5 >/dev/null

old=$(hyprctl activewindow -j | jq -r '.address // ""')
"$term" &

for _ in $(seq 60); do
    sleep 0.05
    cur=$(hyprctl activewindow -j)
    addr=$(printf '%s' "$cur" | jq -r '.address // ""')
    cls=$(printf '%s' "$cur" | jq -r '.class // ""')
    [ "$addr" != "$old" ] && [ "$cls" = "$term" ] && break
done

hyprctl keyword scrolling:column_width 1.0 >/dev/null

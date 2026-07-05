#!/usr/bin/env bash
# term-half: open a terminal at half width while everything else defaults to
# full width.
#
# The scrolling layout has no per-class column width, so we reproduce the
# terminal's *previous* behavior faithfully: temporarily drop the global
# scrolling:column_width to 0.5 so the terminal's column is BORN at half width
# (exactly as it was before, no resize-after-the-fact and no viewport jump),
# then restore column_width to 1.0 so the next non-terminal window opens full.
#
# Logic lives here, not in an inline Hyprland variable, because Hyprland's
# config parser treats { } as block delimiters and would drop every keybind
# after a brace-containing line.

term="${1:-kitty}"

# Drop the default column width so the new terminal column is created at half.
hyprctl keyword scrolling:column_width 0.5 >/dev/null

old=$(hyprctl activewindow -j | jq -r '.address // ""')
"$term" &

# Wait (up to ~3s) until the new terminal is the active window, i.e. its column
# has been created at the half width, before restoring the full-width default.
for _ in $(seq 60); do
    sleep 0.05
    cur=$(hyprctl activewindow -j)
    addr=$(printf '%s' "$cur" | jq -r '.address // ""')
    cls=$(printf '%s' "$cur" | jq -r '.class // ""')
    [ "$addr" != "$old" ] && [ "$cls" = "$term" ] && break
done

# Restore the full-width default for subsequent (non-terminal) windows.
hyprctl keyword scrolling:column_width 1.0 >/dev/null

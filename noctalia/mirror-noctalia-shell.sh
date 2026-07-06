#!/usr/bin/env bash
# Shadow the noctalia-shell package in user config space so the bar relabels
# Hyprland workspaces 11-19 as 1-9 (the second monitor's dwm-style stack;
# see hypr/scripts/ws-dwm.sh) — without touching the root-owned package files.
#
# Quickshell searches ~/.config/quickshell before /etc/xdg, so this mirror wins.
# Everything is a symlink to the installed package EXCEPT
# Services/Compositor/HyprlandService.qml, which is a patched copy that maps the
# 11-19 id range down by 10 for display only (clicks still switch by name).
#
# Re-run this after a `noctalia-shell` upgrade to pick up new/renamed files.
# Revert completely with:  rm -rf ~/.config/quickshell/noctalia-shell
set -euo pipefail

SRC=/etc/xdg/quickshell/noctalia-shell
DST="$HOME/.config/quickshell/noctalia-shell"
PATCHED_REL=Services/Compositor/HyprlandService.qml

[ -d "$SRC" ] || { echo "mirror: package config $SRC not found" >&2; exit 1; }

rm -rf "$DST"
mkdir -p "$DST/Services/Compositor"

# Symlink every top-level entry except Services (we descend into it).
for e in "$SRC"/*; do
  n=$(basename "$e")
  [ "$n" = "Services" ] && continue
  ln -s "$e" "$DST/$n"
done

# Symlink every Services/ entry except Compositor (we descend into it).
for e in "$SRC"/Services/*; do
  n=$(basename "$e")
  [ "$n" = "Compositor" ] && continue
  ln -s "$e" "$DST/Services/$n"
done

# Symlink every Services/Compositor/ entry except the file we patch.
for e in "$SRC"/Services/Compositor/*; do
  n=$(basename "$e")
  [ "$n" = "HyprlandService.qml" ] && continue
  ln -s "$e" "$DST/Services/Compositor/$n"
done

# The one patched file: 11-19 -> 1-9 for display only.
sed 's|"idx": ws\.id,|"idx": (ws.id >= 11 \&\& ws.id <= 19) ? ws.id - 10 : ws.id,|' \
  "$SRC/$PATCHED_REL" > "$DST/$PATCHED_REL"

if grep -qF '"idx": (ws.id >= 11 && ws.id <= 19) ? ws.id - 10 : ws.id,' "$DST/$PATCHED_REL"; then
  echo "mirror: built $DST with workspace-number patch applied"
else
  echo "mirror: FAILED to patch HyprlandService.qml (upstream may have changed)" >&2
  exit 1
fi

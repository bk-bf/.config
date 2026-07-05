#!/usr/bin/env bash
# Relabel Hyprland workspaces 11-19 as 1-9 in Noctalia's bar.
#
# The dwm-style per-monitor workspace setup (hypr/scripts/ws-dwm.sh) puts the
# second monitor's stack on workspace ids 11-19. Noctalia's native Hyprland
# backend prints the raw id, so without this patch the second monitor's bar
# would read 11-19. This maps that range back to 1-9 for display only; clicks
# still switch by workspace name ("11".."19"), so navigation is unaffected.
#
# The target file is owned by the noctalia-shell package, so this patch is
# re-applied after every upgrade via the noctalia-ws-numbers pacman hook.
# Run as root (the hook runs as root; /etc is not user-writable).

set -euo pipefail

F=/etc/xdg/quickshell/noctalia-shell/Services/Compositor/HyprlandService.qml
patched='"idx": (ws.id >= 11 \&\& ws.id <= 19) ? ws.id - 10 : ws.id,'
check='"idx": (ws.id >= 11 && ws.id <= 19) ? ws.id - 10 : ws.id,'

if [ ! -f "$F" ]; then
  echo "patch-workspace-numbers: $F not found; skipping" >&2
  exit 0
fi

if grep -qF "$check" "$F"; then
  echo "patch-workspace-numbers: already applied"
  exit 0
fi

# Keep a pristine copy the first time we touch it.
[ -f "$F.orig" ] || cp -a "$F" "$F.orig"

sed -i 's|"idx": ws\.id,|'"$patched"'|' "$F"

if grep -qF "$check" "$F"; then
  echo "patch-workspace-numbers: applied to $F"
else
  echo "patch-workspace-numbers: FAILED to apply (upstream may have changed line 261)" >&2
  exit 1
fi

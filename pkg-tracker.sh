#!/bin/bash
# Tracks explicitly installed packages and auto-commits changes to the
# private git repo on the local server (~/.local/share/pkglist/).
# ~/.config/pkglist.txt is a symlink to the canonical file there.

PRIVATE_REPO="$HOME/.local/share/pkglist"
PKGLIST="$PRIVATE_REPO/pkglist.txt"

pacman -Qqe > "$PKGLIST"

cd "$PRIVATE_REPO" || exit 1

if ! git diff --quiet "$PKGLIST" 2>/dev/null || ! git ls-files --error-unmatch "$PKGLIST" &>/dev/null; then
    git add "$PKGLIST"
    git commit -m "chore: update pkglist.txt ($(date '+%Y-%m-%d %H:%M'))"
    git push
fi

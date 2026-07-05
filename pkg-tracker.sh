#!/bin/bash
# Tracks explicitly installed packages and auto-commits them to a private
# bare git repo on the local server (ubuntu:git/pkglist.git).
#
# Each machine writes to its own subdirectory — hosts/<tailscale-hostname>/ —
# so multiple machines share one repo without clobbering each other's list.
# The script bootstraps itself on a new machine: it clones the repo if missing
# and (re)points ~/.config/pkglist.txt at this host's canonical file.
set -uo pipefail

REMOTE="ubuntu:git/pkglist.git"
PRIVATE_REPO="$HOME/.local/share/pkglist"
CONFIG_LINK="$HOME/.config/pkglist.txt"

# Non-interactive git-over-ssh: fail fast instead of prompting, and auto-trust
# the server's host key so a fresh machine works straight from the pacman hook.
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

# --- resolve this machine's Tailscale hostname -------------------------------
ts_hostname() {
    local n=""
    if command -v tailscale >/dev/null 2>&1; then
        n=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' 2>/dev/null | cut -d. -f1)
        [ -z "$n" ] && n=$(tailscale status 2>/dev/null | awk 'NR==1{print $2}')
    fi
    [ -z "$n" ] && n=$(hostname)   # fallback if Tailscale is down
    printf '%s' "$n"
}
TS_HOST=$(ts_hostname)
if [ -z "$TS_HOST" ]; then
    echo "pkg-tracker: could not determine hostname" >&2
    exit 1
fi

# --- bootstrap the repo on a new machine -------------------------------------
if [ ! -d "$PRIVATE_REPO/.git" ]; then
    echo "pkg-tracker: cloning $REMOTE -> $PRIVATE_REPO"
    mkdir -p "$(dirname "$PRIVATE_REPO")"
    git clone "$REMOTE" "$PRIVATE_REPO" || { echo "pkg-tracker: clone failed" >&2; exit 1; }
fi

cd "$PRIVATE_REPO" || exit 1

# Ensure a commit identity exists (a fresh machine may have none configured).
git config user.name  >/dev/null 2>&1 || git config user.name  "$TS_HOST"
git config user.email >/dev/null 2>&1 || git config user.email "$TS_HOST@local"

HOST_DIR="$PRIVATE_REPO/hosts/$TS_HOST"
PKGLIST="$HOST_DIR/pkglist.txt"
mkdir -p "$HOST_DIR"

# (Re)point the convenience symlink at this host's list, replacing any stale
# plain file or wrong-target link left over from an earlier setup.
if [ ! -L "$CONFIG_LINK" ] || [ "$(readlink -f "$CONFIG_LINK")" != "$PKGLIST" ]; then
    ln -sfn "$PKGLIST" "$CONFIG_LINK"
fi

# --- regenerate list, commit + push only on change ---------------------------
pacman -Qqe > "$PKGLIST"

git add "$PKGLIST"
if ! git diff --cached --quiet -- "$PKGLIST"; then
    git commit -q -m "chore: update pkglist for $TS_HOST ($(date '+%Y-%m-%d %H:%M'))"
    # Integrate other machines' pushes first so ours isn't rejected.
    git pull --rebase --autostash -q 2>/dev/null
    git push -q || echo "pkg-tracker: push failed (will retry next run)" >&2
fi

exit 0

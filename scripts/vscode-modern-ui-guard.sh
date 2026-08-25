#!/usr/bin/env bash
set -euo pipefail

SETTINGS="${VSCODE_SETTINGS:-$HOME/.config/Code/User/settings.json}"
APP_DIR="${VSCODE_APP_DIR:-/usr/share/code/resources/app}"
BUNDLE="$APP_DIR/out/vs/workbench/workbench.desktop.main.js"
PKG="$APP_DIR/package.json"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/vscode-ui-guard"
COOLDOWN=${VSCODE_UI_GUARD_COOLDOWN:-21600}
CLAUDE_BIN=${CLAUDE_BIN:-claude}

DRY_RUN=0
FORCE=0
for arg in "$@"; do
	case "$arg" in
	--dry-run) DRY_RUN=1 ;;
	--force) FORCE=1 ;;
	*)
		echo "unknown argument: $arg" >&2
		exit 2
		;;
	esac
done

log() { printf '%s\n' "$*" >&2; }
notify() { command -v notify-send >/dev/null 2>&1 && notify-send -a vscode-ui-guard "$1" "${2:-}" || true; }

[[ -f "$SETTINGS" ]] || { log "no settings.json at $SETTINGS -- nothing to guard"; exit 0; }
[[ -f "$BUNDLE" ]] || { log "no VS Code bundle at $BUNDLE -- is code installed?"; exit 0; }

mkdir -p "$STATE"
KEY=$(cat "$STATE/key" 2>/dev/null || echo 'workbench.experimental.modernUI')
KEY_RE=${KEY//./\\.}

version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PKG" | head -1)
last_version=$(cat "$STATE/version" 2>/dev/null || true)

opted_out=0
grep -Eq "\"$KEY_RE\"[[:space:]]*:[[:space:]]*false" "$SETTINGS" && opted_out=1

key_known=1
if ((FORCE)) || [[ "$version" != "$last_version" ]]; then
	grep -Fq "\"$KEY\"" "$BUNDLE" || key_known=0
fi

if ((opted_out && key_known)); then
	printf '%s' "$version" >"$STATE/version"
	log "ok: $KEY is false, and VS Code $version still declares it"
	exit 0
fi

reason=""
((opted_out)) || reason+="settings.json no longer sets \"$KEY\" to false. "
((key_known)) || reason+="VS Code $version no longer declares \"$KEY\" -- it was renamed or dropped. "
log "drift: $reason"

if ((DRY_RUN)); then
	log "dry run: would hand off to Claude"
	exit 0
fi

now=$(date +%s)
last_run=$(cat "$STATE/last-claude" 2>/dev/null || echo 0)
if ((now - last_run < COOLDOWN)); then
	log "cooldown: last hand-off $(((now - last_run) / 60))min ago, staying quiet"
	exit 0
fi

command -v "$CLAUDE_BIN" >/dev/null 2>&1 || { log "claude CLI not on PATH"; exit 1; }
printf '%s' "$now" >"$STATE/last-claude"
notify "VS Code UI guard" "The modern-UI opt-out drifted. Asking Claude to repair settings.json."

read -r -d '' prompt <<EOF || true
VS Code's "modern UI" -- the rounded, bordered, detached workbench panels with
gaps between the sidebar, editor and side panel -- must stay OFF on this machine.
Something drifted:

$reason

VS Code version: $version
User settings:   $SETTINGS  (JSONC: it has comments and trailing commas -- preserve them)
Installed bundle: $BUNDLE
Guard state dir: $STATE

Do exactly this, and nothing else:

1. Work out which setting controls that look in THIS build. Start from the old
   key "$KEY" and follow any rename:
     grep -ohE '.{0,200}$KEY.{0,400}' "$BUNDLE" | head -5
   VS Code declares renames as ConfigurationMigration entries, and the live key
   appears in the configuration schema as {"<key>":{"type":"boolean",...}}.
2. Edit $SETTINGS so that key is set to false. If the old key is gone from the
   bundle, drop it while you are there. Change no other setting.
3. Write the live key name to $STATE/key (bare text, e.g. workbench.modernUI) so
   this guard checks the right key from now on.
4. If you cannot identify the replacement key with confidence, change nothing
   and say so plainly.

Touch no other file. Do not run git.
EOF

cd "$HOME"
"$CLAUDE_BIN" -p "$prompt" \
	--permission-mode acceptEdits \
	--allowedTools Read Edit Write Grep Glob "Bash(grep:*)" || log "claude exited non-zero"

KEY=$(cat "$STATE/key" 2>/dev/null || echo "$KEY")
KEY_RE=${KEY//./\\.}
if grep -Eq "\"$KEY_RE\"[[:space:]]*:[[:space:]]*false" "$SETTINGS"; then
	printf '%s' "$version" >"$STATE/version"
	log "repaired: $KEY is false"
	notify "VS Code UI guard" "Repaired -- $KEY is off. Reload the window to apply."
else
	log "unrepaired: $KEY is still not false in $SETTINGS"
	notify "VS Code UI guard" "Could not repair the modern-UI opt-out. Check: journalctl --user -u vscode-ui-guard"
fi

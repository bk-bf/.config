#!/usr/bin/env bash
set -euo pipefail

STATE_DB="${CLAUDE_VSCODE_STATE_DB:-$HOME/.config/Code/User/globalStorage/state.vscdb}"
SESSION_DIR="${CLAUDE_SESSION_DIR:-$HOME/.claude/sessions}"
MIN_AGE=${CLAUDE_VSCODE_GC_MIN_AGE:-120}

[[ -f "$STATE_DB" ]] || { echo "no state.vscdb at $STATE_DB"; exit 0; }

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

hidden_json=$(sqlite3 -readonly "$STATE_DB" \
    "select value from ItemTable where key='Anthropic.claude-code';" 2>/dev/null) || true
[[ -n "$hidden_json" ]] || { echo "extension state unreadable (VS Code mid-write?)"; exit 0; }

printf '%s' "$hidden_json" | DRY_RUN=$DRY_RUN SESSION_DIR=$SESSION_DIR MIN_AGE=$MIN_AGE python3 -c '
import json, os, sys, glob, signal

state = json.load(sys.stdin)
hidden = set(state.get("hiddenSessionIds", []))
if not hidden:
    print("no hidden sessions"); sys.exit(0)

dry = os.environ["DRY_RUN"] == "1"
min_age = int(os.environ["MIN_AGE"])
clk = os.sysconf("SC_CLK_TCK")
with open("/proc/uptime") as f:
    uptime = float(f.read().split()[0])

killed = 0
for path in sorted(glob.glob(os.path.join(os.environ["SESSION_DIR"], "*.json"))):
    try:
        s = json.load(open(path))
    except Exception:
        continue
    pid, sid = s.get("pid"), s.get("sessionId")
    if not pid or sid not in hidden:
        continue
    if s.get("entrypoint") != "claude-vscode":
        continue
    try:
        stat = open(f"/proc/{pid}/stat").read()
    except FileNotFoundError:
        os.unlink(path)
        continue
    starttime = int(stat[stat.rindex(")") + 2:].split()[19])
    recorded = s.get("procStart")
    if recorded is not None and str(starttime) != str(recorded):
        continue
    age = uptime - starttime / clk
    if age < min_age:
        continue
    name = s.get("name", "?")
    if dry:
        print(f"would kill pid {pid} ({name}) - session deleted in VS Code")
    else:
        try:
            os.kill(pid, signal.SIGTERM)
            print(f"killed pid {pid} ({name}) - session deleted in VS Code")
            killed += 1
        except ProcessLookupError:
            pass
        except PermissionError as e:
            print(f"cannot kill pid {pid}: {e}", file=sys.stderr)

if not dry:
    print(f"claude-vscode-session-gc: {killed} deleted session(s) terminated")
'

#!/usr/bin/env bash
# claude-reaper: terminate stale VS Code "Claude Code" extension processes.
#
# VS Code's Claude Code extension spawns a helper process per session but does
# NOT kill it when you delete the session in the UI -- they linger forever,
# accumulating and pushing the machine into swap. This reaps any such helper
# that has been alive longer than MAX_AGE (default 1 day), since anything that
# old is, by definition, a leaked orphan from a closed session.
#
# Usage: claude-reaper.sh [--dry-run]
set -euo pipefail

MAX_AGE=${CLAUDE_REAPER_MAX_AGE:-86400}   # seconds; default 24h
PATTERN='anthropic\.claude-code.*resources'
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

killed=0
# pgrep -f matches against full cmdline; only the extension helpers match this
# path, so the real interactive `claude` CLI and VS Code itself are untouched.
while read -r pid; do
    [[ -z "$pid" ]] && continue
    [[ "$pid" == "$$" ]] && continue
    age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ') || continue
    [[ -z "$age" ]] && continue
    if (( age > MAX_AGE )); then
        if (( DRY_RUN )); then
            echo "would reap pid $pid (age ${age}s)"
        else
            if kill "$pid" 2>/dev/null; then
                echo "reaped pid $pid (age ${age}s)"
                killed=$((killed + 1))
            fi
        fi
    fi
done < <(pgrep -f "$PATTERN" || true)

if (( DRY_RUN )); then
    echo "dry-run complete"
else
    echo "claude-reaper: $killed stale process(es) terminated"
fi

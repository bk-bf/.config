#!/usr/bin/env bash
set -euo pipefail

MAX_AGE=${CLAUDE_REAPER_MAX_AGE:-86400}
PATTERN='anthropic\.claude-code.*resources'
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

killed=0
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

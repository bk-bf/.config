#!/usr/bin/env bash
# Surface the failures this machine otherwise swallows — as noctalia toasts.
#
# Design rule (from the user): never notify on something already visible
# elsewhere. That excludes two whole categories:
#   - self-announcing crashes (a full session teardown: the screen dies, AND
#     this notifier dies with it since it's PartOf the graphical session, so the
#     toast can't even be delivered). Dropped.
#   - resource pressure (memory/CPU/swap): the system monitor already shows it.
#     No PSI/RSS polling here at all.
# What remains is discrete events with no other surface: a unit failed, a
# process dumped core, a sync got blocked, a disk filled, a process was
# OOM-killed (names the casualty, which the memory graph does not) — plus the
# case that motivated this whole thing: a SILENT ERROR STORM. qdbus errored 57×
# in 38 minutes for two days and nothing ever told the user. That's the highest-
# value signal precisely because it's invisible: see rate_check().
#
# Anti-spam, every layer measured against a real 91k-line journal replay:
#   allowlist   only the patterns below notify; no catch-all severity filter.
#   rate rule   anything NOT allowlisted but erroring fast is caught by volume.
#   cooldown    per (rule,subject), escalating — a chronically broken unit says
#               its piece a few times then goes quiet (516 raw -> ~12 toasts).
#   coalescing  repeats inside a cooldown are counted; next toast says "+N more".
#   burst cap   hard ceiling/min so a novel failure can't storm (critical bypasses).
#   grace       --since now + startup delay: a restart won't replay its own crash.

set -uo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/journal-notify"
mkdir -p "$STATE_DIR"

GRACE_SECONDS=10
BURST_MAX=4
BURST_WINDOW=60
DEFAULT_COOLDOWN=300
MAX_COOLDOWN=21600      # 6h ceiling on escalating backoff
STRIKE_RESET=43200      # 12h quiet clears the escalation
RATE_THRESHOLD=20       # >= N error lines from one identifier in RATE_WINDOW = a storm
RATE_WINDOW=60

declare -A RULE_URGENCY=(
  [oom]=critical  [coredump]=normal  [unitfail]=normal
  [osd]=normal    [diskfull]=critical [storm]=normal
)
declare -A RULE_COOLDOWN=(
  [oom]=60        [coredump]=300     [unitfail]=600
  [osd]=900       [diskfull]=600     [storm]=1800
)
declare -A RULE_TITLE=(
  [oom]="Process OOM-killed"  [coredump]="Process crashed"
  [unitfail]="Service failed" [osd]="Sync problem"
  [diskfull]="Disk full"      [storm]="Repeated errors"
)

started_at=$(date +%s)
sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'; }

burst_ok() {
  local now win f n
  now=$(date +%s); f="$STATE_DIR/.burst"; win=$((now - BURST_WINDOW))
  [[ -f $f ]] && { awk -v w="$win" '$1 > w' "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
  n=$(wc -l < "$f" 2>/dev/null || echo 0)
  (( n >= BURST_MAX )) && return 1
  echo "$now" >> "$f"; return 0
}

# Per-(rule,subject) cooldown with escalating backoff + coalescing.
# Prints " (+N more)" suffix on a fire that had suppressed repeats. Returns 0 to notify.
should_notify() {
  local key="$1" base="$2" now last count strikes f eff
  now=$(date +%s); f="$STATE_DIR/$(sanitize "$key")"
  last=0; count=0; strikes=0
  [[ -f $f ]] && read -r last count strikes < "$f" 2>/dev/null
  : "${last:=0}" "${count:=0}" "${strikes:=0}"
  (( now - last > STRIKE_RESET )) && strikes=0
  eff=$(( base << (strikes > 12 ? 12 : strikes) ))
  (( eff > MAX_COOLDOWN )) && eff=$MAX_COOLDOWN
  if (( now - last < eff )); then
    printf '%s %s %s\n' "$last" "$((count + 1))" "$strikes" > "$f"
    return 1
  fi
  printf '%s 0 %s\n' "$now" "$((strikes + 1))" > "$f"
  (( count > 0 )) && printf ' (+%d more)' "$count"
  return 0
}

notify() {
  local rule="$1" subject="$2" body="$3" suffix
  local urgency="${RULE_URGENCY[$rule]:-normal}"
  local cooldown="${RULE_COOLDOWN[$rule]:-$DEFAULT_COOLDOWN}"
  local title="${RULE_TITLE[$rule]:-$rule}"
  suffix=$(should_notify "$rule/$subject" "$cooldown") || return 0
  [[ $urgency != critical ]] && ! burst_ok && return 0
  notify-send -a "system" -u "$urgency" \
    "${title}${suffix}" "${subject}"$'\n'"${body:0:180}"
}

# The silent-storm catcher. Counts error-priority lines per identifier in a
# sliding window; on threshold, fires ONE toast and resets the window. Its
# escalating cooldown (storm=1800 base) means a persistent storm reports roughly
# every 30min, not every second. This is the rule that would have surfaced qdbus.
rate_check() {
  local ident="$1" body="$2" now f n
  now=$(date +%s); f="$STATE_DIR/rate.$(sanitize "$ident")"
  echo "$now" >> "$f"
  awk -v w=$((now - RATE_WINDOW)) '$1 > w' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  n=$(wc -l < "$f" 2>/dev/null || echo 0)
  if (( n >= RATE_THRESHOLD )); then
    notify storm "$ident" "$n+ errors/min — ${body}"
    : > "$f"          # reset; re-accumulate for the next window
  fi
}

# jq emits type-tagged, tab-safe records:
#   evt \t <rule> \t <subject> \t <body>     — an allowlist hit, notify now
#   rate\t <identifier> \t \t <body>         — unmatched but error-priority, count it
JQ_FILTER='
  (.MESSAGE // "") as $m
| (._SYSTEMD_UNIT // .UNIT // .SYSLOG_IDENTIFIER // "system") as $unit
| (.SYSLOG_IDENTIFIER // "") as $ident
| (.PRIORITY // "6" | tonumber) as $prio
| ( if   ($m | test("Out of memory: Killed process")) then
        {t:"evt", r:"oom", s:($m | capture("\\((?<n>[^)]+)\\)").n // "unknown"), b:$m}
    elif ($ident == "systemd-coredump") and ($m | test("dumped core")) then
        {t:"evt", r:"coredump", s:($m | capture("Process \\d+ \\((?<n>[^)]+)\\)").n // "unknown"), b:$m}
    elif ($m | test("Failed with result|status=203/EXEC")) then
        # The failing unit is in the MESSAGE text; ._SYSTEMD_UNIT is only the
        # emitting manager (user@1000.service), so keying on it collapses every
        # failure onto one subject. Also drop systemd-run transients (churn).
        # NOT matching "Failed to start <desc>." — systemd emits it alongside
        # "<unit>: Failed with result" for the same failure (265 dup hits).
        ( ($m | capture("^(?<u>[A-Za-z0-9@_.:\\\\-]+\\.(service|scope|socket|timer|mount|path)):").u // $unit) as $fu
        | if ($fu | test("^run-[pu]\\d+-i\\d+\\.service$|^run-r[a-f0-9]+\\.service$"))
          then empty else {t:"evt", r:"unitfail", s:$fu, b:$m} end )
    elif ($ident == "osd") and ($m | test("blocked|ERROR|Could not|failed"; "i")) then
        {t:"evt", r:"osd", s:$unit, b:$m}
    elif ($m | test("No space left on device")) then
        {t:"evt", r:"diskfull", s:$unit, b:$m}
    elif ($prio <= 3) and ($ident != "") and ($ident != "systemd") then
        # Not on the allowlist, but erroring at priority<=3 with a real
        # identifier: hand to the rate counter. This is the qdbus path.
        {t:"rate", r:$ident, s:"", b:$m}
    else empty end )
| "\(.t)\t\(.r)\t\(.s)\t\(.b | gsub("[\r\n\t]+"; " ") | .[0:200])"
'

journalctl -f -o json --since now --no-pager 2>/dev/null \
| jq -r --unbuffered "$JQ_FILTER" 2>/dev/null \
| while IFS=$'\t' read -r type a b body; do
    [[ -z ${type:-} ]] && continue
    (( $(date +%s) - started_at < GRACE_SECONDS )) && continue
    case "$type" in
      evt)  notify "$a" "$b" "$body" ;;   # a=rule, b=subject
      rate) rate_check "$a" "$body" ;;    # a=identifier
    esac
  done

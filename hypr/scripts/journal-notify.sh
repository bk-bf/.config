#!/usr/bin/env bash

set -uo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/journal-notify"
mkdir -p "$STATE_DIR"

GRACE_SECONDS=10
BURST_MAX=4
BURST_WINDOW=60
DEFAULT_COOLDOWN=300
MAX_COOLDOWN=21600
STRIKE_RESET=43200
RATE_THRESHOLD=20
RATE_WINDOW=60

CGROUP=/sys/fs/cgroup
SESSION_CG="$CGROUP/user.slice/user-$(id -u).slice/user@$(id -u).service/session.slice"
OOM_POLL=5
OOM_DEDUPE=30
PRESSURE_POLL=15
PRESSURE_PCT=10

declare -A RULE_URGENCY=(
  [oom]=critical  [coredump]=normal  [unitfail]=normal
  [osd]=normal    [diskfull]=critical [storm]=normal
  [pressure]=normal
)
declare -A RULE_COOLDOWN=(
  [oom]=60        [coredump]=300     [unitfail]=600
  [osd]=900       [diskfull]=600     [storm]=1800
  [pressure]=900
)
declare -A RULE_TITLE=(
  [oom]="App killed — out of RAM"    [coredump]="Process crashed"
  [unitfail]="Service failed"        [osd]="Sync problem"
  [diskfull]="Disk full"             [storm]="Repeated errors"
  [pressure]="Low RAM — apps may die soon"
)

app_name() {
  case "$1" in
    zen-bin|zen)                    echo "Zen Browser" ;;
    firefox|firefox-bin)            echo "Firefox" ;;
    "Isolated Web Co"|"Web Content") echo "browser tab" ;;
    WebExtensions)                  echo "browser extension" ;;
    code|code-oss|code-insiders)    echo "VS Code" ;;
    claude|claude-code)             echo "Claude Code" ;;
    [0-9]*.[0-9]*)                  echo "Claude Code" ;;
    chrome|chromium|thorium)        echo "Chromium" ;;
    vesktop|Discord|discord)        echo "Discord" ;;
    obsidian)                       echo "Obsidian" ;;
    spotify)                        echo "Spotify" ;;
    steam|steamwebhelper)           echo "Steam" ;;
    .kitty-wrapped|kitty)           echo "kitty" ;;
    quickshell|noctalia*)           echo "Noctalia" ;;
    Hyprland|hyprland)              echo "Hyprland" ;;
    *)                              echo "$1" ;;
  esac
}

swap_use() { free -g | awk '/^Swap:/ { print $3 "G/" $2 "G" }'; }

oom_detail() {
  local msg="$1" kb held
  kb=$(grep -oP 'anon-rss:\K[0-9]+' <<<"$msg" | head -1)
  [[ $kb =~ ^[0-9]+$ ]] || { printf '%s' "$msg"; return; }
  held=$(awk -v k="$kb" 'BEGIN { if (k >= 1048576) printf "%.1fG", k / 1048576
                                 else printf "%dM", k / 1024 }')
  printf 'was holding %s — the kernel killed it to free RAM · biggest now: %s · swap %s' \
    "$held" "$(top_consumers)" "$(swap_use)"
}

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

NOTIFY_LOG="${HOME}/.local/state/claude-status/notifications.jsonl"
notify_log() {
  mkdir -p "$(dirname "$NOTIFY_LOG")" 2>/dev/null || return 0
  python3 - "$@" <<'PY' >> "$NOTIFY_LOG" 2>/dev/null || true
import json, sys, time, os
rule, summary, subject, body, urgency = (sys.argv[1:6] + [""] * 5)[:5]
print(json.dumps({"app": "system", "rule": rule, "summary": summary,
                  "body": (subject + " " + body).strip()[:300],
                  "urgency": urgency, "ts": time.time()}))
PY
}

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
  if [[ $rule == oom ]]; then
    subject=$(app_name "$subject")
    date +%s > "$STATE_DIR/.last-oom"
  fi
  local cooldown="${RULE_COOLDOWN[$rule]:-$DEFAULT_COOLDOWN}"
  local title="${RULE_TITLE[$rule]:-$rule}"
  suffix=$(should_notify "$rule/$subject" "$cooldown") || return 0
  [[ $urgency != critical ]] && ! burst_ok && return 0
  notify_log "$rule" "${title}${suffix}" "${subject}" "$body" "$urgency"
  command -v notify-send >/dev/null 2>&1 && notify-send -a "system" -u "$urgency" \
    "${title}${suffix}" "${subject}"$'\n'"${body:0:180}"
  triage "$rule" "$subject" "$body"
}

WATCHER=~/.local/bin/watcher
triage() {
  [[ -x $WATCHER ]] || return 0
  setsid "$WATCHER" triage "$1" "$2" "$3" >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

rate_check() {
  local ident="$1" body="$2" now f n
  now=$(date +%s); f="$STATE_DIR/rate.$(sanitize "$ident")"
  echo "$now" >> "$f"
  awk -v w=$((now - RATE_WINDOW)) '$1 > w' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  n=$(wc -l < "$f" 2>/dev/null || echo 0)
  if (( n >= RATE_THRESHOLD )); then
    notify storm "$ident" "$n+ errors/min — ${body}"
    : > "$f"
  fi
}

top_consumers() {
  local rss name out=""
  while read -r rss name; do
    [[ -n $name ]] || continue
    out+="${out:+, }$(app_name "$name") $(awk -v k="$rss" 'BEGIN { printf "%.1fG", k / 1048576 }')"
  done < <(ps -eo rss=,comm= 2>/dev/null | awk '
    { name = $2; for (i = 3; i <= NF; i++) name = name " " $i
      sub(/-MainThread$/, "", name)
      sum[name] += $1 }
    END { for (n in sum) printf "%d %s\n", sum[n], n }' | sort -rn | head -3)
  printf '%s' "$out"
}

oom_victim() {
  local slice="$1" name deep
  name=$(journalctl -k --since "-2min" --no-pager -o cat 2>/dev/null \
         | grep -oiP 'out of memory: Killed process [0-9]+ \(\K[^)]+' | tail -1)
  [[ -n $name ]] && { printf '%s' "$name"; return; }
  deep=$(find "$CGROUP/$slice" -name memory.events.local \
           -exec awk '$1 == "oom_kill" && $2 > 0 { print FILENAME }' {} + 2>/dev/null \
         | awk '{ print length($0), $0 }' | sort -rn | head -1 | cut -d' ' -f2-)
  [[ -z $deep ]] && { printf '%s' "$slice"; return; }
  deep=${deep%/memory.events.local}
  printf '%s' "${deep##*/}"
}

watch_oom_counters() {
  local f slice base_file base cur last_oom
  while :; do
    for f in "$CGROUP"/*.slice/memory.events "$CGROUP"/init.scope/memory.events; do
      [[ -r $f ]] || continue
      cur=$(awk '$1 == "oom_kill" { print $2 }' "$f")
      [[ $cur =~ ^[0-9]+$ ]] || continue
      slice=${f%/memory.events}; slice=${slice#"$CGROUP"/}
      base_file="$STATE_DIR/oomcount.$(sanitize "$slice")"
      base=$(cat "$base_file" 2>/dev/null)
      printf '%s' "$cur" > "$base_file"
      [[ $base =~ ^[0-9]+$ ]] || continue
      (( cur <= base )) && continue
      last_oom=$(cat "$STATE_DIR/.last-oom" 2>/dev/null || echo 0)
      (( $(date +%s) - last_oom < OOM_DEDUPE )) && continue
      notify oom "$(oom_victim "$slice")" \
        "killed to free RAM ($((cur - base)) in $slice, no kernel log line survived) · biggest now: $(top_consumers) · swap $(swap_use)"
    done
    sleep "$OOM_POLL"
  done
}

watch_pressure() {
  local f="$SESSION_CG/memory.pressure" prev cur delta budget stall
  [[ -r $f ]] || return 0
  read_full_total() { awk '/^full/ { sub(/.*total=/, ""); print $1 }' "$f"; }
  prev=$(read_full_total)
  budget=$(( PRESSURE_POLL * 1000000 * PRESSURE_PCT / 100 ))
  while :; do
    sleep "$PRESSURE_POLL"
    cur=$(read_full_total)
    [[ $cur =~ ^[0-9]+$ ]] || continue
    delta=$(( cur - prev )); prev=$cur
    (( delta < budget )) && continue
    stall=$(awk -v d="$delta" 'BEGIN { printf "%.1f", d / 1000000 }')
    notify pressure "Hyprland session" \
      "stalled ${stall}s of the last ${PRESSURE_POLL}s swapping · biggest: $(top_consumers) · swap $(swap_use)"
  done
}

JQ_FILTER='
  (.MESSAGE // "") as $m
| (._SYSTEMD_USER_UNIT // ._SYSTEMD_UNIT // .UNIT // .SYSLOG_IDENTIFIER // "system") as $unit
| (.SYSLOG_IDENTIFIER // "") as $ident
| (.PRIORITY // "6" | tonumber) as $prio
| ( if   ($m | test("out of memory: Killed process"; "i")) then
        {t:"evt", r:"oom", s:($m | capture("\\((?<n>[^)]+)\\)").n // "unknown"), b:$m}
    elif ($ident == "systemd-oomd") and ($m | test("due to memory pressure")) then
        {t:"evt", r:"oom", s:(($m | capture("Killed (?<n>\\S+)").n // "unknown") | split("/") | last), b:$m}
    elif ($ident == "systemd-coredump") and ($m | test("dumped core")) then
        {t:"evt", r:"coredump", s:($m | capture("Process \\d+ \\((?<n>[^)]+)\\)").n // "unknown"), b:$m}
    elif ($m | test("Failed with result|status=203/EXEC")) then
        ( ($m | capture("^(?<u>[A-Za-z0-9@_.:\\\\-]+\\.(service|scope|socket|timer|mount|path)):").u // $unit) as $fu
        | if ($fu | test("^run-[pu]\\d+-i\\d+\\.service$|^run-r[a-f0-9]+\\.service$"))
          then empty else {t:"evt", r:"unitfail", s:$fu, b:$m} end )
    elif ($ident == "osd") and ($m | test("blocked|ERROR|Could not|failed|sync skipped|exceed the guard"; "i")) then
        {t:"evt", r:"osd", s:$unit, b:$m}
    elif ($m | test("No space left on device")) then
        {t:"evt", r:"diskfull", s:$unit, b:$m}
    elif ($prio <= 3) and ($ident != "") and ($ident != "systemd") and ($ident != "kernel") then
        {t:"rate", r:$ident, s:"-", b:$m}
    else empty end )
| "\(.t)\t\(.r)\t\(.s)\t\(.b | gsub("[\r\n\t]+"; " ") | .[0:200])"
'

watchers=()
watch_oom_counters & watchers+=($!)
watch_pressure &     watchers+=($!)
trap 'kill "${watchers[@]}" 2>/dev/null' EXIT

journalctl -f -o json --since now --no-pager 2>/dev/null \
| jq -r --unbuffered "$JQ_FILTER" 2>/dev/null \
| while IFS=$'\t' read -r type a b body; do
    [[ -z ${type:-} ]] && continue
    (( $(date +%s) - started_at < GRACE_SECONDS )) && continue
    case "$type" in
      evt)  if [[ $a == oom ]]; then notify oom "$b" "$(oom_detail "$body")"
            else notify "$a" "$b" "$body"; fi ;;
      rate) rate_check "$a" "$body" ;;
    esac
  done

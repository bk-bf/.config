#!/usr/bin/env bash
# Surface the failures this machine otherwise swallows — as noctalia toasts.
#
# Design rule (from the user): never notify on something already visible
# elsewhere. That excludes two whole categories:
#   - self-announcing crashes (a full session teardown: the screen dies, AND
#     this notifier dies with it since it's PartOf the graphical session, so the
#     toast can't even be delivered). Dropped.
#   - resource pressure (memory/CPU/swap): the system monitor already shows it.
#     One narrow exception, added deliberately — see watch_pressure().
# What remains is discrete events with no other surface: a unit failed, a
# process dumped core, a sync got blocked, a disk filled, a process was
# OOM-killed (names the casualty, which the memory graph does not) — plus the
# case that motivated this whole thing: a SILENT ERROR STORM. qdbus errored 57×
# in 38 minutes for two days and nothing ever told the user. That's the highest-
# value signal precisely because it's invisible: see rate_check().
#
# An OOM kill is watched three ways, because the obvious one is not dependable:
#   journal   the kernel's "Killed process" line, when journald keeps it
#   counters  cgroup memory.events oom_kill — authoritative, survives a lost
#             log line and a restart of this notifier (watch_oom_counters)
#   pressure  the reclaim stall that precedes the kill (watch_pressure)
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

CGROUP=/sys/fs/cgroup
SESSION_CG="$CGROUP/user.slice/user-$(id -u).slice/user@$(id -u).service/session.slice"
OOM_POLL=5              # how often the cgroup kill counters are re-read
OOM_DEDUPE=30           # counter bump this soon after a journal OOM = same event
PRESSURE_POLL=15
PRESSURE_PCT=10         # session fully stalled for >= N% of the window = thrashing

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

# What the kernel calls a process is not what the user calls an app: comm is
# truncated to 15 chars, browsers are named after their binary, and Claude Code's
# comm is its bare version string ("2.1.218"). Map what actually runs on this
# machine; anything unmapped passes through as-is rather than being guessed at.
app_name() {
  case "$1" in
    zen-bin|zen)                    echo "Zen Browser" ;;
    firefox|firefox-bin)            echo "Firefox" ;;
    "Isolated Web Co"|"Web Content") echo "browser tab" ;;
    WebExtensions)                  echo "browser extension" ;;
    code|code-oss|code-insiders)    echo "VS Code" ;;
    claude|claude-code)             echo "Claude Code" ;;
    [0-9]*.[0-9]*)                  echo "Claude Code" ;;   # comm is its version
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

# The kernel line is a dump — total-vm, file-rss, shmem-rss, pgtables,
# oom_score_adj — and pasting it into a toast is how you get a notification
# nobody can read. anon-rss is the only figure that answers the question being
# asked ("how much was it holding?"), so keep that, name the killer plainly, and
# append what is still large: the next casualty is usually already in that list.
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
  # Both OOM paths hand over a raw comm, so translating here covers both.
  # Stamped even when the cooldown swallows the toast: it means the journal has
  # already had its say about this kill, so watch_oom_counters must stay quiet
  # rather than announce the same corpse under a cgroup name.
  if [[ $rule == oom ]]; then
    subject=$(app_name "$subject")
    date +%s > "$STATE_DIR/.last-oom"
  fi
  local cooldown="${RULE_COOLDOWN[$rule]:-$DEFAULT_COOLDOWN}"
  local title="${RULE_TITLE[$rule]:-$rule}"
  suffix=$(should_notify "$rule/$subject" "$cooldown") || return 0
  [[ $urgency != critical ]] && ! burst_ok && return 0
  notify-send -a "system" -u "$urgency" \
    "${title}${suffix}" "${subject}"$'\n'"${body:0:180}"
  triage "$rule" "$subject" "$body"
}

# Hand anything that got past every filter above to watcher, which decides
# whether it is worth a headless Claude Code session (`watcher doctor` shows
# which rules it acts on — oom and pressure are deliberately not among them).
# Detached and failure-tolerant on purpose: triage is a bonus on top of the
# toast, and must never be able to delay or break the notification path.
WATCHER=~/.local/bin/watcher
triage() {
  [[ -x $WATCHER ]] || return 0
  setsid "$WATCHER" triage "$1" "$2" "$3" >/dev/null 2>&1 &
  disown 2>/dev/null || true
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

# Biggest RAM consumers, summed per program name — the number a "why is my
# machine dying" toast actually needs. Summing matters: a browser's memory is
# spread over dozens of content processes, none of which looks big alone.
# Names go through app_name for the same reason the OOM subject does.
top_consumers() {
  local rss name out=""
  while read -r rss name; do
    [[ -n $name ]] || continue
    out+="${out:+, }$(app_name "$name") $(awk -v k="$rss" 'BEGIN { printf "%.1fG", k / 1048576 }')"
  done < <(ps -eo rss=,comm= 2>/dev/null | awk '
    # comm can contain spaces ("Isolated Web Co"), so rebuild it from $2..$NF
    # instead of taking $2 and silently summing several programs together.
    { name = $2; for (i = 3; i <= NF; i++) name = name " " $i
      sub(/-MainThread$/, "", name)      # node/electron thread naming, not a program
      sum[name] += $1 }
    END { for (n in sum) printf "%d %s\n", sum[n], n }' | sort -rn | head -3)
  printf '%s' "$out"
}

# Name a kill that only the counters saw. Best case the kernel line is still in
# the journal (names the process); failing that, the deepest cgroup still
# carrying a local kill; failing that, the slice. The victim's own cgroup is
# usually already gone by now — that is why the parent's counter is what we poll.
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

# The kernel's OOM message is not a dependable trigger. journald can lose it in
# the reclaim storm that caused the kill, and this notifier — 64M ceiling, in the
# same starving session — may itself be a casualty and come back with
# "--since now" already past the line. cgroup memory.events.oom_kill has neither
# problem: it is a counter, so a kill is still there to be found seconds or a
# restart later. Polled from the top-level slices, whose counts are hierarchical
# and therefore cover every descendant.
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
      # First sight of this cgroup: adopt the count silently. Without this a
      # fresh login would replay every kill since boot as news.
      [[ $base =~ ^[0-9]+$ ]] || continue
      # Equal is the common case; lower means the cgroup was recreated and its
      # counter restarted from zero. Neither is a new kill.
      (( cur <= base )) && continue
      last_oom=$(cat "$STATE_DIR/.last-oom" 2>/dev/null || echo 0)
      (( $(date +%s) - last_oom < OOM_DEDUPE )) && continue
      notify oom "$(oom_victim "$slice")" \
        "killed to free RAM ($((cur - base)) in $slice, no kernel log line survived) · biggest now: $(top_consumers) · swap $(swap_use)"
    done
    sleep "$OOM_POLL"
  done
}

# The one resource-pressure exception to this file's design rule, and the reason
# is specific: when a kill leaves no log line there is nothing left to name
# afterwards, and the reclaim stall in front of it is the only warning that
# arrives while there is still something to do about it. Kept from becoming a
# nag by (a) triggering on FULL stall — every task in the session blocked, not
# merely busy — for a tenth of the window, which on this machine is a rare
# reading, and (b) the same escalating cooldown as everything else. Earns its
# place over a system monitor by naming the hog and the swap number.
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
    # The measurement belongs in the body, not the subject: cooldowns are keyed
    # on (rule, subject), so a subject carrying the stall figure would mint a
    # fresh key every window and toast forever through a long thrash.
    notify pressure "Hyprland session" \
      "stalled ${stall}s of the last ${PRESSURE_POLL}s swapping · biggest: $(top_consumers) · swap $(swap_use)"
  done
}

# jq emits type-tagged, tab-safe records:
#   evt \t <rule> \t <subject> \t <body>     — an allowlist hit, notify now
#   rate\t <identifier> \t \t <body>         — unmatched but error-priority, count it
JQ_FILTER='
  (.MESSAGE // "") as $m
  # _SYSTEMD_USER_UNIT first: for anything a --user unit runs, _SYSTEMD_UNIT is
  # the manager (user@1000.service), so preferring it named every osd sync job
  # "user@1000.service" and collapsed them all onto one cooldown key.
| (._SYSTEMD_USER_UNIT // ._SYSTEMD_UNIT // .UNIT // .SYSLOG_IDENTIFIER // "system") as $unit
| (.SYSLOG_IDENTIFIER // "") as $ident
| (.PRIORITY // "6" | tonumber) as $prio
| ( if   ($m | test("out of memory: Killed process"; "i")) then
        # Case-insensitive on purpose. A global OOM logs "Out of memory: Killed
        # process 123 (zen-bin)"; a cgroup OOM logs "Memory cgroup out of
        # memory: Killed process 123 (zen-bin)" — lowercase o, so the old
        # capitalised pattern matched none of them.
        {t:"evt", r:"oom", s:($m | capture("\\((?<n>[^)]+)\\)").n // "unknown"), b:$m}
    elif ($ident == "systemd-oomd") and ($m | test("due to memory pressure")) then
        # oomd is disabled on this machine; matched anyway so enabling it later
        # cannot quietly create an unwatched kill path.
        # oomd names a whole cgroup path; the leaf is the readable part.
        {t:"evt", r:"oom", s:(($m | capture("Killed (?<n>\\S+)").n // "unknown") | split("/") | last), b:$m}
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
    elif ($ident == "osd") and ($m | test("blocked|ERROR|Could not|failed|sync skipped|exceed the guard"; "i")) then
        # "sync skipped"/"exceed the guard" were the gap: the deletion guard
        # writes "<job>: N deletions exceed the guard of M — sync skipped." and
        # none of the original four patterns appears in that sentence, so the
        # most actionable osd event on this machine only ever surfaced as the
        # generic unitfail toast, with the reason missing.
        # (No apostrophes in this block: JQ_FILTER is single-quoted.)
        {t:"evt", r:"osd", s:$unit, b:$m}
    elif ($m | test("No space left on device")) then
        {t:"evt", r:"diskfull", s:$unit, b:$m}
    elif ($prio <= 3) and ($ident != "") and ($ident != "systemd") and ($ident != "kernel") then
        # Not on the allowlist, but erroring at priority<=3 with a real
        # identifier: hand to the rate counter. This is the qdbus path.
        #
        # "kernel" is excluded because it is bursty by design and every burst is
        # one event, not a storm: a single OOM kill dumps ~25 error-priority
        # lines (meminfo, the task table, the oom-kill: summary), which tripped
        # RATE_THRESHOLD and stapled a junk "Repeated errors: kernel" toast onto
        # every OOM — on top of the real one. Same for ACPI error spam. Kernel
        # events worth hearing about have explicit rules above.
        #
        # Subject is "-" rather than "": tab is IFS whitespace downstream, so
        # consecutive tabs collapse and an empty field would shift the body up
        # into it, arriving as a toast with no message at all.
        {t:"rate", r:$ident, s:"-", b:$m}
    else empty end )
| "\(.t)\t\(.r)\t\(.s)\t\(.b | gsub("[\r\n\t]+"; " ") | .[0:200])"
'

# The counter and pressure watchers poll, so they run alongside the journal
# stream rather than inside it. No GRACE_SECONDS for them: watch_oom_counters
# reporting a kill it finds in its first pass is the point, not a replay bug —
# that pass is what catches a kill this notifier was dead for.
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
      # a=rule, b=subject. The kernel's OOM dump is the one body worth rewriting
      # before it reaches a human; everything else already reads as a sentence.
      evt)  if [[ $a == oom ]]; then notify oom "$b" "$(oom_detail "$body")"
            else notify "$a" "$b" "$body"; fi ;;
      rate) rate_check "$a" "$body" ;;    # a=identifier
    esac
  done

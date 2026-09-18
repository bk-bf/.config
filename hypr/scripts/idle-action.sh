#!/bin/bash

MODE=${1:-}
QUIET_S=${IDLE_ACTION_QUIET_S:-600}
LID_S=${IDLE_ACTION_LID_S:-30}
POLL_S=${IDLE_ACTION_POLL_S:-30}
DRY_RUN=${IDLE_ACTION_DRY_RUN:-0}
STATE_DIR=${IDLE_ACTION_STATE_DIR:-${XDG_RUNTIME_DIR:-/tmp}/idle-action}

log() { logger -t idle-action "$*"; }

fullscreen_windows() {
    hyprctl clients -j 2>/dev/null | python3 -c \
        "import sys,json;print(','.join((c.get('class') or '?')+':'+(c.get('title') or '')[:40] for c in json.load(sys.stdin) if c.get('fullscreen')))" \
        2>/dev/null
}

audio_by_state() {
    pactl -f json list sink-inputs 2>/dev/null | python3 -c \
        "import sys,json;want='$1';d=json.load(sys.stdin);print(','.join((i.get('properties',{}).get('application.name') or '?')+(':corked' if i.get('corked') else ':playing') for i in d if bool(i.get('corked'))==(want!='playing')))" \
        2>/dev/null
}

lid_state() {
    awk '{print $2}' /proc/acpi/button/lid/LID0/state 2>/dev/null
}

lid_switch_state() {
    python3 - <<'LIDPY' 2>/dev/null || echo unknown
import fcntl, array, glob, os
EVIOCGSW = (2 << 30) | (8 << 16) | (0x45 << 8) | 0x1b
for dev in sorted(glob.glob('/dev/input/event*')):
    try:
        name = open('/sys/class/input/%s/device/name' % os.path.basename(dev)).read().strip()
    except OSError:
        continue
    if name != 'Lid Switch':
        continue
    buf = array.array('B', [0] * 8)
    try:
        with open(dev, 'rb') as fd:
            fcntl.ioctl(fd, EVIOCGSW, buf, True)
    except OSError:
        print('unknown')
        break
    print('closed' if buf[0] & 1 else 'open')
    break
else:
    print('unknown')
LIDPY
}

lid_is_closed() {
    [[ $(lid_state) == closed || $(lid_switch_state) == closed ]]
}

do_suspend() {
    local why=$1
    log "suspend: $why; audio=[$(audio_by_state playing)]; fullscreen=[$(fullscreen_windows)]; lid=$(lid_state)"
    if [[ $DRY_RUN == 1 ]]; then
        log "suspend: dry run, not suspending"
    else
        systemctl suspend
    fi
}

stop_timer() {
    local name=$1 pidfile=$STATE_DIR/$1.pid pid
    [[ -r $pidfile ]] || return 0
    pid=$(<"$pidfile")
    rm -f "$pidfile"
    if [[ -n $pid ]] && kill "$pid" 2>/dev/null; then
        log "$name: cancelled"
    fi
    return 0
}

start_timer() {
    local name=$1
    mkdir -p "$STATE_DIR"
    stop_timer "$name"
    setsid bash "$0" "$name-run" >/dev/null 2>&1 &
}

claim_timer() {
    mkdir -p "$STATE_DIR"
    echo $$ > "$STATE_DIR/$1.pid"
}

release_timer() {
    rm -f "$STATE_DIR/$1.pid"
}

audio_timer() {
    local quiet_since=0 playing now
    claim_timer audio-wait
    while :; do
        sleep "$POLL_S"
        playing=$(audio_by_state playing)
        now=$(date +%s)
        if [[ -n $playing ]]; then
            if (( quiet_since != 0 )); then
                log "audio-wait: audio started again [$playing], countdown reset"
            fi
            quiet_since=0
            continue
        fi
        if (( quiet_since == 0 )); then
            quiet_since=$now
            log "audio-wait: audio stopped, ${QUIET_S} s countdown started"
            continue
        fi
        if (( now - quiet_since >= QUIET_S )); then
            release_timer audio-wait
            do_suspend "${QUIET_S} s idle with no audio"
            return
        fi
    done
}

lid_timer() {
    local waited=0
    claim_timer lid-wait
    while (( waited < LID_S )); do
        sleep 5
        waited=$(( waited + 5 ))
        if ! lid_is_closed; then
            release_timer lid-wait
            log "lid-wait: lid reads open after ${waited} s, not suspending"
            return
        fi
    done
    release_timer lid-wait
    do_suspend "lid closed for ${LID_S} s"
}

case "$MODE" in
    screen-off|lock)
        fs=$(fullscreen_windows)
        playing=$(audio_by_state playing)
        if [[ -n $fs || -n $playing ]]; then
            log "$MODE: skipped; fullscreen=[$fs]; audio=[$playing]; lid=$(lid_state)"
            exit 0
        fi
        log "$MODE: running; fullscreen=[]; audio=[]; lid=$(lid_state)"
        if [[ $MODE == screen-off ]]; then
            hyprctl dispatch dpms off
        else
            loginctl lock-session
        fi
        ;;
    idle-suspend)
        stop_timer audio-wait
        playing=$(audio_by_state playing)
        if [[ -n $playing ]]; then
            log "audio-wait: waiting for audio to stop; audio=[$playing]; fullscreen=[$(fullscreen_windows)]"
            start_timer audio-wait
            exit 0
        fi
        do_suspend "${QUIET_S} s idle with no audio"
        ;;
    idle-active)
        stop_timer audio-wait
        ;;
    lid-closed)
        if ! lid_is_closed; then
            log "lid-closed: ignored, lid reads acpi=$(lid_state) switch=$(lid_switch_state)"
            exit 0
        fi
        log "lid-wait: lid closed, suspending in ${LID_S} s"
        start_timer lid-wait
        ;;
    lid-open)
        stop_timer lid-wait
        ;;
    audio-wait-run)
        audio_timer
        ;;
    lid-wait-run)
        lid_timer
        ;;
    before-sleep)
        log "before-sleep: start"
        qs -c noctalia-shell ipc call lockScreen lock
        log "before-sleep: lock call returned $?"
        sleep 1
        log "before-sleep: done"
        ;;
    *)
        echo "Usage: $0 {screen-off|lock|idle-suspend|idle-active|lid-closed|lid-open|before-sleep}" >&2
        exit 2
        ;;
esac

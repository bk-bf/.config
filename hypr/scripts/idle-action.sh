#!/bin/bash

MODE=${1:-}

fullscreen_windows() {
    hyprctl clients -j 2>/dev/null | python3 -c \
        "import sys,json;print(','.join((c.get('class') or '?')+':'+(c.get('title') or '')[:40] for c in json.load(sys.stdin) if c.get('fullscreen')))" \
        2>/dev/null
}

audio_by_state() {
    pactl -f json list sink-inputs 2>/dev/null | python3 -c \
        "import sys,json;want='$1';d=json.load(sys.stdin);print(','.join((i.get('properties',{}).get('application.name') or '?')+':'+(i.get('state') or '?') for i in d if ((i.get('state') or '').upper()=='RUNNING')==(want=='running')))" \
        2>/dev/null
}

lid_state() {
    awk '{print $2}' /proc/acpi/button/lid/LID0/state 2>/dev/null
}

run_or_skip() {
    local mode=$1 fs running other lid
    fs=$(fullscreen_windows)
    running=$(audio_by_state running)
    other=$(audio_by_state other)
    lid=$(lid_state)
    if [[ -n $fs || -n $running ]]; then
        logger -t idle-action "$mode: skipped; fullscreen=[$fs]; audio_running=[$running]; audio_idle=[$other]; lid=$lid"
        return 1
    fi
    logger -t idle-action "$mode: running; fullscreen=[]; audio_running=[]; audio_idle=[$other]; lid=$lid"
    return 0
}

case "$MODE" in
    screen-off)
        run_or_skip screen-off && hyprctl dispatch dpms off
        ;;
    lock)
        run_or_skip lock && loginctl lock-session
        ;;
    suspend)
        run_or_skip suspend && systemctl suspend
        ;;
    before-sleep)
        logger -t idle-action "before-sleep: start"
        qs -c noctalia-shell ipc call lockScreen lock
        logger -t idle-action "before-sleep: lock call returned $?"
        sleep 1
        logger -t idle-action "before-sleep: done"
        ;;
    *)
        echo "Usage: $0 {screen-off|lock|suspend|before-sleep}" >&2
        exit 2
        ;;
esac

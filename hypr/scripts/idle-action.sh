#!/bin/bash

MODE=${1:-}

has_fullscreen_window() {
    hyprctl clients -j 2>/dev/null | python3 -c \
        "import sys,json; clients=json.load(sys.stdin); exit(0 if any(c.get('fullscreen') for c in clients) else 1)" \
        2>/dev/null
}

has_active_audio() {
    pactl list sink-inputs 2>/dev/null | grep -q "State: RUNNING"
}

should_skip_media_idle_action() {
    has_fullscreen_window || has_active_audio
}

case "$MODE" in
    screen-off)
        if should_skip_media_idle_action; then
            exit 0
        fi
        hyprctl dispatch dpms off
        ;;
    lock)
        if should_skip_media_idle_action; then
            exit 0
        fi
        loginctl lock-session
        ;;
    suspend)
        if should_skip_media_idle_action; then
            exit 0
        fi
        systemctl suspend
        ;;
    before-sleep)
        if has_fullscreen_window; then
            exit 0
        fi
        qs -c noctalia-shell ipc call lockScreen lock
        sleep 1
        ;;
    *)
        echo "Usage: $0 {screen-off|lock|suspend|before-sleep}" >&2
        exit 2
        ;;
esac
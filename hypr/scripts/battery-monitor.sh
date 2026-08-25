#!/bin/bash


BATTERY_PATH="/sys/class/power_supply/BAT1"
CHECK_INTERVAL=30
STATE_FILE="/tmp/battery_monitor_state"

if [ ! -f "$STATE_FILE" ]; then
    echo "100" > "$STATE_FILE"
fi

get_battery_level() {
    if [ -f "$BATTERY_PATH/capacity" ]; then
        cat "$BATTERY_PATH/capacity"
    else
        echo "100"
    fi
}

get_battery_status() {
    if [ -f "$BATTERY_PATH/status" ]; then
        cat "$BATTERY_PATH/status"
    else
        echo "Unknown"
    fi
}

send_notification() {
    local level=$1
    local urgency=$2
    
    if [ "$level" -le 5 ]; then
        notify-send -u critical "Battery Critical: ${level}%" "Please plug in your charger immediately!"
    elif [ "$level" -eq 10 ]; then
        notify-send -u critical "Battery Low: ${level}%" "Battery is running low. Please charge soon."
    fi
}

while true; do
    battery_level=$(get_battery_level)
    battery_status=$(get_battery_status)
    last_notified=$(cat "$STATE_FILE")
    
    if [ "$battery_status" = "Discharging" ]; then
        if [ "$battery_level" -le 10 ] && [ "$battery_level" -lt "$last_notified" ]; then
            if [ "$battery_level" -eq 10 ] || [ "$battery_level" -eq 5 ] || [ "$battery_level" -lt 5 ]; then
                send_notification "$battery_level"
                echo "$battery_level" > "$STATE_FILE"
            fi
        fi
    else
        if [ "$last_notified" -lt 100 ]; then
            echo "100" > "$STATE_FILE"
        fi
    fi
    
    sleep $CHECK_INTERVAL
done

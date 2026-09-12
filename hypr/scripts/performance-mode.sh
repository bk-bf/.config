#!/bin/bash

set -euo pipefail

CONF_DIR="$HOME/.config/intel-undervolt"
MODE="${1:-disable}"

apply_governor() {
    local gov="$1"
    for cpu_dir in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "$gov" | sudo tee "$cpu_dir" > /dev/null
    done
}

apply_intel_undervolt() {
    local conf="$1"
    sudo cp "$conf" "$CONF_DIR/intel-undervolt.conf"
    sudo intel-undervolt apply
}

apply_platform_profile() {
    local profile="$1"
    echo "$profile" | sudo tee /sys/firmware/acpi/platform_profile > /dev/null
}

case "$MODE" in
    enable)
        apply_platform_profile performance
        apply_intel_undervolt "$CONF_DIR/intel-undervolt-performance.conf"
        apply_governor performance
        notify-send -u normal -i power-profile-performance-symbolic \
            "Performance mode enabled" "PL1=28W PL2=45W · governor=performance"
        ;;
    disable)
        apply_platform_profile balanced
        apply_intel_undervolt "$CONF_DIR/intel-undervolt-balanced.conf"
        apply_governor powersave
        notify-send -u low -i power-profile-balanced-symbolic \
            "Balanced mode restored" "PL1=28W PL2=45W · governor=powersave"
        ;;
    *)
        echo "Usage: $0 [enable|disable]" >&2
        exit 1
        ;;
esac

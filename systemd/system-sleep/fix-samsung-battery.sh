#!/bin/bash

case "$1/$2" in
    post/hibernate|post/suspend|post/hybrid-sleep|post/suspend-then-hibernate)
        sleep 2

        BAT_DEV="/sys/bus/acpi/devices/PNP0C0A:00"

        [ -L "$BAT_DEV/driver" ] && exit 0

        echo "PNP0C0A:00" > /sys/bus/acpi/drivers_probe 2>/dev/null || true
        sleep 1

        if [ ! -L "$BAT_DEV/driver" ]; then
            rmmod samsung_galaxybook 2>/dev/null || true
            sleep 1
            modprobe samsung_galaxybook 2>/dev/null || true
        fi
        ;;
esac

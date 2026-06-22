#!/bin/bash
# /etc/systemd/system-sleep/fix-samsung-battery.sh
#
# Ensures BAT1 ACPI battery device is bound to the acpi-battery driver after resume.
# On Samsung Galaxy Book, the EC does not present BAT1 until after a suspend/resume cycle.
# This hook triggers a re-probe of the ACPI bus so the battery appears in power_supply.
#
# Source-controlled at ~/.config/systemd/system-sleep/fix-samsung-battery.sh
# Install: sudo cp ~/.config/systemd/system-sleep/fix-samsung-battery.sh \
#               /etc/systemd/system-sleep/fix-samsung-battery.sh
#          sudo chmod 755 /etc/systemd/system-sleep/fix-samsung-battery.sh

case "$1/$2" in
    post/hibernate|post/suspend|post/hybrid-sleep|post/suspend-then-hibernate)
        sleep 2

        BAT_DEV="/sys/bus/acpi/devices/PNP0C0A:00"

        # Already bound — nothing to do
        [ -L "$BAT_DEV/driver" ] && exit 0

        # Trigger acpi-battery probe for the battery device
        echo "PNP0C0A:00" > /sys/bus/acpi/drivers_probe 2>/dev/null || true
        sleep 1

        # If still unbound, try reloading samsung_galaxybook which re-registers the battery hook
        if [ ! -L "$BAT_DEV/driver" ]; then
            rmmod samsung_galaxybook 2>/dev/null || true
            sleep 1
            modprobe samsung_galaxybook 2>/dev/null || true
        fi
        ;;
esac

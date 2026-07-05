#!/bin/bash
# Fix Samsung Galaxy Book4 Pro battery detection on battery-only boot.
# The EC takes ~2 minutes to initialize on battery-only boot.
# drivers_probe works but only after this delay.
#
# Source-controlled at ~/.config/scripts/fix-samsung-battery.sh

# Exit immediately if battery already present (AC boot — EC ready within seconds)
if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    echo "fix-samsung-battery: BAT1 already present" | systemd-cat -t fix-samsung-battery
    exit 0
fi

echo "fix-samsung-battery: BAT1 missing, waiting for EC to initialize..." | systemd-cat -t fix-samsung-battery

# EC needs ~2 minutes on battery-only boot before drivers_probe works
sleep 120

echo "PNP0C0A:00" > /sys/bus/acpi/drivers_probe 2>/dev/null
sleep 3

if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    echo "fix-samsung-battery: BAT1 now bound" | systemd-cat -t fix-samsung-battery
    exit 0
fi

echo "fix-samsung-battery: BAT1 still missing after probe attempt" | systemd-cat -t fix-samsung-battery
exit 0

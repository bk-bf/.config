#!/bin/bash

if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    echo "fix-samsung-battery: BAT1 already present" | systemd-cat -t fix-samsung-battery
    exit 0
fi

echo "fix-samsung-battery: BAT1 missing, waiting for EC to initialize..." | systemd-cat -t fix-samsung-battery

sleep 120

echo "PNP0C0A:00" > /sys/bus/acpi/drivers_probe 2>/dev/null
sleep 3

if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    echo "fix-samsung-battery: BAT1 now bound" | systemd-cat -t fix-samsung-battery
    exit 0
fi

echo "fix-samsung-battery: BAT1 still missing after probe attempt" | systemd-cat -t fix-samsung-battery
exit 0

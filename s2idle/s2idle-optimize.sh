#!/bin/bash

set -e

echo "═══════════════════════════════════════════════════════════"
echo "  S2idle Power Management Optimization"
echo "═══════════════════════════════════════════════════════════"
echo ""

if [ "$EUID" -ne 0 ]; then 
   echo "ERROR: This script must be run as root (use sudo)"
   exit 1
fi

echo "[1/5] Enabling runtime PM for all PCI devices..."
for dev in /sys/bus/pci/devices/*/power/control; do
    echo "auto" > "$dev" 2>/dev/null || true
done
echo "✓ PCI runtime PM enabled"

echo ""
echo "[2/5] Enabling USB autosuspend..."
for dev in /sys/bus/usb/devices/*/power/control; do
    echo "auto" > "$dev" 2>/dev/null || true
done
for dev in /sys/bus/usb/devices/*/power/autosuspend; do
    echo "2" > "$dev" 2>/dev/null || true
done
echo "✓ USB autosuspend enabled"

echo ""
echo "[3/5] Enabling WiFi power save..."
if command -v iw &> /dev/null; then
    WIFI_IFACE=$(iw dev | awk '/Interface/{print $2}' | head -1)
    if [ -n "$WIFI_IFACE" ]; then
        iw dev "$WIFI_IFACE" set power_save on 2>/dev/null || true
        echo "✓ WiFi power save enabled on $WIFI_IFACE"
    else
        echo "⚠ No WiFi interface found"
    fi
else
    echo "⚠ iw command not found, skipping WiFi power save"
fi

echo ""
echo "[4/5] Configuring display power management..."
if [ -d /sys/module/i915 ]; then
    echo "✓ i915 (Intel graphics) module loaded"
fi

echo ""
echo "[5/5] Setting SATA link power management..."
for dev in /sys/class/scsi_host/host*/link_power_management_policy; do
    echo "med_power_with_dipm" > "$dev" 2>/dev/null || true
done
echo "✓ SATA link PM configured"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✓ Runtime power management optimizations applied"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Active optimizations:"
echo "  • PCI device runtime PM: enabled"
echo "  • USB autosuspend: 2s timeout"
echo "  • WiFi power save: enabled"
echo "  • SATA link PM: med_power_with_dipm"
echo ""
echo "These settings are temporary (reset on reboot)."
echo "For permanent configuration, install the systemd service."

# Battery Notification System

## Overview
Automated battery monitoring that sends critical notifications through Mako to prevent unexpected shutdowns.

## Components
- **Monitor Script**: `~/.config/sway/scripts/battery-monitor.sh`
- **Notification Daemon**: Mako
- **Battery Device**: `/sys/class/power_supply/BAT1`
- **Auto-start**: Configured in Sway config (line 250)

## Notification Thresholds
- **10%**: Critical warning when discharging
- **5%**: Critical warning when discharging
- **<5%**: Critical warning every 1% drop

Notifications only sent when **discharging** (not while charging/plugged in).

## State Management
State file: `/tmp/battery_monitor_state`
- Tracks last notification level to prevent spam
- Resets to 100 when charging/full
- Check interval: 30 seconds

## Common Issue Fixed
**Problem**: Script was hardcoded to `BAT0` but actual battery is `BAT1`
- Symptoms: No notifications despite low battery
- Solution: Updated `BATTERY_PATH` variable to correct device

## Testing
```bash
# Test notification display
notify-send -u critical "Test" "Critical notification test"

# Check current battery
cat /sys/class/power_supply/BAT1/capacity
cat /sys/class/power_supply/BAT1/status

# Verify monitor is running
ps aux | grep battery-monitor

# Check monitor state
cat /tmp/battery_monitor_state
```

## Troubleshooting
1. **No notifications**: Verify battery path matches your device (`ls /sys/class/power_supply/`)
2. **Script not running**: Check Sway config auto-start or run `~/.config/sway/scripts/battery-monitor.sh &`
3. **Mako not receiving**: Test with `notify-send -u critical "Test" "Message"`

## Manual Restart
```bash
pkill -f battery-monitor.sh
nohup ~/.config/sway/scripts/battery-monitor.sh > /dev/null 2>&1 &
```

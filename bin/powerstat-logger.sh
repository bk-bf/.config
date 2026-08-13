#!/bin/bash
# Powerstat continuous logger
# Logs power statistics to ~/.local/share/powerstat/

LOG_DIR="$HOME/.local/share/powerstat"
mkdir -p "$LOG_DIR"

DATE=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/powerstat-${DATE}.log"

# Find battery device
BAT_PATH=$(ls /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1 | xargs dirname)

# Run powerstat with 10 second intervals, 6 samples per minute
# -R for RAPL, -n for no header repeats
while true; do
    # Log timestamp and battery status
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG_FILE"
    
    # Log battery info if available
    if [ -n "$BAT_PATH" ]; then
        BAT_CAPACITY=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo "N/A")
        BAT_STATUS=$(cat "$BAT_PATH/status" 2>/dev/null || echo "N/A")
        echo "Battery: ${BAT_CAPACITY}% (${BAT_STATUS})" >> "$LOG_FILE"
    fi
    
    sudo powerstat -R -n 10 6 2>&1 | tee -a "$LOG_FILE"
    
    # Check if date changed, create new log file
    NEW_DATE=$(date +%Y-%m-%d)
    if [ "$NEW_DATE" != "$DATE" ]; then
        DATE=$NEW_DATE
        LOG_FILE="$LOG_DIR/powerstat-${DATE}.log"
    fi
done

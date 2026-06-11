#!/bin/bash
# Add current directory as a yazi bookmark

KEYMAP="$HOME/.config/yazi/keymap.toml"
CURRENT_DIR="$1"

if [ -z "$CURRENT_DIR" ]; then
    echo "Error: No directory provided"
    exit 1
fi

# Find an unused key by checking existing bindings
used_keys=$(grep -oP 'on = \[ "g", "\K[^"]+' "$KEYMAP" | sort)

# Try alphanumeric keys in order: a-z, A-Z, 0-9
for key in {a..z} {A..Z} {0..9}; do
    if ! echo "$used_keys" | grep -qx "$key"; then
        # Found unused key, add bookmark
        echo "" >> "$KEYMAP"
        echo "[[mgr.prepend_keymap]]" >> "$KEYMAP"
        echo "on = [ \"g\", \"$key\" ]" >> "$KEYMAP"
        echo "run = \"cd $CURRENT_DIR\"" >> "$KEYMAP"
        echo "desc = \"Go to $CURRENT_DIR\"" >> "$KEYMAP"
        
        notify-send "Yazi Bookmark" "Added g$key → $CURRENT_DIR\nRestart yazi to use it"
        exit 0
    fi
done

notify-send "Yazi Bookmark" "Error: No available keys left"
exit 1

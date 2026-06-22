#!/bin/bash
# /usr/lib/systemd/system-sleep/fix-samsung-audio.sh
#
# Reloads max98390 DKMS modules and re-creates I2C amp devices after resume.
# NOTE: Must live in /usr/lib/systemd/system-sleep/ — /etc/systemd/system-sleep/
# is NOT read by systemd 260+.
#
# Source-controlled at ~/.config/systemd/system-sleep/fix-samsung-audio.sh
# Install: sudo cp ~/.config/systemd/system-sleep/fix-samsung-audio.sh \
#               /usr/lib/systemd/system-sleep/fix-samsung-audio.sh
#          sudo chmod 755 /usr/lib/systemd/system-sleep/fix-samsung-audio.sh

case "$1/$2" in
    post/hibernate|post/suspend|post/hybrid-sleep|post/suspend-then-hibernate)
        echo "fix-samsung-audio: reloading max98390 modules after $2" | systemd-cat -t fix-samsung-audio
        sleep 2
        modprobe -r snd_hda_scodec_max98390_i2c 2>/dev/null || true
        modprobe -r snd_hda_scodec_max98390 2>/dev/null || true
        sleep 1
        modprobe snd_hda_scodec_max98390 2>/dev/null || true
        modprobe snd_hda_scodec_max98390_i2c 2>/dev/null || true
        # Re-create I2C amp devices (i2c-setup service only runs at boot)
        if [ -x /usr/local/sbin/max98390-hda-i2c-setup.sh ]; then
            /usr/local/sbin/max98390-hda-i2c-setup.sh start 2>&1 | systemd-cat -t fix-samsung-audio
        fi
        echo "fix-samsung-audio: done" | systemd-cat -t fix-samsung-audio
        ;;
esac

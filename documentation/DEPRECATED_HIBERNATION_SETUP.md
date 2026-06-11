# ⚠️ DEPRECATED: Hibernation Setup - Galaxy Book Gen4

## ❌ THIS SETUP SHOULD BE REVERTED

**Date deprecated:** February 15, 2026  
**Reason:** Hibernation is worse than shutdown on this hardware

### Why This Failed

1. **No user experience benefit** - Must press power button and boot through GRUB, identical to shutdown
2. **Breaks speakers** - MAX98390 don't initialize after resume (kernel patch conflict)
3. **Terrible UX** - Screen freezes on entry, looks like system crash
4. **No state preservation value** - Your sway autostart handles app initialization

### What To Do Instead

**Read the full assessment:** [SLEEP_OPTIONS_ASSESSMENT.md](SLEEP_OPTIONS_ASSESSMENT.md)

**Quick revert:**
```bash
bash ~/.config/documentation/revert-hibernation.sh
```

**Recommended solution:**
- Use simple s2idle suspend for daily breaks (accept ~14% overnight drain)
- Manually shutdown before bed (0% drain, faster than hibernation)
- Accept Intel hardware limitation (no S3 deep sleep available)

---

## Original Documentation (For Reference)

## Problem Statement

Battery drain during sleep on Galaxy Book Gen4 when left closed overnight:
- Sleep at 01:00-02:00 with laptop running
- Wake briefly to close lid
- Return at midday/afternoon to find battery completely drained (0%)
- MacBook M1 Air didn't have this issue - could maintain charge while closed

## Background

### Why this happens on Intel laptops vs MacBook M1

**MacBook M1:**
- Has true deep sleep (S3 state)
- ~0.5% battery drain per hour
- Can last weeks on battery while closed

**Galaxy Book Gen4 (Intel):**
- Only supports s2idle (modern standby / S0ix)
- 1.79% battery drain per hour in suspend
- 8-12 hours overnight = complete battery drain
- This is a **hardware limitation**, not a Linux bug
- Modern Intel laptops removed S3 support for "Windows Modern Standby"

### Battery Analysis (from battery-report-20260213-1437.log)

Observed drain patterns:
```
2026-02-12 22:00 - 31% - 5.07W avg
2026-02-12 23:00 - 12% - 4.17W avg
2026-02-13 00:00 - 24% - 3.49W avg
2026-02-13 01:00 - 14% - 1.90W avg
2026-02-13 02:00 - 7% - 0.86W avg
2026-02-13 03:00 - 3% - 1.93W avg
```

Battery drain: 43.0% over 24.0 hours (1.79%/hr average during suspend)

## Solution: Suspend-Then-Hibernate

The fix uses a hybrid approach to match MacBook behavior:

1. **Initial suspend** - Laptop suspends immediately when lid closes (fast resume)
2. **Auto-hibernate after 30min** - Saves RAM to disk, then powers off completely (0% drain)
3. **Resume** - Restores from hibernation (slower than suspend, but battery preserved)

This gives the best of both worlds:
- Quick resume if you return within 30 minutes
- Zero battery drain if left overnight

## Implementation

### 1. Swap File Creation

Hibernation requires disk space to store RAM contents.

**Location:** `/swapfile`  
**Size:** 16GB (matches RAM size)  
**Type:** Btrfs-compatible (CoW disabled)

```bash
sudo truncate -s 0 /swapfile
sudo chattr +C /swapfile              # Disable copy-on-write for Btrfs
sudo fallocate -l 16G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

**Verification:**
```bash
$ swapon --show
NAME       TYPE       SIZE USED PRIO
/swapfile  file        16G   0B   -2    # ← New disk-based swap
/dev/zram0 partition 15.2G   0B  100   # ← Existing zram (can't be used for hibernation)
```

**Why disk swap?** zram (compressed RAM swap) can't be used for hibernation since it's stored in RAM itself.

---

### 2. Make Swap Permanent

**File:** `/etc/fstab`

**Added:**
```
/swapfile none swap defaults 0 0
```

**Revert:**
```bash
sudo sed -i '/\/swapfile/d' /etc/fstab
```

---

### 3. GRUB Bootloader Configuration

Kernel needs to know where to resume from on boot.

**File:** `/etc/default/grub`  
**Backup:** `/etc/default/grub.backup` ✓

**Before:**
```
GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog nvme_load=YES zswap.enabled=0 splash loglevel=3 acpi_osi=! acpi_osi="Windows 2022" acpi.debug_layer=0x00000004 acpi.debug_level=0x00000002'
```

**After:**
```
GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog nvme_load=YES zswap.enabled=0 splash loglevel=3 acpi_osi=! acpi_osi="Windows 2022" acpi.debug_layer=0x00000004 acpi.debug_level=0x00000002 resume=UUID=0bd1c041-2a6d-48c5-b358-5e14ae63799e resume_offset=24978688'
```

**Parameters added:**
- `resume=UUID=0bd1c041-2a6d-48c5-b358-5e14ae63799e` - Root partition UUID
- `resume_offset=24978688` - Physical offset of swapfile on Btrfs

**How offset was calculated:**
```bash
sudo btrfs inspect-internal map-swapfile -r /swapfile
# Output: 24978688
```

**Commands executed:**
```bash
sudo cp /etc/default/grub /etc/default/grub.backup
# ... sed edit to add resume parameters ...
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

**Revert:**
```bash
sudo cp /etc/default/grub.backup /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

---

### 4. Initramfs Configuration

The resume hook must load hibernation image before mounting filesystems.

**File:** `/etc/mkinitcpio.conf`  
**Backup:** `/etc/mkinitcpio.conf.backup` ✓

**Before:**
```
HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth filesystems)
```

**After:**
```
HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth filesystems resume)
```

**Commands executed:**
```bash
sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.backup
# ... sed edit to add resume hook ...
sudo mkinitcpio -P  # Rebuilt initramfs for both kernels (6.18.7-1-cachyos & 6.12.69-2-cachyos-lts)
```

**Revert:**
```bash
sudo cp /etc/mkinitcpio.conf.backup /etc/mkinitcpio.conf
sudo mkinitcpio -P
```

---

### 5. Systemd Sleep Configuration

**File:** `/etc/systemd/sleep.conf.d/10-hibernate.conf` ← NEW  
**User copy:** `~/.config/documentation/systemd-sleep-config.conf`

```ini
[Sleep]
# Enable suspend-then-hibernate functionality
AllowSuspendThenHibernate=yes
AllowHibernation=yes

# After 30 minutes of suspend, automatically hibernate to save battery
# This prevents overnight drain like you experienced
HibernateDelaySec=30min
```

**Purpose:**
- Enables hybrid sleep mode
- Sets 30-minute timer before hibernation activates

**Revert:**
```bash
sudo rm /etc/systemd/sleep.conf.d/10-hibernate.conf
```

---

### 6. Systemd Lid Behavior Configuration

**File:** `/etc/systemd/logind.conf.d/99-lid-hibernate.conf` ← NEW  
**User copy:** `~/.config/documentation/logind-config.conf`

```ini
[Login]
# Use suspend-then-hibernate when lid is closed
HandleLidSwitch=suspend-then-hibernate

# When plugged in, just suspend (faster resume when on AC power)
HandleLidSwitchExternalPower=suspend
```

**Behavior:**
- **On battery:** Close lid → suspend-then-hibernate
- **On AC power:** Close lid → suspend only (no hibernate, faster resume)

**Old conflicting files removed:**
The following redundant configs were removed to avoid conflicts:
- `/etc/systemd/logind.conf.d/laptop-lid.conf` (old, set suspend only)
- `/etc/systemd/logind.conf.d/lid.conf` (old, set suspend only)

**Revert:**
```bash
sudo rm /etc/systemd/logind.conf.d/99-lid-hibernate.conf
```

---

## Activation

All changes complete. **Reboot required** to activate:

```bash
sudo reboot
```

**Why reboot instead of reloading systemd?**
- `systemctl restart systemd-logind` kills SwayFX session
- Rebooting safely applies all changes including new kernel parameters

**What gets activated:**
- ✓ Swap file (active now)
- ✓ GRUB parameters (apply on boot)
- ✓ Initramfs with resume hook (ready)
- ✓ Systemd sleep config (apply on boot)
- ✓ Lid behavior (apply after reboot)

---

## Testing After Reboot

### 1. Verify hibernation support
```bash
systemctl hibernate
```
Should hibernate immediately.

### 2. Test suspend-then-hibernate
```bash
systemctl suspend-then-hibernate
```
Should suspend, then auto-hibernate after 30 minutes.

### 3. Test lid behavior
- Close lid → should suspend
- Wait 30+ minutes → should auto-hibernate
- Open lid → should resume from hibernation

### 4. Monitor power drain
```bash
# Check current status
cat /sys/class/power_supply/BAT0/capacity
cat /sys/class/power_supply/BAT0/status

# Watch power consumption
watch -n 1 cat /sys/class/power_supply/BAT0/power_now
```

**Expected results:**
- Old behavior: 1.79%/hour during suspend overnight = 0% by morning
- New behavior: 1.79%/hour for first 30min, then 0%/hour after hibernate

---

## Expected Behavior

### Scenario 1: Overnight sleep (1:00 AM - 2:00 PM)
**Before:** Battery 0% (13 hours × 1.79%/hr = fully drained)  
**After:** Battery ~80-90% (30min s2idle drain, then 12.5hr hibernation = 0% drain)

### Scenario 2: Short break (15 minutes)
- Suspends → Quick resume when lid opens
- No hibernation (within 30min window)

### Scenario 3: Long meeting (2 hours)
- Suspends for 30min → Hibernates for 1.5hr
- Slower resume from hibernation, but battery preserved

### Scenario 4: Plugged into AC
- Only suspends (no hibernate)
- Fast resume
- No battery concerns

---

## Integration with GDM Lock

The hibernation setup works alongside the existing GDM lock configuration documented in [GDM_LOCK_DOCUMENTATION.md](GDM_LOCK_DOCUMENTATION.md).

**Combined behavior:**
1. Lid closes → GDM lock screen called via D-Bus (from `sway/config`)
2. System suspends (via systemd `HandleLidSwitch=suspend-then-hibernate`)
3. After 30 minutes → auto-hibernates
4. Lid opens → resume from hibernation
5. GDM greeter appears → requires password

**Sway config integration:**
```bash
# From ~/.config/sway/config
bindswitch --reload --locked lid:on exec 'gdbus call --system --dest org.gnome.DisplayManager --object-path /org/gnome/DisplayManager/LocalDisplayFactory --method org.gnome.DisplayManager.LocalDisplayFactory.CreateTransientDisplay > /dev/null'

exec_always pkill swayidle; swayidle -w before-sleep 'gdbus call --system --dest org.gnome.DisplayManager --object-path /org/gnome/DisplayManager/LocalDisplayFactory --method org.gnome.DisplayManager.LocalDisplayFactory.CreateTransientDisplay > /dev/null' &
```

---

## Complete Revert Instructions

To undo all hibernation changes:

```bash
# 1. Remove swap file
sudo swapoff /swapfile
sudo rm /swapfile
sudo sed -i '/\/swapfile/d' /etc/fstab

# 2. Restore GRUB**Conflicting files (not removed, just overridden):**
- `/etc/systemd/logind.conf.d/laptop-lid.conf`
- `/etc/systemd/logind.conf.d/lid.conf`

sudo cp /etc/default/grub.backup /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg

# 3. Restore initramfs
sudo cp /etc/mkinitcpio.conf.backup /etc/mkinitcpio.conf
sudo mkinitcpio -P

# 4. Remove systemd configs
sudo rm /etc/systemd/sleep.conf.d/10-hibernate.conf
sudo rm /etc/systemd/logind.conf.d/99-lid-hibernate.conf

# 5. Reboot
sudo reboot
```

---

## Backups Created

All critical config files were backed up before modification:

```
/etc/default/grub.backup           # GRUB config
/etc/mkinitcpio.conf.backup        # Initramfs hooks

# User reference copies
~/.config/documentation/systemd-sleep-config.conf
~/.config/documentation/logind-config.conf
```

---

## Technical Details

### Swap Calculation
- **Size needed:** Equals RAM size (16GB)
- **Why:** Hibernation stores complete RAM contents to disk
- **Btrfs special handling:** `chattr +C` disables copy-on-write for swapfile
- **Resume offset:** Calculated via `btrfs inspect-internal map-swapfile -r /swapfile`

### Systemd Configuration Hierarchy
```
/etc/systemd/sleep.conf          # Base config (defaults)
/etc/systemd/sleep.conf.d/*.conf # Drop-in overrides

/etc/systemd/logind.conf         # Base config (defaults)
/etc/systemd/logind.conf.d/*.conf # Drop-in overrides (loaded alphabetically)
```

### Why Not s2idle Optimization?

Alternative considered: Optimize s2idle to reduce power drain without hibernation.

**Why rejected:**
- s2idle drain is hardware-limited by Intel platform
- Even with optimization, can't match MacBook's S3 deep sleep
- Hibernation provides guaranteed 0% drain, matching MacBook behavior

---

## Known Issue: Speakers Not Working After Hibernation Resume

**Issue discovered:** February 15, 2026  
**Status:** Root cause identified, fix needs testing

### ⚠️ TESTING REQUIRED - Next Steps

1. **Reboot** to restore audio (broken during diagnostics)
2. **Hibernate again** to reproduce the speaker issue
3. **Test manual fix** to verify it actually works:
   ```bash
   sudo modprobe -r snd_soc_skl_hda_dsp && sudo modprobe snd_soc_skl_hda_dsp
   sleep 3
   # Test speakers with: paplay /usr/share/sounds/freedesktop/stereo/complete.oga
   # Check devices in pavucontrol
   ```
4. **Only if fix verified**: Create automated systemd service

### Problem

After resuming from hibernation, the MAX98390 speaker amplifiers don't initialize properly, resulting in no audio output from speakers (though HDMI audio and headphones work). 

**Root Cause Identified:**
- The HDA codec (`ehdaudio0D0` - Realtek ALC298) doesn't automatically rebind to its driver after hibernation
- Without the codec driver bound, the MAX98390 HDA component binding fails
- This is related to the SOF (Sound Open Firmware) audio driver suspend/resume behavior on Meteor Lake-P platform

**Evidence from testing:**
```bash
# After boot - codec properly bound:
$ ls -la /sys/bus/hdaudio/devices/ehdaudio0D0/driver
lrwxrwxrwx 1 root root 0 -> ../../drivers/snd_hda_codec_alc269

# After hibernation resume - codec NOT bound:
$ ls -la /sys/bus/hdaudio/devices/ehdaudio0D0/driver
ls: cannot access: No such file or directory

# Kernel shows speakers never rebind:
$ dmesg | grep "MAX98390.*bound"
[    6.009766] max98390-hda: MAX98390 HDA component bound (index 0-3)  ← Boot
[ 1686.910965] max98390-hda: MAX98390 HDA component unbound            ← Hibernation
# No rebind messages after resume
```

### Proposed Fix (Needs Verification)

Reload the SOF HDA machine driver to force codec rebinding:

```bash
sudo modprobe -r snd_soc_skl_hda_dsp && sudo modprobe snd_soc_skl_hda_dsp
```

**This fix has NOT been verified yet.** Need to test if it:
- Restores speaker audio output
- Restores all audio device options (HDMI 1-3, Speaker) in pavucontrol
- Properly rebinds MAX98390 components (check `dmesg | grep MAX98390`)

### If Fix Works: Automate with Systemd

After verifying the manual fix works, create systemd service that runs after hibernation resume.

### Why Not Disable Hibernation?

If the fix works and takes only ~3 seconds, the battery preservation benefit (0% drain overnight vs 100% drain) far outweighs the minor inconvenience of this workaround.

---

## Summary

**Status:** Suspend-then-hibernate functional, speaker resume issue being investigated

**Trade-offs accepted:**
- ✅ Battery preserved overnight (matches MacBook behavior)
- ✅ Fast resume for short breaks (<30min)
- ✅ Zero drain during hibernation
- ⚠️ Slower resume after hibernation (vs instant resume from S3 sleep)
- ⚠️ Requires 16GB disk space for swapfile
- ⚠️ **Speakers don't initialize after hibernation** (manual fix being tested)

**Why this is the best solution:**
- Intel platform limitation prevents true deep sleep (S3)
- Hibernation is the only way to achieve 0% battery drain
- 30-minute delay preserves quick-resume convenience
- Standard, documented approach for Arch/systemd
- Speaker initialization issue may have simple fix (pending verification)

---

## System Information

- **Date implemented:** February 13, 2026
- **Speaker issue discovered:** February 15, 2026
- **Distribution:** CachyOS (Arch-based)
- **Kernels:** 6.18.7-1-cachyos, 6.12.69-2-cachyos-lts
- **Filesystem:** Btrfs
- **Desktop:** SwayFX
- **Display Manager:** GDM
- **Hardware:** Samsung Galaxy Book Gen4
- **RAM:** 16GB
- **Audio:** MAX98390 quad speakers (requires kernel patch + resume fix TBD)

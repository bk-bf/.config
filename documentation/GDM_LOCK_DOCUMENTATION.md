# GDM Lock Integration with SwayFX

## Problem Statement

When closing the laptop lid, the goal was to:
1. Suspend to RAM for power saving
2. Lock to GDM greeter (not swaylock)
3. Minimize visual delay on resume (brief Sway desktop visibility before GDM appears)

## Background

- **Why not swaylock?** Swaylock causes input glitches and doesn't look good in this setup
- **Why GDM?** Already running GDM as display manager, want consistent lock experience
- **Power saving requirement:** Lid close must trigger suspend to RAM

## Working Solution

### Configuration Files

#### `/etc/systemd/logind.conf.d/lid.conf`
```ini
[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
HandleLidSwitchDocked=ignore
```

This ensures systemd triggers suspend when lid closes.

#### `/home/kirill/.config/sway/config`

**Lid switch binding:**
```bash
bindswitch --reload --locked lid:on exec 'gdbus call --system --dest org.gnome.DisplayManager --object-path /org/gnome/DisplayManager/LocalDisplayFactory --method org.gnome.DisplayManager.LocalDisplayFactory.CreateTransientDisplay > /dev/null'
```

**Swayidle backup trigger:**
```bash
exec_always pkill swayidle; swayidle -w before-sleep 'gdbus call --system --dest org.gnome.DisplayManager --object-path /org/gnome/DisplayManager/LocalDisplayFactory --method org.gnome.DisplayManager.LocalDisplayFactory.CreateTransientDisplay > /dev/null' &
```

### How It Works

1. **Lid closes** → systemd triggers suspend (`HandleLidSwitch=suspend`)
2. **Before suspend** → swayidle catches `before-sleep` event and calls GDM via D-Bus
3. **Alternative trigger** → bindswitch also calls GDM directly on lid close
4. **GDM creates transient display** → temporary greeter session
5. **System suspends** → enters s2idle (suspend to RAM)
6. **Lid opens** → system resumes
7. **GDM greeter appears** → requires password to return to Sway session

### D-Bus Call Explanation

```bash
gdbus call --system \
  --dest org.gnome.DisplayManager \
  --object-path /org/gnome/DisplayManager/LocalDisplayFactory \
  --method org.gnome.DisplayManager.LocalDisplayFactory.CreateTransientDisplay
```

- `dest org.gnome.DisplayManager` - targets the GDM service
- `object-path` - specifies the factory object that creates displays
- `method CreateTransientDisplay` - creates a temporary login screen
- This switches from Sway session to GDM greeter, returns to Sway after login

## Attempted Solutions for Visual Delay

### Issue
On resume, there's a ~0.5-1 second delay where the Sway desktop is visible before GDM greeter takes over. This is a cosmetic issue - security is fine, but it looks unpolished.

### Solution 1: DPMS Off ❌
**Idea:** Turn off display on lid close
```bash
swaymsg "output * dpms off"
```
**Rejected:** Display turns back on when lid opens, before GDM appears

---

### Solution 2: Black Wallpaper ❌
**Idea:** Change wallpaper to black on lid close
```bash
swaymsg "output * bg ~/Pictures/black4k.png fill"
```
**Rejected:** Windows still visible on top of wallpaper

---

### Solution 3: Swaylock as Black Overlay ❌
**Idea:** Use swaylock briefly as visual barrier, then switch to GDM
```bash
swaylock -f -c 000000 & sleep 0.1 && gdbus call ... CreateTransientDisplay
```
**Result:** Failed - swaylock persists after GDM unlock, causes glitches and requires laptop restart

**Why it failed:** Swaylock doesn't automatically terminate when GDM session switches. It remains running in background and blocks input after returning from GDM.

---

### Solution 4: Systemd Sleep Hook with Display Delay ❌
**Idea:** Use systemd sleep hook to control display hardware on resume, keeping it off while GDM draws

**Implementation attempted:**
1. Created `/usr/lib/systemd/system-sleep/display-delay` hook
2. Tried controlling display via `/sys/class/drm/card1-eDP-1/enabled`
3. Tried controlling backlight brightness via `/sys/class/backlight/*/brightness`

**Why it failed:** 
- **Sequential execution problem**: The sleep hook runs in the resume pipeline sequentially, which means:
  1. Resume starts → Sway desktop becomes visible (the problem we're trying to solve)
  2. Sleep hook runs → blacks out screen  
  3. Sleep hook waits → still blacked out
  4. Sleep hook restores display → Sway still visible, GDM hasn't switched yet
  5. GDM finally switches → greeter appears
- The hook doesn't prevent Sway from being visible, it just adds a black screen *after* Sway is already shown, then delays GDM appearance even more
- No way to intercept the display at the right moment in the pipeline
- Architectural limitation: display hardware turns on before any software can control it

**Verdict:** Not viable - doesn't solve the timing issue, just adds unnecessary delays to the resume process

---

## Verification

### Test Suspend/Resume
```bash
# Check swayidle is running
ps aux | grep swayidle

# Test manual GDM call
gdbus call --system --dest org.gnome.DisplayManager --object-path /org/gnome/DisplayManager/LocalDisplayFactory --method org.gnome.DisplayManager.LocalDisplayFactory.CreateTransientDisplay

# Check suspend logs
journalctl -b | grep -i "suspend\|resume"
```

### Expected Behavior
1. ✅ Lid close triggers suspend
2. ✅ System enters s2idle state
3. ✅ GDM greeter appears on resume
4. ✅ Password required to return to Sway
5. ⚠️ Brief (~0.5s) Sway visibility before GDM (cosmetic only)

## Alternative Approaches Not Tried

### Option: Kill Sway Session on Suspend
**Idea:** Terminate Sway entirely on suspend, rely only on GDM
**Drawback:** Would lose all running applications, window positions, workspace state
**Verdict:** Not viable - defeats purpose of suspend (quick resume)

### Option: Use LightDM instead of GDM
**Idea:** LightDM has dm-tool for session locking
**Drawback:** Would require switching display manager, different GNOME integration
**Verdict:** Not pursued - user prefers GDM

### Option: Custom Compositor Overlay
**Idea:** Create dedicated compositor that draws black screen
**Drawback:** Significant development effort for cosmetic fix
**Verdict:** Overkill for the problem

## Summary

**Current state:** Fully functional GDM lock on suspend without swaylock, with minor cosmetic delay on resume.

**Trade-offs accepted:**
- ✅ Security: GDM lock works perfectly
- ✅ Power saving: Suspend to RAM working
- ✅ No swaylock glitches
- ⚠️ Brief visual delay on resume (unavoidable)

**Why we can't do better:** The session handoff between Sway and GDM is a fundamental display manager operation that requires time. Any workaround either causes worse problems (swaylock glitches) or isn't feasible (killing Sway loses state).

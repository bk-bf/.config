# Touchscreen / Touchpad udev Rule

## Problem

The Galaxy Book4 exposes two separate I2C HID input devices:

- **ZNT0001:00 14E5:650E** — the touchpad (two nodes: a `Mouse` and a `Touchpad` node)
- **GXTP7936:00 27C6:0123** — the display touchscreen

libinput picks up both. Since the touchscreen is not useful on a laptop running a Wayland compositor, a udev rule was added to suppress it.

---

## The Bug (what not to do)

The original rule was written as:

```udev
SUBSYSTEM=="input", ATTRS{name}=="GXTP7936:00 27C6:0123", ENV{LIBINPUT_IGNORE_DEVICE}="1"
KERNEL=="event10", SUBSYSTEM=="input", ENV{LIBINPUT_IGNORE_DEVICE}="1"
```

The second line hard-codes `event10`. Linux kernel input event numbers are **not stable across reboots** — they depend on probe order. After a reboot `event10` was reassigned to the touchpad (`ZNT0001:00 14E5:650E Touchpad`), causing libinput to ignore the touchpad entirely while the touchscreen continued working fine.

This could silently break any input device on any reboot. Never match on `KERNEL=="eventN"`.

---

## The Fix

Match only on the stable device name attribute:

```udev
# Galaxy Book4 GXTP7936 Touchscreen
SUBSYSTEM=="input", ATTRS{name}=="GXTP7936:00 27C6:0123", ENV{LIBINPUT_IGNORE_DEVICE}="1"
```

This is tracked at `~/.config/.docs/udev/99-disable-touchscreen.rules` and deployed to `/etc/udev/rules.d/`.

---

## Restore

```bash
sudo cp ~/.config/.docs/udev/99-disable-touchscreen.rules /etc/udev/rules.d/
sudo udevadm control --reload
```

A reboot is recommended after deploying — `udevadm trigger` is unreliable for I2C HID devices.

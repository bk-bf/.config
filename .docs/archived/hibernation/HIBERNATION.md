# Hibernation — Removed (2026-05-28)

**Device:** Samsung Galaxy Book 4 Pro (NP940XGK), CachyOS / Arch, btrfs, GRUB, Hyprland

Hibernate was fully configured and working in isolation (`sudo systemctl hibernate` with AC
connected) but failed in both real-world use cases it was meant to solve. Removed in favour
of workspace snapshot/restore. See `.docs/power/WORKSPACE_SNAPSHOT.md`.

---

## Why it was removed

### Failure mode 1: session not saved when battery dies

The primary goal was: battery runs out → session preserved to disk → resume on next boot.
This never worked because of a hardware-level ACPI timing bug.

The Samsung Galaxy Book EC (Embedded Controller) does not report BAT1 as present until a
PMC/UCSI hardware handshake completes. On AC-connected boot this happens in ~1 second; on
battery-only boot it takes 3–8 seconds — by which time `acpi_battery` has already finished
its probe pass and never picks up BAT1. The device is physically present in the ACPI namespace
(`\_SB_.PC00.LPCB.H_EC.BAT1`) but is unbound from the battery driver.

Consequence: UPower reports no battery on any boot that starts without AC power. Because UPower
sees no battery, it has no percentage to track, so its `CriticalPowerAction=Hibernate` trigger
never fires. The laptop just dies when the cell is exhausted, with nothing written to the
swapfile. Exactly the scenario hibernate was supposed to prevent.

The `fix-samsung-battery.service` workaround (wait 8s, then rebind the ACPI device) fixes the
missing battery indicator in a running session but does not help here: UPower is already running
and has already decided there is no battery. The race is at driver bind time, before systemd
user services start. Even if the battery appeared, UPower would need to re-enumerate it — which
it only does on a udev add event, which only fires when the kernel binds the device. By the time
the workaround fires, the window for that event is gone.

This is a known kernel bug (bugzilla #218234). A fix was posted to lore.kernel.org by Joshua
Grisham in February 2025 but was still not merged into cachyos-galaxybook-kernel as of the
removal date. Until it is, any hibernate trigger that depends on UPower seeing the battery on a
battery-only boot is fundamentally broken on this machine.

### Failure mode 2: broken state after manual hibernate

Even when hibernating manually with AC connected (so the battery was visible), resume produced
a broken session in two consistent ways:

**Audio broken on resume.** The speaker fix depends on an out-of-tree DKMS module
(`snd-hda-scodec-max98390`) loaded by `modules-load.d` and three I2C amp devices created by
`max98390-hda-i2c-setup.service`. Both of those only run at boot — not on resume.
`systemd/system-sleep/fix-samsung-audio.sh` was written to reload the module and re-run the I2C
setup script after resume, but the re-probe race with PipeWire meant audio was unreliable for
30–60 seconds after wake in the best case, and sometimes required a manual `systemctl restart
pipewire` to recover.

**Battery not detected on resume.** Same ACPI timing bug. When hibernating and resuming without
AC power, the resume kernel boots cold (it is a full kernel load — hibernate resume is not a
simple wakeup), hits the same probe race, and BAT1 is again missing. The battery workaround
service fires after 8 seconds and binds the device, but in the gap UPower still sees no battery.
`systemd/system-sleep/fix-samsung-battery.sh` attempted to re-probe on resume but could not
reliably trigger the udev add event that UPower listens for.

**Lockscreen crash (fixed but worth noting).** hypridle's `before_sleep_cmd` must block until
the lockscreen Wayland protocol handshake completes before systemd freezes RAM. The naive
`loginctl lock-session` is async and returns immediately, so systemd could snapshot RAM while
Noctalia/Quickshell was still mid-handshake on `ext-session-lock-v1` (WlSessionLock). On
resume the lock surface object was in a broken state, Quickshell crashed, and Hyprland's
"lockscreen crashed" safety screen appeared — the session was inaccessible without a reboot.
This was fixed by switching to `qs ipc call lockScreen lock` (synchronous round-trip) + `sleep 1`
in `idle-action.sh`, but it illustrates the fragility of the whole stack.

---

## What was set up (historical record)

### Swapfile

A dedicated 16G btrfs swapfile on its own subvolume — required because zram-only systems
cannot hibernate (no persistent block device to write RAM to).

```
/swap/               # btrfs subvolume
/swap/swapfile       # 16G, no CoW, no compression
```

`/etc/fstab` entry:
```
/swap/swapfile  none  swap  defaults  0 0
```

The swapfile still exists and is still mounted as swap (useful for memory pressure). Only the
hibernate resume pointer was removed.

### Kernel parameters

`resume=UUID=0bd1c041-2a6d-48c5-b358-5e14ae63799e resume_offset=44311808`

- UUID is the btrfs root partition (nvme0n1p2)
- `resume_offset` was obtained with: `btrfs inspect-internal map-swapfile -r /swap/swapfile`

**Removed from** `/etc/default/grub` GRUB_CMDLINE_LINUX_DEFAULT. If ever re-adding, run the
map-swapfile command fresh — the offset changes if the swapfile is deleted and recreated.

### mkinitcpio

`resume` hook added before `filesystems` in HOOKS. **Removed.** Current HOOKS:
```
HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth filesystems)
```

### UPower

`CriticalPowerAction=Hibernate` with `AllowRiskyCriticalPowerAction=true`. **Reverted** to
`CriticalPowerAction=PowerOff` and `AllowRiskyCriticalPowerAction=false`.

### logind / sleep

`HandleLidSwitch=suspend-then-hibernate` + `HibernateDelaySec=45min`. **Reverted** to
`HandleLidSwitch=suspend` with no hibernate delay.

### system-sleep hooks

Three hooks were installed to `/usr/lib/systemd/system-sleep/` and `/etc/systemd/system-sleep/`:

- `fix-samsung-audio.sh` — reload DKMS audio module + re-run I2C setup after resume
- `fix-samsung-battery.sh` — re-probe ACPI battery after resume
- `hibernate-splash.sh` — Plymouth "Hibernating..." splash during RAM dump

`hibernate-splash.sh` has been removed. The audio and battery hooks are still installed because
they are also useful for plain suspend resume (audio sometimes needs a nudge after s2idle).

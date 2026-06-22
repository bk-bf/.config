# Battery Not Detected on Boot (AC-less boot)

**Device:** Samsung Galaxy Book4 Pro (NP940XGK)  
**Symptom:** BAT1 missing from `/sys/class/power_supply/` on boot without AC adapter. Battery indicator absent in Noctalia bar. UPower reports no battery.  
**Status:** Workaround applied. Upstream fix pending.

---

## Root cause

The EC (Embedded Controller) firmware does not report BAT1 as present until a PMC/UCSI hardware handshake completes. On AC-connected boot this happens in ~1s. On battery-only boot it takes 3-8 seconds — by which time `acpi_battery` has already finished its probe pass and never picks up BAT1. The device sits in the ACPI namespace (`\_SB_.PC00.LPCB.H_EC.BAT1`) the whole time but is unbound from the battery driver.

Related: kernel bugzilla #218234, patch posted to lore.kernel.org by Joshua Grisham (Feb 2025), under review. The `cachyos-galaxybook-kernel` as of early 2025 does **not** include the fix — it is still pending upstream acceptance.

ACPI path confirmed for this machine:
```
\_SB_.PC00.LPCB.H_EC.BAT1
```

---

## Workaround applied

A systemd oneshot service waits 8 seconds post-boot then manually binds the battery ACPI device to the battery driver:

**Source file:** `~/.config/systemd/fix-samsung-battery.service`  
**System symlink:** `/etc/systemd/system/fix-samsung-battery.service`

```ini
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'sleep 8 && echo \_SB_.PC00.LPCB.H_EC.BAT1 > /sys/bus/acpi/drivers/battery/bind'
```

Enable with:
```bash
sudo ln -sf ~/.config/systemd/fix-samsung-battery.service \
     /etc/systemd/system/fix-samsung-battery.service
sudo systemctl enable fix-samsung-battery.service
```

---

## Manual trigger (no reboot)

If BAT1 is missing in a running session:
```bash
echo '\_SB_.PC00.LPCB.H_EC.BAT1' | sudo tee /sys/bus/acpi/drivers/battery/bind
```

---

## When to remove this workaround

Once the battery probe delay patch is merged upstream and included in `cachyos-galaxybook-kernel`, this service can be disabled:
```bash
sudo systemctl disable fix-samsung-battery.service
```

Monitor: https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/master/linux-galaxybook/PKGBUILD  
Upstream patch: https://lore.kernel.org/platform-driver-x86/20250218092341.9821-1-joshua@joshuagrisham.com/

---

## Related files

| File | Purpose |
|---|---|
| `~/.config/systemd/fix-samsung-battery.service` | Source-controlled service unit |
| `/etc/systemd/system/fix-samsung-battery.service` | System symlink (installed) |

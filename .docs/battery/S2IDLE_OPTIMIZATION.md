# S2idle Optimization - Galaxy Book Gen4

**Date:** February 15, 2026  
**Status:** ✓ Installed - **Reboot required for kernel parameters**

---

## Current Status

| Metric             | Before  | Target   | Status                                          |
| ------------------ | ------- | -------- | ----------------------------------------------- |
| Battery drain/hour | 1.79%   | 1.0-1.3% | Runtime PM active, kernel params pending reboot |
| Overnight (8h)     | ~14%    | ~8-10%   | Test after reboot                               |
| S0ix residency     | Unknown | >90%     | Baseline: 58,674,192 µs                         |

**Installed components:**
- ✅ Runtime PM service: `s2idle-optimize.service` (active now) — source-controlled at `~/.config/s2idle/s2idle-optimize.service`, symlinked to `/etc/systemd/system/`
- ✅ Script: `/usr/local/bin/s2idle-optimize.sh` — source-controlled at `~/.config/s2idle/s2idle-optimize.sh`, symlinked to `/usr/local/bin/`
- ✅ Monitoring aliases: `s2check`, `s2residency`, `s2devices`, `s2test`
- ⏳ Kernel parameters: Added to GRUB (apply on reboot)

---

## Quick Commands

### Monitoring
```bash
s2check          # Service status
s2residency      # S0ix deep sleep time (µs)
s2devices        # Devices blocking sleep
s2test           # 1-hour test guide

batrep           # 24h battery report
bathour          # Hourly consumption
```

### Testing
```bash
# 1. Overnight test (recommended)
sudo reboot                           # Apply kernel params
# Close lid before bed
batrep                                # Check drain rate in morning

# 2. S0ix residency test (1 hour)
s2residency                           # Note value
# Close lid for 1 hour
s2residency                           # Check increase
# Good: >3.24M µs increase (>90% residency)
```

---

## What Was Done

### Runtime Power Management (Active Now)
Enables aggressive power saving for all devices on boot:
- PCI devices: Runtime PM auto
- USB devices: 2s autosuspend
- WiFi: Power save enabled
- SATA: Link power management

### Kernel Parameters (Apply on Reboot)
Added to `/etc/default/grub`:
```
mem_sleep_default=s2idle          # Explicit s2idle mode
i915.enable_fbc=1                 # Framebuffer compression
i915.enable_dc=2                  # Deep display states (DC6)
pcie_aspm.policy=powersupersave   # PCIe link PM
```

### Diagnosis Results
Found 12+ devices blocking deep S0ix substates:
- USB2_PLL, FABRIC_PLL, SOC_PLL not powering down
- ISH (Integrated Sensor Hub): 10ms latency
- IOE_PMC: 5.6ms latency
- Multiple PCI devices staying active

---

## Troubleshooting

### System Won't Resume
**Cause:** PCIe ASPM too aggressive  
**Fix:**
```bash
sudo nano /etc/default/grub
# Remove: pcie_aspm.policy=powersupersave
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

### WiFi Drops After Resume
**Fix:**
```bash
sudo nano /usr/local/bin/s2idle-optimize.sh
# Comment out: iw dev "$WIFI_IFACE" set power_save on
sudo systemctl restart s2idle-optimize.service
```

### Still High Drain
```bash
s2check          # Verify service running
s2devices        # Check active devices
s2residency      # Measure deep sleep %
```

---

## Service Unit File

Installed at `/etc/systemd/system/s2idle-optimize.service`:

```ini
[Unit]
Description=Runtime Power Management Optimization for S2idle
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/s2idle-optimize.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

---

## Reverting Changes

### Remove Service
```bash
sudo systemctl disable --now s2idle-optimize.service
sudo rm /etc/systemd/system/s2idle-optimize.service
sudo rm /usr/local/bin/s2idle-optimize.sh
```

### Remove Kernel Parameters
```bash
sudo cp /etc/default/grub.before-s2idle-opt /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

---

## Success Criteria

**Good (Goal):** 1.0-1.3%/hr, 8-10% overnight, >90% S0ix residency  
**Acceptable:** 1.3-1.5%/hr, 10-12% overnight, 70-90% residency  
**Needs work:** >1.5%/hr, <70% residency, device failures

---

## Next Steps

1. **Reboot now:** `sudo reboot`
2. **Test overnight:** Close lid, run `batrep` in morning
3. **Measure S0ix:** Use `s2test` for 1-hour residency check
4. **Expected:** 25-40% battery improvement

**Related docs:** [SLEEP_OPTIONS_ASSESSMENT.md](SLEEP_OPTIONS_ASSESSMENT.md), [HIBERNATION_SETUP.md](swayfx+waybar/DEPRECATED_HIBERNATION_SETUP.md) (deprecated)


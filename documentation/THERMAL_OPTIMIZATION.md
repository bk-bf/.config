# Thermal Optimization - Galaxy Book Gen4

**Date:** February 27, 2026  
**Status:** ✓ Applied — all components active

---

## Current Status

| Fix                        | State       | Details                                                  |
| -------------------------- | ----------- | -------------------------------------------------------- |
| Power profile              | ✅ OK        | Already `balanced` — no change needed                    |
| Intel Turbo Boost          | ✅ On        | `no_turbo=0` — power cap via `intel-undervolt` instead   |
| Boost disable (persistent) | ❌ Removed   | tmpfiles rule removed; boost allowed, PL1/PL2 contain it |
| intel-undervolt            | ✅ Active    | PL1=15W (long), PL2=25W (short); service enabled         |
| thermald                   | ✅ Active    | Dynamic thermal management daemon                        |
| s-tui                      | ✅ Installed | Stress + temperature monitor                             |

---

## Quick Commands

### Monitoring
```bash
s-tui                                          # Live CPU temp + freq + stress graph
btop                                           # System overview (pre-installed)
sudo intel-undervolt measure                   # Current RAPL power readings
sensors                                        # Raw temperature readout (lm-sensors)
```

### Check Status
```bash
cat /sys/devices/system/cpu/intel_pstate/no_turbo   # 1 = boost disabled
powerprofilesctl get                                 # Should be: balanced
systemctl is-active intel-undervolt                  # Should be: active
systemctl is-active thermald                         # Should be: active
sudo intel-undervolt read                            # Current power limits
```

---

## What Was Done

### 1. Intel Turbo Boost — Enabled (power-capped)

Turbo Boost is enabled (`no_turbo=0`) but effectively constrained by the PL1=15W sustained
power limit set via `intel-undervolt`. The CPU can boost in frequency for short bursts
(within the PL2=25W window) but is throttled back to whatever frequency fits within 15W
sustained — replicating how Windows/DPTF manages it.

The `/etc/tmpfiles.d/cpu-no-turbo.conf` rule has been removed. Boost persists across reboots.

To re-disable boost if needed:
```bash
echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo
echo "w /sys/devices/system/cpu/intel_pstate/no_turbo - - - - 1" | sudo tee /etc/tmpfiles.d/cpu-no-turbo.conf
```

---

### 2. CPU Package Power Limits via `intel-undervolt`

Installed from `extra` repo (was in official repos, not AUR):
```bash
sudo pacman -S intel-undervolt
```

Config: `/etc/intel-undervolt.conf`

Added line:
```
power package 25 15
```
- **PL2 (short-term):** 25W — peak burst for up to ~0.002s  
- **PL1 (long-term):** 15W — sustained TDP over ~28s window

Applied immediately with:
```bash
sudo intel-undervolt apply
sudo systemctl enable --now intel-undervolt
```

The service is also linked to `suspend.target`, `hibernate.target`, and
`hybrid-sleep.target`, so limits are reinstated after any sleep/wake cycle automatically.

---

### 3. `thermald` — Intel Thermal Daemon

Installed from `extra` repo:
```bash
sudo pacman -S thermald
sudo systemctl enable --now thermald
```

`thermald` replicates the adaptive thermal behavior that Windows uses through DPTF
(Dynamic Platform and Thermal Framework). Without it, Linux applies a flat conservative
firmware limit. With it, the daemon actively throttles based on real-time sensor data,
preventing sustained high-temp bursts before hitting critical thresholds.

---

### 4. `s-tui` — Stress + Temperature Monitor

Installed from `extra` repo:
```bash
sudo pacman -S s-tui
```
Includes `stress` as a dependency. Run `s-tui` for a TUI showing CPU frequency,
utilization, and temperature in real time — useful for validating that the limits are
working.

---

## Why `cpufreq/boost` Didn't Exist

The guide referenced `/sys/devices/system/cpu/cpufreq/boost`, which is the path for the
`acpi-cpufreq` driver. Your system uses `intel_pstate` instead (confirmed via
`cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver`), which exposes turbo control at
`/sys/devices/system/cpu/intel_pstate/no_turbo` — the opposite polarity: `0` = boost on,
`1` = boost off.

---

## Troubleshooting

### Power limits not applying after reboot
```bash
sudo systemctl status intel-undervolt
sudo intel-undervolt read    # Check PL1/PL2 values
sudo intel-undervolt apply   # Re-apply manually
```

### thermald conflicting with power-profiles-daemon
These can conflict. If you see warnings in `journalctl -u thermald`, try masking one:
```bash
sudo systemctl mask power-profiles-daemon   # if thermald preferred
# or
sudo systemctl mask thermald                # if power-profiles-daemon preferred
```

### Boost re-enabled after update
Check that the tmpfiles rule is still present:
```bash
cat /etc/tmpfiles.d/cpu-no-turbo.conf
```
Re-create if missing:
```bash
echo "w /sys/devices/system/cpu/intel_pstate/no_turbo - - - - 1" | sudo tee /etc/tmpfiles.d/cpu-no-turbo.conf
```

---

## Reverting Changes

### Re-enable Turbo Boost
```bash
echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo
sudo rm /etc/tmpfiles.d/cpu-no-turbo.conf
```

### Remove Power Limits
```bash
sudo systemctl disable --now intel-undervolt
sudo pacman -R intel-undervolt
# or edit /etc/intel-undervolt.conf and comment out the `power package` line
```

### Remove thermald
```bash
sudo systemctl disable --now thermald
sudo pacman -R thermald
```

---

## Expected Impact

| Scenario       | Before   | Expected After        |
| -------------- | -------- | --------------------- |
| Idle temps     | 60–75°C  | 45–55°C               |
| Light load     | 75–90°C  | 55–65°C               |
| Sustained load | 95–100°C | 60–75°C               |
| Fan noise      | Frequent | Significantly reduced |

The largest gains come from the PL1=15W sustained power cap and `thermald`. Turbo Boost
is re-enabled but contained by the power limits, giving burst responsiveness without
sustained thermal runaway.

---

**Related docs:** [S2IDLE_OPTIMIZATION.md](S2IDLE_OPTIMIZATION.md), [BATTERY_NOTIFICATION.md](BATTERY_NOTIFICATION.md)

# VRR & SCX Scheduler — Power/Performance Tuning

**Date:** March 2026 | **Updated:** April 2026  
**Status:** VRR ✅ Active | SCX ✅ Active (`scx_lavd` running via `scx_loader.service`)

---

## VRR (Variable Refresh Rate / Adaptive Sync)

### What it does
With `vrr = 1` in Hyprland's `misc {}` block, the display's refresh rate adapts to
actual content frame rate. When showing a static terminal or idle desktop, the panel
can drop well below 120Hz, reducing GPU/display power draw.

### Config location
`~/.config/hypr/hyprland.conf` — `misc` block:

```
misc {
    vrr = 1  # 0=off, 1=always on, 2=fullscreen-only
}
```

### Status
Active (`vrr = 1` in `hyprland.conf`). Was disabled temporarily due to annoyance; re-enabled April 2026.

---

## SCX Scheduler (scx_lavd)

### What it does
`scx_lavd` is a latency-aware virtual deadline scheduler built on sched-ext (BPF).
It improves compositor responsiveness under mixed loads (e.g. Hyprland + browser +
build jobs) with comparable or lower power vs. the default CFS scheduler.

### Current state
Active. `scx_loader.service` is enabled and running; spawns `scx_lavd --autopilot`.

Config: `/etc/scx_loader.toml`
```toml
default_sched = "scx_lavd"
default_mode = "Auto"
```

**Note:** Do NOT add a `[Service] ExecStart=` drop-in with `--auto` flag — the service
is `Type=dbus` and that causes a startup timeout. The toml config is sufficient.

### Setup (one-time, requires sudo)

```bash
# 1. Write the config
sudo tee /etc/scx_loader.toml > /dev/null <<'EOF'
default_sched = "scx_lavd"
default_mode = "Auto"
EOF

# 2. Enable and start (no drop-in needed)
sudo systemctl enable --now scx_loader
```

### Verify active scheduler

```bash
cat /sys/kernel/sched_ext/state        # should print: enabled
cat /sys/kernel/sched_ext/root/ops     # should print: scx_lavd
busctl get-property org.scx.Loader /org/scx/Loader org.scx.Loader CurrentScheduler
```

### Revert / switch schedulers

```bash
# Switch to a different scheduler at runtime (requires polkit auth prompt)
busctl call org.scx.Loader /org/scx/Loader org.scx.Loader SwitchScheduler su scx_rusty 0

# Disable entirely — remove the drop-in and config, then restart service
sudo rm /etc/systemd/system/scx_loader.service.d/auto.conf /etc/scx_loader.toml
sudo systemctl daemon-reload && sudo systemctl restart scx_loader
```

### Available schedulers (installed via scx-scheds)
| Scheduler | Best for |
|---|---|
| `scx_lavd` | Desktop/compositor — **recommended** |
| `scx_rusty` | General workloads |
| `scx_bpfland` | Mixed interactive/batch |
| `scx_tickless` | Power saving |
| `scx_flash` | Low latency burst |

---

## Related docs
- `S2IDLE_OPTIMIZATION.md` — runtime PM, USB autosuspend, SATA link PM
- `SCREEN_OFF_MEDIA_AWARE.md` — hypridle / DPMS power saving

# VRR & SCX Scheduler — Power/Performance Tuning

**Date:** March 2026 | **Updated:** July 2026  
**Status:** VRR ❌ **Disabled** (`vrr = 0`) | SCX ✅ Active (`scx_lavd` via `scx_loader.service`)

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
    vrr = 0  # 0=off, 1=always on, 2=fullscreen-only
}
```

### Status
**Disabled.** `vrr = 0` in `hyprland.conf`, confirmed live with `hyprctl getoption misc:vrr`.
The config comment records why: *"adaptive sync disabled — fixes Chromium video frame pacing"*.

This doc previously claimed `vrr = 1` and "re-enabled April 2026" — that was stale. Leave VRR
off unless deliberately retesting: frame pacing is the dominant cause of dropped video frames on
this machine, and VRR is a known aggravator. See
[../performance/VIDEO_PLAYBACK.md](../performance/VIDEO_PLAYBACK.md). If revisiting, `vrr = 2`
(fullscreen-only) is the usual compromise rather than `1`.

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

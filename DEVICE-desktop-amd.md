# Device profile: desktop-amd (branch `hyprland-noctalia-desktop`)

Forked from `hyprland-noctalia` (laptop / Galaxy Book) and adapted for this machine.

## Hardware
- **CPU:** AMD Ryzen (AuthenticAMD)  → `amd-ucode`
- **GPU:** AMD Radeon RX 5700 XT (Navi 10), `amdgpu`  → `vulkan-radeon`, `radeonsi` VAAPI
- **Boot:** Limine (UEFI)  — *not* GRUB
- **Displays:** HP E243i 1920×1200 on **DP-3** (primary, left) + LG 1920×1080 on **HDMI-A-1** (right)
- **Input:** Logitech G213 keyboard + G502 mouse (no touchpad/lid/battery/backlight)

## Changes vs laptop branch
- `hypr/hyprland.conf`
  - monitors: `eDP-1 2880x1800@120 scale 2` → dual `DP-3` + `HDMI-A-1` scale 1
  - `env = LIBVA_DRIVER_NAME` `iHD` → `radeonsi`
  - removed touchpad block, touchpad gestures, brightness keys, middle-click-disable, battery-monitor exec-once
  - `kb_layout = de` (unchanged — already German)
- `uwsm/env`: `HYPRLAND_CONFIG=$HOME/.config/hypr/hyprland.conf`
  — forces the legacy `.conf` over the CachyOS default Lua config (`hyprland.lua`).
- `pkglist.txt` (untracked, machine-local): dropped `intel-ucode`, `intel-media-driver`,
  `intel-undervolt`, `vulkan-intel`, `lib32-vulkan-intel`, `vpl-gpu-rt`;
  added `amd-ucode`, `vulkan-radeon`, `lib32-vulkan-radeon`, `libva-mesa-driver`, `libva-utils`.
- `install.sh` GRUB / intel-undervolt / s2idle blocks auto-skip (not a Galaxy Book) — Limine used instead.

## Notes / gotchas
- **HDMI input "flapping":** the BALHVIT HDMI switch on HDMI-A-1 auto-selects whichever input
  has an active source. A second machine on input 1 (e.g. a Windows login screen) will steal it.
  This is the switch, not a driver bug — all `amdgpu`/`navi10` firmware is present.
- Backup drive: ext4 label `BACKUP`, UUID `54d81b5f-6484-435b-959c-dee4a73740f3`.

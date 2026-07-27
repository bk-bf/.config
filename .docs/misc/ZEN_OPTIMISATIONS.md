# Zen Browser Optimisations

> See also: [HELIUM_OPTIMISATIONS.md](./HELIUM_OPTIMISATIONS.md) — documents the Helium (Chromium)
> browser evaluation that preceded returning to Zen, including the memory architecture comparison.

## System context

- CachyOS, Hyprland/Wayland, Intel Arc MTL
- Display: 2880×1800 native @ 120Hz, scale=2 (logical 1440×900), eDP-1
- Zen 1.19.8b (Firefox 149.0.2 base)

---

## Problem: RAM growth over long sessions

### Observed behaviour

- Baseline on fresh start with same tab count: ~9.7 GB system used (~64%) vs ~7.3 GB (~48%) on
  Helium — a ~2.5 GB higher floor.
- RAM grows continuously over a session. `about:memory` → "Minimize memory usage" drops usage
  by only ~1% (~160 MB) and it climbs back within minutes. This confirms an active leak, not
  just jemalloc page retention.
- Swap remains barely touched (< 1 MB) — not causing pressure, but the growth trend is real.

### Root causes

**1. Gecko baseline is higher than Chromium by design.**
Chromium's Memory Saver proactively kills backgrounded tab processes and reloads on return.
Gecko has no equivalent — all tabs stay in RAM. `browser.tabs.unloadOnLowMemory` exists but
is reactive (fires only under OS memory pressure) and on a 16 GB machine that threshold rarely
triggers.

**2. Zen-specific leaks in Workspace and Glance code (partially fixed, partially open).**
The following are confirmed Zen-only bugs — not reproducible on vanilla Firefox:

| Issue | Status |
|---|---|
| Missing event listener cleanup in ZenWorkspaces JS (#12285, Jan 2026) | Fixed |
| Bitmap handle not released in Zen graphics code (#13242, Apr 2026) | Fixed (≥ 1.19.x) |
| Glance subframe memory leak (#13237, Apr 2026) | Fixed (≥ 1.19.x) |
| Remaining leaks in Workspace/Glance code paths | **Open** — tracked in META #8932 |

META issue: https://github.com/zen-browser/desktop/issues/8932 (open since Jun 2025, active).

**3. Workspaces and Glance are the leak vectors — and are in active use.**
Disabling them would stop the growth but removes Zen's core differentiators. Not viable.

---

## Applied mitigations

These are set in `about:config` and reduce the baseline but do not stop the growth:

| Pref | Value | Effect |
|---|---|---|
| `dom.ipc.processCount` | `4` | Fewer shared content processes (default 8) |
| `dom.ipc.processPrelaunch.fission.number` | `1` | Fewer preallocated processes (default 3) |
| `browser.tabs.unloadOnLowMemory` | `true` | Reactive tab unload under memory pressure |

**Note:** `dom.ipc.keepProcessesAlive.web` does not exist as a settable pref in current
Firefox/Zen builds — ignore any references to it.

**No Zen mods active** — `zen-themes.css` is empty, so `will-change: transform` layer
promotion from themes is not a factor here.

---

## Current status (Apr 2026)

No config fix eliminates the growth while keeping Workspaces and Glance enabled. The leak
lives in those code paths, and the upstream fix is not fully shipped.

**Practical options:**

1. **Wait** — #8932 is actively worked on. Update Zen and check release notes for
   workspace/memory fixes.
2. **Periodic restart** — restart Zen every few hours before RAM climbs toward swap. The
   browser state (tabs, workspaces) restores cleanly.
3. **Monitor `about:memory`** — if RSS climbs above ~12 GB system used, restart.
   The "swap stays empty" observation below no longer holds: as of Jul 2026 zram routinely
   runs full (13.1 GB of pages compressed into 4.05 GB of physical RAM, 3.32× ratio) with
   under 1 GB free. Swap pressure is now a real contributor, not a spare indicator.
4. **Fall back to Helium** — better memory behaviour (~2.5 GB lower baseline, no growth),
   but ~12% video frame drops vs ~6.5% in Zen. See
   [HELIUM_OPTIMISATIONS.md](./HELIUM_OPTIMISATIONS.md).

---

## Video playback

Zen/Gecko's Wayland presentation pipeline handles VSync and frame callbacks more robustly on
Hyprland + Intel Arc MTL than Chromium's compositor — this was the primary reason for
returning to Zen.

### Hardware decode requires a flag (corrected Jul 2026)

An earlier revision of this file claimed VA-API decode "is handled by Firefox's own pipeline
(no flags needed)". That was wrong. Gecko does **not** enable hardware video decoding by
default on Linux/Intel; it stays off unless explicitly forced.

```js
user_pref("media.hardware-video-decoding.force-enabled", true);   // ~/.zen/zen-default/user.js
```

How the software fallback was identified:

| Check | Result |
|---|---|
| `drm-engine-video` in `/proc/*/fdinfo/*`, all processes | `0 ns` — video engine never used, across a 29 h session |
| Zen decode processes holding `/dev/dri/renderD128` | none; only the parent and GPU process hold DRM fds, render-only |
| `ffmpeg -init_hw_device vaapi=/dev/dri/renderD128` | initialises cleanly |
| `LIBVA_DRIVER_NAME`, `iHD_drv_video.so` | `iHD`, present |

The driver stack was healthy throughout — Gecko simply never asked for it. Verify after any
profile change, with a video playing:

```sh
grep drm-engine-video /proc/$(pgrep -f 'zen-bin.*contentproc' | head -1)/fdinfo/*
```

The frame-drop figures above (~6.5% Zen vs ~12% Helium) were measured under software decode
and need re-measuring now that the GPU decoder is in use.

### Note on the removed `max98390` rationale

The pref previously carried a comment claiming forced hardware decode caused audio dropout on
the Samsung max98390 speakers, "when GPU decode pipeline desynchs from CPU audio thread". That
rationale does not hold and has been removed:

- The max98390 defect is device *enumeration* — three of four amps are not created by ACPI, so
  they are instantiated over I2C and bound by a DKMS module. The failure mode is *no speakers*,
  not dropouts. See [SPEAKER_FIX.md](../audio/SPEAKER_FIX.md). Both kernels currently have
  `max98390-hda/1.0` installed and the module loaded.
- The stated mechanism is backwards: A/V sync runs off a media clock that audio owns, and when
  video decode falls behind Gecko drops *video* frames to keep audio continuous.
- The pref was set to `false`, which is already Gecko's default — so it disabled nothing. It
  documented a change that never took effect.

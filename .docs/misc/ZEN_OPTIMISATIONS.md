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
3. **Monitor `about:memory`** — if RSS climbs above ~12 GB system used, restart. Below that
   the system is not actually pressured (swap stays empty).
4. **Fall back to Helium** — better memory behaviour (~2.5 GB lower baseline, no growth),
   but ~12% video frame drops vs ~6.5% in Zen. See
   [HELIUM_OPTIMISATIONS.md](./HELIUM_OPTIMISATIONS.md).

---

## Video playback

No issues. Zen/Gecko's Wayland presentation pipeline handles VSync and frame callbacks more
robustly on Hyprland + Intel Arc MTL than Chromium's compositor. Frame drops are ~6.5% vs
Helium's ~12% after all Helium fixes were applied — this was the primary reason for returning
to Zen.

VA-API hardware decode is handled by Firefox's own pipeline (no flags needed).

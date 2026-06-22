# Helium Browser Optimisations

> See also: [ZEN_OPTIMISATIONS.md](./ZEN_OPTIMISATIONS.md) — documents the RAM leak
> investigation and current status after returning to Zen.

## Problems

1. **Startup CPU spikes / system-wide lag** — resolved
2. **GPU hardware acceleration disabled** — resolved
3. **YouTube video lag / dropped frames** — resolved with hardware decode

---

## Fix 1: Startup lag

Two causes:

- **Wayland/Vulkan conflict** — `--ozone-platform=wayland` is incompatible with Helium's
  Vulkan path, causing broken init and falling back to CPU-heavy software rendering.
- **Bloated JS code cache** — 109MB of cached JS that Chromium validates/recompiles on
  every launch, spiking all cores.

**Flags applied** (see `~/.config/helium-browser-flags.conf`):

```
--ozone-platform=wayland
--disable-features=Vulkan
--js-flags=--max-old-space-size=512
```

If startup lag returns, the JS code cache has likely bloated again — clear
`~/.cache/net.imput.helium/Default/Code Cache/js/` and it'll rebuild clean.

---

## Fix 2: GPU hardware acceleration

**Root cause:** Wrong Chromium flag syntax. `--use-gl=angle` and `--use-angle=opengles` are
**deprecated** in Chromium 147. The browser ignored them and defaulted to `gl=none`, which
then triggered the crash guard ("GPU access is disabled due to frequent crashes").

**Correct flags for Chromium 147+:**

```
--gl=egl-angle
--angle=opengl
```

**Full working flags** (Intel Arc MTL, CachyOS, Hyprland/Wayland):

```
--ozone-platform=wayland
--disable-features=Vulkan
--gl=egl-angle
--angle=opengl
--ignore-gpu-blocklist
--disable-gpu-process-crash-limit
--disable-gpu-sandbox
--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoEncoder
--js-flags=--max-old-space-size=512
```

**Notes:**

- `--disable-gpu-sandbox` fixes an "FD ownership violation" crash that prevents the GPU
  process from starting. The warning in Helium's UI is cosmetic.
- `--disable-gpu-process-crash-limit` bypasses Chromium's "3 strikes" fallback that
  permanently disables GPU access after repeated crashes.
- `--angle=opengl` uses the desktop OpenGL ANGLE backend. `opengles` also works but
  `opengl` has better feature support.
- `LIBVA_DRIVER_NAME=iHD` must be set in the environment (added to `hyprland.conf`) —
  the system only has the `iHD` VA-API driver.
- `--disable-features=Vulkan` is still needed despite Vulkan appearing as "Enabled" in
  `chrome://gpu` — without it, a non-fatal Wayland/Vulkan compatibility warning fires.

**Working hardware decode profiles (confirmed):**
- H264 baseline/main/high
- VP8, VP9 profile0/profile2
- HEVC main/main 10/still-picture
- AV1 profile main

**If GPU acceleration breaks again:**

Close Helium completely, clear caches, and relaunch:

```bash
killall helium helium_crashpad_handler
rm -rf ~/.config/net.imput.helium/Default/GPUCache
rm -rf ~/.config/net.imput.helium/GrShaderCache
rm -rf ~/.config/net.imput.helium/GraphiteDawnCache
```

Then relaunch Helium. The `--disable-gpu-process-crash-limit` flag prevents the crash
 guard from re-triggering.

---

## Outcome: Rejected

**What was fixed:**
- Startup CPU spikes resolved (Wayland/Vulkan conflict + bloated JS cache)
- GPU hardware acceleration fully enabled (ANGLE OpenGL, VA-API decode for AV1/VP9/H264/HEVC)

**Why it was rejected:**

Persistent video frame drops during YouTube playback that flags could not eliminate:
- **Helium (Chromium/Blink)**: ~12% frame drops after all fixes
- **Zen (Firefox/Gecko)** on same hardware/compositor: ~6.5% drops

**Root cause of remaining drops:**
Chromium's compositor under native Wayland at 2× display scale (2880×1800 native → 1440×900 logical) has inherent frame pacing issues. The browser's `kVideoPlaybackRoughness` metric showed frames presented **7+ seconds late** (`DECODER_UNDERFLOW` events in `chrome://media-internals`), caused by the compositor missing presentation deadlines — not decode speed. Disabling Hyprland blur/VRR/VFR reduced load but did not fix the core timing jitter.

**Comparison point:**
Firefox/Gecko uses a different Wayland presentation pipeline that handles VSync and frame callbacks more robustly on this compositor/hardware combination.

**Alternative:**
Zen Browser updated to 1.19.7b (Firefox 149.0.2 base) around the same time. Firefox 149.0.2 did not contain a user-facing RAM leak fix — the security CVEs patched are exploitation bugs, not memory leaks. Whether Zen's RAM issues are resolved depends on Zen's own patches, not the Firefox base. Since Zen video playback was already smoother with half the drops, and RAM appeared stable after the update, the pragmatic choice was to return to Zen and monitor RAM usage.

---

## Memory behaviour: Zen vs Helium

> No raw memory logs exist from the session — neither browser writes them to disk by default.
> The analysis below is based on observed behaviour and upstream research (Zen GitHub, Chromium docs, Firefox source docs).

### Architecture differences

**Chromium (Helium)** uses strict one-process-per-site isolation (PartitionAlloc heap, V8 GC). Memory Saver mode proactively *kills* backgrounded tab processes and reloads them on return — this keeps resident RAM lower at the cost of reload latency. V8 is aggressive about compacting and returning freed heap to the OS between GC cycles.

**Gecko (Zen)** uses a shared content process pool (Fission site isolation, jemalloc heap, SpiderMonkey incremental GC + cycle collector). jemalloc tends to retain freed pages in its own pool rather than returning them to the kernel immediately — so `RES` in htop stays elevated even after GC. Gecko does not proactively discard backgrounded tab processes unless `browser.tabs.unloadOnLowMemory` is set.

**Net effect for a multi-tab session:** Helium will appear to use less RAM over time (Memory Saver discards old tabs); Zen will use more sustained RAM because all tabs stay loaded, but tab-switching is instant.

### Zen-specific RAM amplifiers (confirmed by Zen GitHub, 2025-2026)

These are **not** general Gecko/Firefox issues — they are Zen-specific patches that have been confirmed as RAM sources:

- **Missing event listener cleanup in Workspace JS** — PR #12285 (Jan 2026): Zen's own workspace code was not removing event listeners, causing unbounded growth over a session. Fixed.
- **Bitmap handles not closed** — PR #13242 (Apr 2026, merged): A graphics handle in Zen-specific rendering code was never released. Fixed.
- **Glance memory leak** — PR #13237 (Apr 2026, merged): Zen's page-preview (Glance) feature loaded subframes without proper principal checks, leaking content process memory. Fixed.
- **`will-change: transform` in themes/mods** — Zen's mod ecosystem promotes compositing layers for entire browser views, dramatically increasing GPU memory. Confirmed by Zen maintainer.
- **`dom.ipc.keepProcessesAlive.web`** — Zen (and Firefox) keep idle web processes warm for fast new-tab creation. Non-zero values mean closed-tab memory is not freed immediately.

Issues #12741 (10 GB for 5 tabs) and #12496 (GPU Helper reaching 2 GB) both have the "cannot reproduce on vanilla Firefox" flag set — confirming the worst cases are Zen-specific, not inherent Gecko behaviour.

META tracking issue: https://github.com/zen-browser/desktop/issues/8932 (open since Jun 2025).

### Is mirroring Chromium memory performance feasible in Zen?

**No — not fully, by design:**

Chromium's lower sustained RAM comes primarily from Memory Saver (proactive tab process killing), which Gecko does not have an equivalent of. Firefox has `browser.tabs.unloadOnLowMemory` but it's reactive (only fires under pressure) rather than proactive. SpiderMonkey's GC is also more conservative about when to collect vs V8.

**However**, the worst Zen-specific growth (the cases multiplying baseline 3–5×) are bugs in Zen's own code, not Gecko limits. The Apr 2026 merged PRs (#13242, #13237) address some of this. The baseline after fixes should be closer to vanilla Firefox levels.

### Mitigations for Zen RAM (if RAM becomes a problem again)

```
about:config tweaks:
  dom.ipc.keepProcessesAlive.web        = 0   # free idle processes immediately
  dom.ipc.processPrelaunch.fission.number = 1  # fewer preallocated processes (default 3)
  dom.ipc.processCount                  = 4   # fewer shared content processes (default 8)
  browser.tabs.unloadOnLowMemory        = true # reactive tab unload under pressure
  javascript.options.mem.gc_compacting  = true # compact heap during GC cycles
```

- Disable Zen mods that use transparency/blur (especially any using `will-change: transform`)
- Disable Glance if unused
- Use `about:memory` → "Minimize memory usage" to force a full GC + cycle collect
- Watch whether RAM stabilises after the Apr 2026 patches — #13242 and #13237 are now in Zen ≥ 1.19.x

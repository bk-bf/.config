# Video playback — frame drops on Hyprland + Intel Arc MTL

> Canonical doc for browser video performance on this laptop. Browser-specific notes live in
> [ZEN_OPTIMISATIONS.md](../misc/ZEN_OPTIMISATIONS.md) and
> [HELIUM_OPTIMISATIONS.md](../misc/HELIUM_OPTIMISATIONS.md); both link here.

## System context

- Galaxy Book 4 Ultra, Intel Core Ultra 7 155H, Arc iGPU (Meteor Lake), `i915` driver
- eDP-1: 2880×1800 @ 120 Hz, `scale = 2.0`, VRR off
- Hyprland under UWSM, Zen browser (Firefox base)
- YouTube serves **AV1 at every resolution** as of 2026 and no longer honours a VP9 preference

---

## Two independent causes, both silent

Frame drops here had two unrelated causes. Each is invisible in its own UI, and fixing one
still leaves the other. YouTube's dropped-frame counter conflates them — it counts frames the
compositor failed to paint on time *as well as* frames the decoder missed.

| | Cause | Symptom share | Fix |
|---|---|---|---|
| 1 | Hyprland blur compositing every frame | ~80% of drops | `no_blur` window rule per browser |
| 2 | Gecko never enabling VA-API decode | the rest, plus high CPU | `media.hardware-video-decoding.force-enabled` |

### Measured (2026-07-27, AV1 `av01.0.12M.08` itag 400, 2560×1440@60)

| Configuration | Dropped frames |
|---|---|
| Blur on | 710 / 2173 — **32.7%** |
| Blur off | 94 / 1452 — **6.5%** |

Buffer health was 42 s with zero network activity in both runs, so bandwidth was never a factor.

---

## Cause 1: blur is the dominant cost

`decoration:blur` with `size = 3, passes = 2` runs on every composited frame. At 2880×1800 with
`scale = 2.0` and a 120 Hz output the per-frame budget is 8.3 ms, and blurring a large browser
surface does not fit inside it while a video is also being scaled and presented.

This was **already diagnosed for Helium** and encoded as a window rule:

```conf
# hyprland.conf
windowrule = no_blur on, match:class ^(helium)$
```

When the browser moved back to Zen the rule did not follow, so the fix silently stopped
applying. Zen's window class is `zen`:

```conf
windowrule = no_blur on, match:class ^(zen)$
```

Prefer the per-window rule over disabling blur globally — it keeps blur everywhere it costs
nothing. `hyprctl keyword decoration:blur:enabled false` is runtime-only and is for testing;
it does not survive a compositor restart.

Related knobs not yet exercised: `render:direct_scanout` (currently `0`) lets a *fullscreen*
video bypass compositing entirely, which should beat `no_blur` for fullscreen playback.

---

## Cause 2: Gecko does not enable VA-API on its own

The browser's "use hardware acceleration when available" checkbox drives the **render** engine
(page drawing, compositing, WebGL). It does **not** reach the **video decode** engine, which is
separate silicon behind a separate pref with no UI, no indicator, and no error on fallback.

```js
// ~/.zen/zen-default/user.js
user_pref("media.hardware-video-decoding.force-enabled", true);
```

Requires a browser restart. See [ZEN_OPTIMISATIONS.md](../misc/ZEN_OPTIMISATIONS.md) for the
evidence trail and for the bogus `max98390` rationale that was attached to this pref.

Meteor Lake has **two** video engines (`drm-engine-capacity-video: 2`) with AV1, VP9 and H.264
decode, so the hardware was never the limitation.

---

## How to verify — and how to get it wrong

Decode happens in Firefox's **RDD process**, not the tab or parent process. Verify by watching
the GPU video engine climb:

```sh
# during playback — the RDD process is the one that moves
for p in $(pgrep -f zen-bin); do
  v=$(grep -h "^drm-engine-video:" /proc/$p/fdinfo/* 2>/dev/null | grep -v ":.0 ns" | head -1)
  [ -n "$v" ] && echo "PID $p -> $v"
done
```

Four ways this measurement lies, all encountered while diagnosing this:

1. **fdinfo counters die with the process.** The RDD process exits when playback goes idle,
   taking its counters with it. A reading of `0 ns` taken after playback proves nothing — it
   must be sampled *during*. This invalidated the initial "hardware decode never ran in 29 h"
   conclusion.
2. **A 4:4:4 test clip falls back to software.** VA-API decodes 4:2:0; `ffmpeg` encoding from
   `testsrc` produces `yuv444p` by default and silently software-decodes. Use `-pix_fmt yuv420p`
   and confirm the log says `Reinit context to …, pix_fmt: vaapi`.
3. **`timeout cmd &` yields the wrapper's PID**, not the command's, so `/proc/$!/fdinfo` is empty.
4. **`grep -m1 … /proc/$pid/fdinfo/*` picks an arbitrary fd** and different fds carry different
   counters, so successive samples are not comparable and deltas can come out negative. Sum
   across all fds (accepting overcount from aliasing) or pin one fd.

The i915 PMU on this platform exposes `bcs`/`ccs` events but **no `vcs`** (video) events, so
`perf` is not an alternative here. `intel_gpu_top` is not installed.

---

## Order of attack for future drops

1. Read YouTube **Stats for nerds** first — codec, resolution, and the dropped ratio. Everything
   else is inference; this is ground truth, and the counter never resets, so reload before timing.
2. Check buffer health and network activity to rule out bandwidth.
3. Toggle blur off at runtime and re-measure on a fresh load.
4. Confirm the video engine is moving during playback (above).
5. Only then look at system load, governor, and power state.

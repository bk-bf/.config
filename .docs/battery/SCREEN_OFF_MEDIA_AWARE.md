# Media-Aware Screen-Off & Lock Screen (hypridle + noctalia)

**Date:** March 14, 2026  
**Status:** ✓ Active

---

## Problem

Firefox and Chromium-based browsers do not set the Wayland idle inhibitor for
windowed video (they only do so in fullscreen). This means watching a YouTube
video in a normal window would cause the screen to turn off and lock mid-playback,
as neither hypridle nor noctalia's idle service could detect an active video.

---

## Setup

Screen-off, lock screen, and idle suspend are all owned exclusively by
**hypridle**. Noctalia's idle manager is disabled and its suspend-time lock hook
is turned off to avoid races and to ensure all idle actions pass through the
same media-aware guards.

The setup is intentionally minimal now:
- **Fullscreen** prevents idle actions during fullscreen video, including muted video.
- **Active audio** prevents idle actions during non-fullscreen playback or music.
- **Before-sleep lock** only checks fullscreen, since audio becomes irrelevant once suspend actually happens.

### Files

| File                                                                                                       | Purpose                                                              |
| ---------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `hypr/hypridle.conf`                                                                                       | Idle config — calls the unified idle action script                   |
| `hypr/scripts/idle-action.sh`                                                                              | Single entrypoint for screen-off, lock, suspend, and before-sleep    |
| `noctalia/settings.json` (`idle.enabled: false`, `idle.suspendTimeout: 0`, `general.lockOnSuspend: false`) | Disables Noctalia idle/suspend locking so hypridle is the only owner |

### How it works

hypridle fires after **240 s** of inactivity and calls
`idle-action.sh screen-off` instead of `dpms off` directly. The script checks:

1. **Fullscreen window** — if any Hyprland client has `fullscreen` set (e.g.
   a browser in fullscreen video mode), the script exits without touching the
   display.
2. **PipeWire/PulseAudio sink inputs** — if any sink input is in `RUNNING`
   state (covers browser tabs playing audio, music players, etc.) the script
   exits without touching the display.
3. **Otherwise** — `hyprctl dispatch dpms off` runs as normal.

On any input activity, hypridle's `on-resume` turns the display back on
unconditionally.

hypridle also fires after **660 s** of inactivity and calls `idle-action.sh lock`
instead of `loginctl lock-session` directly. The same fullscreen/audio checks
apply; locking is skipped if any guard condition is true.

hypridle also fires after **1800 s** of inactivity and calls
`idle-action.sh suspend` instead of letting Noctalia manage suspend directly.
The same fullscreen/audio checks apply; suspend is skipped if any guard
condition is true.

Before suspend, hypridle calls `idle-action.sh before-sleep` instead of
`loginctl lock-session` directly. Only the fullscreen check applies here —
audio checks are omitted since audio stops on suspend anyway. This keeps the
pre-suspend lock behavior separate from the idle suspend decision.

---

## Limitations

- Muted browser video **not** in fullscreen with no audio output will still
  cause the screen to turn off and lock — there is no Wayland-level signal
  available for windowed video without browser cooperation.
- If audio stops after an idle timeout has already fired (and was skipped), the
  screen-off/lock/suspend won't trigger until the next idle cycle (user must
  become active then idle again).
- Skipping the pre-suspend lock when fullscreen is a minor security tradeoff:
  if the system is suspended by some other path while fullscreen video is
  playing, it may resume without a lock screen.

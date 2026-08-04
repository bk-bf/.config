# `.docs` — machine documentation

Durable findings about this laptop (Samsung Galaxy Book4 Ultra, Intel Core Ultra 7 155H / Arc
iGPU, CachyOS, Hyprland under UWSM). Each doc records a *mechanism* and how it was verified, not
just a recipe.

**Conventions**

- Docs state what was **measured**, with the command that measures it. Verify against the
  kernel or live state, never against a config file — a config file is a claim.
- Superseded content is corrected in place with a dated note rather than deleted, so the
  reasoning stays legible.
- Anything under `archived/` describes a subsystem that **no longer exists**. Kept for history;
  never treat as current.

---

## Performance

| Doc | Covers |
|---|---|
| [performance/CPU_PRIORITY.md](./performance/CPU_PRIORITY.md) | cgroup weights so dev work yields to the desktop; the `bgr` wrapper; why weights only compare siblings |
| [performance/MEMORY_PRESSURE.md](./performance/MEMORY_PRESSURE.md) | `MemoryLow` protection vs `MemoryHigh` caps, the 2026-07 inversion, scoped `systemd-oomd`, the Claude reaper |
| [performance/MEMORY_RECLAIM.md](./performance/MEMORY_RECLAIM.md) | Leaked processes that outlive their owner; measuring committed memory rather than RSS |
| [performance/VIDEO_PLAYBACK.md](./performance/VIDEO_PLAYBACK.md) | Frame drops: Hyprland blur, VA-API decode, CPU contention; four ways the measurement lies |
| [performance/CRASH_HISTORY.md](./performance/CRASH_HISTORY.md) | Running log of session losses — 2026-07-28 SIGKILL (**open**), 2026-07-23/24 OOM teardowns |
| [performance/THERMAL_OPTIMIZATION.md](./performance/THERMAL_OPTIMIZATION.md) | Turbo/PL1 behaviour, `intel-undervolt`; why `cpufreq/boost` does not exist here |

## Power & battery

| Doc | Covers |
|---|---|
| [battery/S2IDLE_OPTIMIZATION.md](./battery/S2IDLE_OPTIMIZATION.md) | Suspend path and its service/script |
| [battery/VRR_AND_SCX_SCHEDULER.md](./battery/VRR_AND_SCX_SCHEDULER.md) | `scx_lavd` scheduler; VRR is **disabled** (it hurt video frame pacing) |
| [battery/SCREEN_OFF_MEDIA_AWARE.md](./battery/SCREEN_OFF_MEDIA_AWARE.md) | Media-aware screen blanking |
| [power/BATTERY_DETECTION.md](./power/BATTERY_DETECTION.md) · [power/WORKSPACE_SNAPSHOT.md](./power/WORKSPACE_SNAPSHOT.md) | AC/battery detection; workspace snapshotting |

## Hardware

| Doc | Covers |
|---|---|
| [audio/SPEAKER_FIX.md](./audio/SPEAKER_FIX.md) | MAX98390 amps: ACPI creates one of four, DKMS module binds the rest over I2C |
| [TOUCHSCREEN_UDEV.md](./TOUCHSCREEN_UDEV.md) | Suppressing the GXTP7936 touchscreen from libinput |
| [boot/LIMINE.md](./boot/LIMINE.md) | Bootloader (Limine, **not** GRUB) |

## Desktop & session

| Doc | Covers |
|---|---|
| [ui/UWSM_SESSION.md](./ui/UWSM_SESSION.md) | How the Hyprland session is started and what owns which cgroup |
| [ui/THEME_SYNC.md](./ui/THEME_SYNC.md) | Noctalia → GTK/kitty/polkit theme propagation |
| [auth/POLKIT_AGENT.md](./auth/POLKIT_AGENT.md) | Polkit agent selection and theming |
| [sddm/HIDPI.md](./sddm/HIDPI.md) | Display-manager scaling |

## Browsers

| Doc | Covers |
|---|---|
| [misc/ZEN_OPTIMISATIONS.md](./misc/ZEN_OPTIMISATIONS.md) | Zen RAM growth, upstream leak tracking, hardware-decode flag |
| [misc/HELIUM_OPTIMISATIONS.md](./misc/HELIUM_OPTIMISATIONS.md) | The Chromium evaluation that preceded returning to Zen — historical, not current |

## Monitoring

| Doc | Covers |
|---|---|
| [monitoring/WARDEN.md](./monitoring/WARDEN.md) | Journal watcher → notification → headless triage session; the three mechanisms that keep it quiet; `session_args` as the authority switch |

## Packages & sync

| Doc | Covers |
|---|---|
| [packages/PACKAGE_TRACKING.md](./packages/PACKAGE_TRACKING.md) | Package list tracking across hosts |
| [packages/PACDIM.md](./packages/PACDIM.md) | The pacman/yay output recolouring filter |
| [SESSION-PACKAGE-PROFILES.md](./SESSION-PACKAGE-PROFILES.md) | Per-session package profiles |
| [sync/CLAUDE-SESSIONS-SYNC.md](./sync/CLAUDE-SESSIONS-SYNC.md) | Claude session sync to the server |
| [SYSTEM_SYMLINKS.md](./SYSTEM_SYMLINKS.md) | Every symlink from this repo into system paths |

---

## Archived

Subsystems that no longer exist. Each carries a banner explaining what replaced it.

- `archived/taildrop-obsidian/` — Taildrop→Obsidian sync; scripts and vault path both gone
- `archived/hibernation/` — hibernation setup, superseded by s2idle
- `archived/gdm/` — GDM lock screen, superseded by SDDM
- `archived/swayfx+waybar/` — the pre-Hyprland desktop

---

## Auditing this tree

Catches the two most common forms of rot:

```sh
cd ~/.config/.docs

# 1. referenced paths that no longer exist (expect a few intentional absences —
#    THERMAL_OPTIMIZATION.md documents paths precisely because they are missing)
for f in $(find . -name '*.md' -not -path './archived/*'); do
  grep -oE '`(~|/)[A-Za-z0-9~._/@-]+`' "$f" | tr -d '`' | sort -u | while read p; do
    e="${p/#\~/$HOME}"; [ -e "$e" ] || echo "$f -> $p"
  done
done

# 2. broken cross-references between docs
for f in $(find . -name '*.md' -not -path './archived/*'); do
  d=$(dirname "$f")
  grep -oE '\]\(\.{1,2}/[A-Za-z0-9._/-]+\.md\)' "$f" | sed 's/](//;s/)//' | sort -u |
    while read l; do [ -e "$d/$l" ] || echo "$f -> $l"; done
done
```

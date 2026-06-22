# Session-Scoped Package Profiles

Status: RESEARCH
Problem: installed packages are system-wide on CachyOS/Arch; no native mechanism
to "disable" packages per compositor session without uninstalling them.

---

## Problem Statement

Git worktrees give per-branch config isolation (hyprland-noctalia vs niri-noctalia).
The missing half: packages like `hyprpaper`, `hyprlock`, `xdg-desktop-portal-hyprland`
are meaningless noise when running a niri session, and niri-specific packages
(`niri`, `xwayland-satellite`) are unused on hyprland. The goal is to switch
sessions cleanly — activating the right set — without uninstalling anything.

Uninstalling is unacceptable because:
- pacman dependency solver may pull in unwanted removals
- reinstalling is slow and requires internet
- orphan tracking becomes noisy
- breaks the mental model: packages are installed, just not active

---

## What "Disable" Actually Means Per Layer

| Layer | Hyprland-specific | Niri-specific | Shared |
|---|---|---|---|
| Compositor | hyprland | niri | — |
| Portal | xdg-desktop-portal-hyprland | xdg-desktop-portal-gnome (or -wlr) | xdg-desktop-portal |
| Idle daemon | hypridle | (hypridle works on niri too) | hypridle |
| Wallpaper | hyprpaper | — (noctalia handles it?) | — |
| XWayland | built-in | xwayland-satellite | — |
| Lock screen | (noctalia) | (noctalia) | noctalia |

Most "session packages" are daemons — the real problem is: which daemons
start, not which binaries are on disk.

---

## Candidate Approaches

### A. systemd session targets (service-level, not package-level)

UWSM already activates `hyprland-session.target` or `niri-session.target`.
Each target can `Wants=` a different set of `.service` units.

- Packages remain installed but only the right daemons start
- xdg-desktop-portal portals are selected by `XDGDP_PORTAL_*` env vars or by
  which portal .service is enabled — already session-scoped
- Effectively solves the daemon problem without touching packages at all
- Does NOT solve: packages occupying disk space or pacman orphan noise

Status: probably sufficient for the real use case. Investigate first.

### B. pacman "meta" packages / explicit hold list

Maintain `packages/hyprland.txt` and `packages/niri.txt` (output of `pacman -Qqe`).
A reconcile script installs missing, but does NOT remove extras.
Packages from the inactive session stay installed — this is acceptable if
the goal is "activate", not "uninstall".

Downside: no enforcement. The inactive session's packages drift silently.

### C. pacman local repo + `--asdeps` marking

Install session-specific packages as dependencies (`pacman -S --asdeps niri`),
not as explicit. They won't appear in `pacman -Qqe` and `pacman -Rns` will
sweep them when their "parent" is removed. Fragile, confusing ownership.

### D. Nix / home-manager profiles

Nix profiles are first-class "named sets of packages". `nix profile switch` or
`home-manager switch` atomically activates a profile. Packages not in the
active profile are still in the store (not uninstalled) but not on PATH.

- True "disable without uninstall" semantics
- `home-manager` can also own dotfiles — replaces the git worktree approach
- High adoption cost on CachyOS; conflicts with pacman-managed system packages
- Nix store grows unboundedly unless `nix-collect-garbage` is run

### E. Flatpak per-session (partial)

For GUI apps (browsers, etc.) that differ per session, Flatpak sandboxing
already isolates them. Not applicable to compositor infrastructure packages.

### F. distrobox / toolbox containers

Session-specific packages installed inside a container image. The container
is the "profile". Absurd overhead for compositor-level packages.

---

## Open Questions

1. Is the real problem daemons starting (→ solved by systemd targets, approach A)?
   Or is it actual package set divergence (different binaries needed)?
2. Does xdg-desktop-portal already handle portal selection per-session without
   any manual intervention on CachyOS with UWSM?
3. Are there any packages that would conflict if both sessions are installed
   simultaneously (e.g., two portals both owning the same D-Bus name at boot)?
4. Is Nix home-manager viable alongside CachyOS's pacman without constant friction?

---

## Likely Resolution

Approach A (systemd session targets) probably covers the real need:
- Nothing to uninstall
- Daemons are scoped to the active session automatically
- UWSM + xdg-desktop-portal already implement most of this

Investigate: run both sessions installed simultaneously and observe what
actually breaks vs what is just cosmetic noise. The answer likely determines
whether anything beyond approach A is needed.

---

## Related

- `.docs/NIRI-MIGRATION.md` — migration spec, step 6 (UWSM session launch)
- UWSM docs: https://github.com/Vladimir-csp/uwsm

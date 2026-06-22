# Polkit Authentication Agent

## Setup

The polkit authentication agent (`polkit-gnome`) runs as a systemd user service with automatic
restart. This ensures the password dialog is always available for privileged apps (Timeshift,
network manager, etc.) even if the agent crashes.

**Service file:** `~/.config/systemd/user/polkit-agent.service`

```ini
[Unit]
Description=Polkit Authentication Agent (GNOME)
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
```

Enabled via:
```bash
systemctl --user enable --now polkit-agent.service
```

**Not** started via `exec-once` in `hyprland.conf` — the systemd service supersedes that.
`gnome-keyring-daemon` is still launched via `exec-once` for secrets management (separate concern).

`theme-sync.sh` restarts this service on every color scheme change. GTK3 apps load CSS at
startup and have no live-reload mechanism, so a restart is required for the new theme to appear
in auth dialogs.

---

## Why Not exec-once

`exec-once` in Hyprland fires once at startup and never restarts if the process dies. If the agent
crashes (e.g. due to failed auth storms hitting `pam_faillock`), all subsequent pkexec calls silently
fail — apps requiring elevated privileges either crash or do nothing.

The systemd service with `Restart=on-failure` auto-recovers within 2 seconds.

---

## pam_faillock Lockout

Sudo and polkit both go through `pam_faillock`. The default config (`/etc/security/faillock.conf`)
locks the account after **3 consecutive failures** for **10 minutes**.

When locked, PAM returns auth failure even for the correct password — it does not tell you the
account is locked, it just says incorrect password.

**To unlock immediately:**
```bash
faillock --user kirill --reset
```

**To check current lock state:**
```bash
faillock --user kirill
```

This is unrelated to the keyring or gnome-keyring. Sudo passwords come from `/etc/shadow` via
`pam_unix` — the keyring stores only application secrets (WiFi, browser credentials, etc.).

---

## pam_systemd_home.so Breaking sudo (systemd 260)

**Symptom:** `sudo` always fails with "incorrect password" regardless of what you type. `passwd` and `su` still work fine.

**Root cause:** `/etc/pam.d/system-auth` includes `pam_systemd_home.so` with `success=2` — meaning if the module succeeds, skip the next 2 lines (which include `pam_unix.so`, the module that actually checks `/etc/shadow`). The `-` prefix only skips the module if the `.so` file is missing entirely; if the file exists but the service is dead, the module still runs.

`systemd-homed` has never been enabled on this system. Before **systemd 260** (landed 2026-03-23), `pam_systemd_home.so` returned a fall-through result when homed wasn't running, so `pam_unix.so` was reached normally. In systemd 260 the module's behavior changed — it now returns a result that triggers the `success=2` jump, skipping `pam_unix.so` entirely.

**Fix:** In `/etc/pam.d/system-auth`, change the jump count on the `pam_systemd_home.so` auth line from `success=2` to `success=1`:

```
# Before (broken with systemd 260 + homed inactive):
-auth      [success=2 default=ignore]  pam_systemd_home.so

# After (correct):
-auth      [success=1 default=ignore]  pam_systemd_home.so
```

This makes the module a no-op when homed isn't running — if it somehow succeeds it only skips itself, and `pam_unix.so` is always reached.

**Do not enable systemd-homed** to work around this. Homed manages home directories as encrypted images; migrating an existing `/home/kirill` into it is destructive and adds no benefit on a single-user desktop.

**If sudo breaks again after a PAM/systemd update**, check this line first — package updates can overwrite `/etc/pam.d/system-auth` back to `success=2`.

---

## Related

- [THEME_SYNC.md](../UI/THEME_SYNC.md) — restarts this service on every color scheme change; GTK3 apps have no CSS live-reload so a restart is the only way to apply new colors to the auth dialog
- [UWSM_SESSION.md](../UI/UWSM_SESSION.md) — explains why `PartOf=graphical-session.target` requires UWSM; without it this service never auto-starts

> **ARCHIVED (2026-07-28).** This subsystem no longer exists. `~/.config/taildrop-sync/` is
> gone, both scripts it describes are absent, and the vault it targeted
> (`~/Documents/Obsidian/`) has moved to `~/Documents/remote/notes`. Kept for history only —
> nothing here reflects the current machine. Current sync:
> [../../sync/CLAUDE-SESSIONS-SYNC.md](../../sync/CLAUDE-SESSIONS-SYNC.md).

# Taildrop Obsidian Server Sync

This setup watches a directory on the remote Ubuntu host and pushes changed files over Taildrop, then receives them on this machine into Obsidian under `notes/projects/infrastructure/Server-Infrastructure`.

## Script Locations

- Sender (run on Ubuntu): `/home/kirill/.config/taildrop-sync/taildrop-watch-push.sh`
- Receiver (run on local kirill machine): `/home/kirill/.config/taildrop-sync/taildrop-recv-into-obsidian.sh`

## Receiver Service (Always On)

Receiver script now manages its own `systemd --user` service by default.

Start or ensure receiver service is running:

```bash
/home/kirill/.config/taildrop-sync/taildrop-recv-into-obsidian.sh
```

Check receiver status:

```bash
/home/kirill/.config/taildrop-sync/taildrop-recv-into-obsidian.sh --status
```

Follow receiver logs:

```bash
/home/kirill/.config/taildrop-sync/taildrop-recv-into-obsidian.sh --logs
```

Stop receiver:

```bash
/home/kirill/.config/taildrop-sync/taildrop-recv-into-obsidian.sh --stop
```

Run receiver in current terminal (no service install):

```bash
/home/kirill/.config/taildrop-sync/taildrop-recv-into-obsidian.sh --foreground
```

Managed systemd user unit:

- `/home/kirill/.config/systemd/user/taildrop-recv-obsidian.service`

Common commands:

```bash
systemctl --user daemon-reload
systemctl --user enable --now taildrop-recv-obsidian.service
systemctl --user status taildrop-recv-obsidian.service
journalctl --user -u taildrop-recv-obsidian.service -f
```

## Remote Sender Usage

Default behavior installs or updates a per-instance `systemd --user` service and enables it.
If no `--name` is provided, instance name defaults to a deterministic hash of `--dir`.

Run from any directory you want to watch, or pass `--dir` explicitly:

```bash
/home/kirill/.config/taildrop-sync/taildrop-watch-push.sh --target <kirill-device-name>
```

Watch a specific directory:

```bash
/home/kirill/.config/taildrop-sync/taildrop-watch-push.sh --target <kirill-device-name> --dir /path/to/docs
```

Only send markdown files:

```bash
/home/kirill/.config/taildrop-sync/taildrop-watch-push.sh --target <kirill-device-name> --include '\\.md$'
```

Set an explicit instance name:

```bash
/home/kirill/.config/taildrop-sync/taildrop-watch-push.sh --target <kirill-device-name> --name my-sync
```

Run in current terminal (no service installation):

```bash
/home/kirill/.config/taildrop-sync/taildrop-watch-push.sh --target <kirill-device-name> --foreground
```

Check sender status:

```bash
# list all taildrop-watch-push user services
/home/kirill/.config/taildrop-sync/taildrop-watch-push.sh --status

# check one named instance
/home/kirill/.config/taildrop-sync/taildrop-watch-push.sh --status --name my-sync
```

Stop sender:

```bash
# stop default/per-dir instance
/home/kirill/.config/taildrop-sync/taildrop-watch-push.sh --stop

# stop named instance
/home/kirill/.config/taildrop-sync/taildrop-watch-push.sh --stop --name my-sync
```

For autostart without login (once per user):

```bash
sudo loginctl enable-linger "$USER"
```

## Data Flow

1. Sender runs an initial sync pass over existing files in the watch directory.
2. Sender watches recursively via `inotifywait` for ongoing changes.
3. On match, sender encodes the relative path into Taildrop filename by replacing `/` with `__`.
4. Sender Taildrops each file to the target device (with retries).
5. Receiver service gets Taildrop files continuously.
6. Receiver writes files into:

`/home/kirill/Documents/Obsidian/notes/projects/infrastructure/Server-Infrastructure`

Relative subpaths are preserved.

## Notes

- Sender `systemd --user` unit files are written to `~/.config/systemd/user/` as `taildrop-watch-push-<instance>.service`.
- Sender logs are written under `${XDG_CACHE_HOME:-$HOME/.cache}/taildrop-sync/`.
- If `systemd --user` is unavailable, sender falls back to `nohup` background mode (not reboot-persistent).
- Sender retries each transfer up to 3 times before giving up on that file.
- If sender logs show `file access denied`, set Tailscale operator once on sender: `sudo tailscale set --operator=$USER`.
- Deletes are not propagated.
- Temporary files (`*.swp`, `*.tmp`, `*~`, etc.) are ignored by sender.
- Dependencies:
  - `tailscale`
  - `inotifywait` (`inotify-tools` package)

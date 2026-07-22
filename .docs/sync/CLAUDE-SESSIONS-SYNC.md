# Claude Code Session Sync (osync hub)

Keeps `~/.claude/projects/` — Claude Code transcripts (`*.jsonl`), per-project
`memory/`, and `.hidden-sessions.json` — consistent across all your devices.

**Replaced** the old git+GitHub sync (`claude-git-sync`/`-watch` services, per-file
newer-wins over a private GitHub repo + Tailscale pokes). That was flaky; this is
plain bidirectional [osync](https://github.com/deajan/osync), managed via
[osync-dash](https://github.com/bk-bf/osync-dash) (`osd`).

## Architecture — central hub

```
   laptop  ~/.claude/projects  ⇄─┐
                                  ├─►  ubuntuserver  /home/ubuntu/claude-code-sessions   (always-on hub)
   desktop ~/.claude/projects  ⇄─┘
   (future devices)            ⇄─┘
```

- The **hub is ubuntuserver** (`ubuntu` ssh alias → pinned Tailscale IP
  `100.122.63.6`), always on. Each device runs an osync job that bidirectionally
  syncs its `~/.claude/projects/` with the hub dir `/home/ubuntu/claude-code-sessions/`.
- **Newest-wins** (osync default: newer mtime wins; ties → the local/initiator side).
- Because every device syncs to the *same* hub dir, the hub holds the **union** of
  all devices' sessions, and each device pulls the union back — so you can reach
  **all** your Claude Code sessions from any device, independent of whether any
  other device is awake. Onboard a new device by just adding its osd host.

## Per-device osync host

Each device has its own config in `~/.config/osync/`, with a **unique**
INSTANCE_ID (so their state on the hub doesn't collide):

- laptop → `claude-sessions-laptop.conf`  (this machine)
- desktop → `claude-sessions-desktop.conf`
- `<device>` → `claude-sessions-<device>.conf`

All point at the same hub: `ssh://ubuntu@ubuntu:22//home/ubuntu/claude-code-sessions`,
mode `ts` (Tailscale), direction bidirectional.

## Onboard a device

1. Install osync-dash (`git clone …/osync-dash && ./install.sh`).
2. `osd` → press `a` → fill: name `claude-sessions-<device>`, local dir
   `~/.claude/projects`, device/host `ubuntu` (or the tailnet IP `100.122.63.6`),
   remote user `ubuntu`, remote dir `/home/ubuntu/claude-code-sessions`,
   direction ⇄ Bidirectional. Or copy an existing `claude-sessions-*.conf` and
   change `INSTANCE_ID` + `INITIATOR_SYNC_DIR`.
3. First run seeds/merges with the hub.

## Running the sync

- On demand: `osd` → select the host (`n`) → `s` to sync, or
  `osync-dash --sync -c ~/.config/osync/claude-sessions-<device>.conf`.
- Automatic (optional): add a systemd user timer that runs
  `osync.sh ~/.config/osync/claude-sessions-<device>.conf --silent` every few
  minutes (osync's rsync delta makes repeat runs cheap). Not installed by
  default — the old always-on watcher is intentionally gone.

## Backup

The old GitHub repo `github.com/bk-bf/claude-code-sessions` (private) was kept as
a **frozen point-in-time backup** (final push before the local `.git` was
removed). It no longer receives updates; delete it whenever you like. Ongoing
durability now comes from the hub + every device holding a full copy.

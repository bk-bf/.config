# Claude Code Session Sync (Git + GitHub)

Two coordinated pieces keep Claude Code consistent across the desktop
(`cachyos-x8664-desktop`, `100.110.253.23`) and laptop (`cachyos-x8664-1`, `100.89.239.11`):

- **A. Session sync** — `~/.claude/projects/` is a git repo pushed to a **private** GitHub repo.
  Each device auto-commits, auto-pushes, and auto-pulls. Realtime while both are awake.
- **B. Hidden-sessions sync** — the VS Code "hidden sessions" list (`hiddenSessionIds`) is synced so
  a session you hide on one device is hidden on the other. **Files are never deleted** for this;
  hiding is the mechanism for clearing UI bloat, and the `.jsonl` stays (backed up by piece A).

- **Repo:** `github.com/bk-bf/claude-code-sessions` (**private**)
- **Synced path:** `~/.claude/projects/` — transcripts (`*.jsonl`), per-project `memory/`, and the
  shared `.hidden-sessions.json` used by piece B.

> This backs up full conversation transcripts + Claude memory files to GitHub. The repo is private,
> but the data leaves the machines. Keep it private.

## Script Locations (identical on both machines)

- Session sync (commit → pull → newer-wins resolve → push → realtime poke): `~/.local/bin/claude-git-sync.sh`
- Watcher (debounced auto-commit+push on change): `~/.local/bin/claude-git-watch.sh`
- Hidden-sessions sync (called first by the sync script): `~/.local/bin/claude-hidden-sync.sh`
- Peer config (per-machine `PEER_IP`/`PEER_USER`): `~/.config/claude-git-sync/config`
- Resume hook (installed with sudo): `/usr/lib/systemd/system-sleep/claude-git-sync`
- Logs: `~/.claude/claude-git-sync.log`, `~/.claude/claude-hidden-sync.log`

## systemd User Units (both machines)

- `~/.config/systemd/user/claude-git-watch.service` — the change watcher.
- `~/.config/systemd/user/claude-git-sync.service` — oneshot sync (timer + resume hook use it).
- `~/.config/systemd/user/claude-git-sync.timer` — periodic sync **every 2 min** (auto-fetch backstop).

```bash
systemctl --user daemon-reload
systemctl --user enable --now claude-git-watch.service claude-git-sync.timer
tail -f ~/.claude/claude-git-sync.log ~/.claude/claude-hidden-sync.log
loginctl enable-linger "$USER"    # autostart without an active login (once per machine)
```

## Realtime (peer poke)

GitHub can't push to your devices, so after a machine pushes new commits it sends a one-line
Tailscale **poke** to the peer (`ssh PEER 'systemctl --user start --no-block claude-git-sync.service'`)
that triggers an immediate pull. Both awake → sync in seconds. Peer asleep/offline → the poke no-ops
and the 2-min timer + resume hook cover it. Loop-safe: a device only pokes when it actually pushed
new commits, so a pull-only run never pokes back.

## Resume Hook (lazy pull on lid-open)

Installed as root on each machine (mainly the laptop, which sleeps):

```bash
sudo install -m 755 ~/.config/claude-git-sync/resume-hook.sh /usr/lib/systemd/system-sleep/claude-git-sync
```

On resume it triggers `claude-git-sync.service` in the user session. This is a passive effect — when
the machine is awake the script simply runs and syncs.

## Data Flow / Sync Cycle

`claude-git-sync.sh` runs on three triggers: file change (watcher, 5s debounce), the 2-min timer,
and resume-from-sleep. Each run, under a `flock` guard:

1. Run `claude-hidden-sync.sh` (piece B — see below).
2. `git add -A` + commit local changes (message tagged host + UTC; watcher commits at change-time).
3. If the remote is unreachable, stop — the local commit is pushed on a later cycle.
4. `git pull --no-edit --no-rebase` (merge). On conflict, auto-resolve **newer-commit-wins per file**
   (incl. delete-vs-edit → the newer side's deletion propagates). Never blocks on manual resolution.
5. `git push`; if we pushed new commits, **poke the peer**.

## Conflict Rule (piece A)

Newer-commit-wins per file, fully automatic. Because the watcher commits at change-time, "newer"
reflects the genuinely newer edit even across an offline gap. Everything is in git history, so any
resolution is recoverable. Lossy edge case: editing the **same** session on **both** machines at once
— later-committed wins, the other's lines for that file live only in history. Different sessions
(the normal case) are safe.

## B. Hidden-Sessions Sync

**Problem:** the VS Code "delete" button only **hides** a session — it adds the id to
`hiddenSessionIds` inside the `Anthropic.claude-code` blob in
`~/.config/Code/User/globalStorage/state.vscdb`. It does not delete the file, and the list is
per-machine (VS Code Settings Sync does **not** carry it). So hides don't cross devices.

**Mechanism (`claude-hidden-sync.sh`, run at the top of every sync cycle):**

1. Read local `hiddenSessionIds` from `state.vscdb`.
2. Union with the shared `~/.claude/projects/.hidden-sessions.json` (hide-wins).
3. If changed, write the union to the shared file → it rides piece A's commit/pull/push/poke.
4. Apply the peer's ids into `state.vscdb` via an **atomic in-SQL merge** (`json_set` + `json_each`,
   add-only) — it merges into the *current* on-disk value, so it can never clobber a hide you just
   made (this closed a lost-update race where the last few hides in a burst kept reappearing).

Each device's `state.vscdb` is the source of truth for *its own* hides; the shared file accumulates
the union. Unioning local ∪ shared every run is self-healing — it converges even if the git
newer-wins merge overwrites the shared file wholesale or VS Code rewrites `state.vscdb` from memory.

**Caveats:**
- **Reload to display peer hides.** VS Code caches the list in memory, so a hide that arrived *from
  the other machine* only shows after "Developer: Reload Window". Your *own* hides show immediately.
- **Hide-wins / monotonic.** Un-hiding does **not** propagate — the peer still has it hidden and
  re-hides it. This is intended (clearing bloat), not a bug.
- One-time pristine DB backup per machine: `~/.claude/backups/state.vscdb.orig`.
- `state.vscdb` is gitignored in the public `~/.config` repo, so its contents never leak there.

## Onboarding a New Device

```bash
cd ~/.claude/projects
gh auth setup-git                 # if pushing over https
git init -q -b main
git config user.name "bk-bf"; git config user.email "boychenkokirill@gmail.com"
git config pull.rebase false
printf '.DS_Store\n*.tmp\n*.swp\n' > .gitignore
git add -A && git commit -q -m "baseline: $(hostname -s)"
git branch -f preadopt-$(hostname -s)      # safety snapshot of pre-join state
git remote add origin https://github.com/bk-bf/claude-code-sessions.git
git fetch -q origin
git merge --allow-unrelated-histories --no-edit -X theirs origin/main -m "onboard"
git branch --set-upstream-to=origin/main main
git push -q origin main
# copy the scripts + units + resume hook from another device, write ~/.config/claude-git-sync/config
# with this machine's PEER_IP, then: systemctl --user enable --now claude-git-watch.service claude-git-sync.timer
```

## Recovery

```bash
git -C ~/.claude/projects log --oneline
git -C ~/.claude/projects restore <file>
git -C ~/.claude/projects checkout <sha> -- <file>
cp ~/.claude/backups/state.vscdb.orig ~/.config/Code/User/globalStorage/state.vscdb   # (VS Code closed)
```

## Notes

- Deletes **are** propagated by piece A (newer-wins) — but session *removal for UI bloat* is piece B
  (hide), not deletion. Files stay on disk as backup.
- Biggest risk to the push: GitHub's **100 MB per-file** limit. Session `.jsonl` grow by appending;
  the sync logs a WARN + desktop-notifies at 95 MB. `.git` also carries deleted history (recoverable
  but not space-free); reclaiming means rewriting history — don't, without intent.
- Pause everything: `systemctl --user stop claude-git-watch.service claude-git-sync.timer`.
- Dependencies: `git`, `gh` (authenticated), `inotifywait` (`inotify-tools`), `jq`, `sqlite3`, `rsync`.
- This replaced an earlier Tailscale-SSH + rsync design (torn down); that bidirectional no-delete
  rsync once resurrected deleted sessions — do not reintroduce it.

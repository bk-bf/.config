# Agents

Instructions for AI agents (OpenCode, etc.) working in this repository.

## What this repo is

Personal Arch/CachyOS dotfiles for a Hyprland + Noctalia desktop. Configuration only — no build system, no tests. Changes here affect a live system.

## Rules

- **Never commit secrets.** Check `.git/info/exclude` and `.gitignore` before staging anything new.
- **Always commit and push.** In this repo, commit every change and push it to origin without being asked.
- **Never create git worktrees** (`git worktree add`, EnterWorktree, or any auto-isolation) unless I explicitly ask for one. This is a dotfiles repo — the working copy *is* the live config, so edit files in place here. (Enforced for background jobs via `worktree.bgIsolation: "none"` in `.claude/settings.json`.)
- **Never install packages** or run `yay`/`pacman` unless explicitly asked.
- **Never run `hyprctl reload`** or restart services unless explicitly asked — this is a live desktop.
- `install.sh` writes symlinks to `/etc` and `/usr/local/bin`. Don't run it unless asked.

## Commit style

Conventional commits. Match the log:

```
feat: <short description>
fix: <short description>
chore: <short description>
docs: <short description>
refactor: <short description>
```

Use `/commit` to stage and commit without confirmation.

## Slash commands

| Command | Description |
|---|---|
| `/commit` | `git add -A`, inspect diff, commit with conventional message, then push. No confirmation. |
| `/udoc <file>` | Update a documentation file to reflect current codebase state. |

## Sensitive paths (never commit)

Defined in `.git/info/exclude`. Key entries:

- `opencode/commands/` — private slash commands (tracked separately)
- `opencode/node_modules/`, `opencode/bun.lock` — generated
- `gh/` — GitHub CLI credentials
- `mozilla/firefox/`, `vesktop/`, `discord/` — browser/client data
- `documentation/private` — private notes
- `tmux/plugins/` — vendored plugins

## AI preferences

- Primary agent: OpenCode (replaced Hermes).
- Preferred model: Claude Sonnet via GitHub Copilot.
- Former Hermes settings: 3 GB systemd cgroup memory cap for CLI sessions, aggressive context compression (threshold 0.3).

## Generated files (don't edit manually)

- `gtk-3.0/noctalia-colors.css`, `gtk-4.0/noctalia-colors.css` — written by `theme-sync.sh`
- `kitty/current-theme.conf` — written by `theme-sync.sh`
- `noctalia/colors.json` — written by Noctalia on scheme change

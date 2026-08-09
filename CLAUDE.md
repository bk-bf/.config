# CLAUDE.md

Instructions for this repo live in @AGENTS.md — read and follow them.

## What this repo is

Personal Arch/CachyOS dotfiles for a Hyprland + Noctalia desktop. Configuration only — no build system, no tests. Changes here affect a live system.

## Rules

- `install.sh` writes symlinks to `/etc` and `/usr/local/bin`. Don't run it unless asked.

## Sensitive paths (never commit)

Defined in `.git/info/exclude`. Key entries:

- `opencode/commands/` — private slash commands (tracked separately)
- `opencode/node_modules/`, `opencode/bun.lock` — generated
- `gh/` — GitHub CLI credentials
- `mozilla/firefox/`, `vesktop/`, `discord/` — browser/client data
- `documentation/private` — private notes
- `tmux/plugins/` — vendored plugins

## Generated files (don't edit manually)

- `gtk-3.0/noctalia-colors.css`, `gtk-4.0/noctalia-colors.css` — written by `theme-sync.sh`
- `kitty/current-theme.conf` — written by `theme-sync.sh`
- `noctalia/colors.json` — written by Noctalia on scheme change

# Agents

Instructions for AI agents (OpenCode, etc.) working in this repository.

## Working style (all projects)

- **No narration leakage into the product.** A deliverable — slides, docs, README, code comments, commit/PR text, UI copy — must only ever be about its subject, never about how or why you built it. Do not write "plain words first, code names pinned alongside", "this deck reads the code not the notes", "as requested, here is…", "I chose to structure it this way", or reading instructions for your own artifact. The construction of a thing and the content of a thing are two different layers; keep the construction layer in chat with me, out of the artifact. **Litmus test before you write anything into a deliverable: would a human doing this job actually put that sentence there?** A human designer never narrates their own technique onto the slide. If the answer is no, cut it.

- **Never work blind — see the output before calling it done.** For anything with observable output, and *especially* any UI/frontend work, set up a feedback loop **first** and check every change against it — not at the end. For web UI: a running dev server plus screenshots you actually view (headless `firefox --screenshot <url>` for static states; a Playwright script for states behind interaction — filled, loading, error), compared against the target look before declaring it finished. Check both light and dark. Before building tooling from scratch, look for an existing skill, CLI, or library that already does the job. Shipping UI I have never looked at — the exact failure that has wasted your time before — is what this rule exists to prevent. Mechanics: the `visual-dev` skill.

## Rules

- **Never commit secrets.** Check `.git/info/exclude` and `.gitignore` before staging anything new.
- **Always commit and push.** In this repo, commit every change and push it to origin without being asked.
- **Never create git worktrees** (`git worktree add`, EnterWorktree, or any auto-isolation) unless I explicitly ask for one. This is a dotfiles repo — the working copy *is* the live config, so edit files in place here. (Enforced for background jobs via `worktree.bgIsolation: "none"` in `.claude/settings.json`.)
- **Never install packages** or run `yay`/`pacman` unless explicitly asked.
- **Never run `hyprctl reload`** or restart services unless explicitly asked — this is a live desktop.

## Shell environment

- **Default to `mosh` for remote work** on `ubuntu` (`mosh ubuntu`). It
  survives laptop lid-close/suspend — roaming UDP keeps the session pinned, so
  it resumes on wake. **Do not use plain `ssh` for remote sessions unless I
  deliberately ask**, or unless the task genuinely needs something mosh can't do:
  scrollback-heavy reading, port/agent forwarding (`-L`/`-J`), or file transfer
  (`scp`/`rsync`). `ssh` is unaliased/plain. Trade-off to remember: mosh owns the
  alt screen and has **no scrollback** (the mouse wheel walks shell history
  instead of scrolling) — that's expected, reach for `ssh` when you need to read
  back. `mosh` is wrapped in `.aliases` to force `LC_ALL=C.UTF-8` (servers lack
  the laptop's `de_DE.UTF-8` locales, else mosh-server bails to US-ASCII).

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

## AI preferences

- Primary agent: OpenCode (replaced Hermes).
- Preferred model: Claude Sonnet via GitHub Copilot.

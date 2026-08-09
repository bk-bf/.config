# pacdim — pacman/yay output, recoloured by importance

**What:** a stdin→stdout filter that recolours pacman/yay output so routine chatter recedes and decisions, package names and real failures stand out.
**Files:** `bin/pacdim` (filter), `bin/pacdim-sample.txt` (demo transcript), `.aliases` (shell wiring), symlinked to `~/.local/bin/pacdim`.
**Not a TUI.** No menus, no alternate screen, no new commands to learn — `yay -Syu` stays `yay -Syu`.

---

## The one guarantee

**Text, layout and ordering are never touched. Only colour changes.**

Every line is passed through verbatim and wrapped in SGR codes. Nothing is reworded, reordered, summarised, collapsed or hidden — dimmed lines are still on screen and still greppable after the colour is stripped.

This is enforced mechanically, not by inspection: strip the SGR codes back out of the output and the result is byte-identical to the input.

```sh
pacdim < transcript.txt | sed 's/\x1b\[[0-9;]*m//g' | diff - transcript.txt
```

---

## Colour tiers

| Tier | Colour | xterm | Applied to |
|---|---|---|---|
| `ERR` | bright red, bold | 203 | Nothing was installed — act on it: `error:`, `==> ERROR:`, `Errors occurred`, `Aborting...`, `<pkg>: /path exists in filesystem` |
| `SOFT` | muted red | 131 | Failed, but the packages are fine — see *Error severity* below |
| `ASK` | orange, bold | 215 | Anything blocking on you: `[Y/n]` prompts, `[sudo] password` |
| `WARN` | amber | 179 | Real warnings |
| `SIZE` | pale gold, bold | 223 | Download / Installed / Net Upgrade sizes |
| `PKG` | cyan, bold | 117 | Package names |
| `VER` | green | 150 | Version numbers |
| `HDR` | near-white, bold | 252 | `::` section headers |
| `BODY` | light grey | 250 | Ordinary readable text (default) |
| `DIM` | grey | 242 | Routine chatter — see below |

All indices are ≥16, so they come from the fixed xterm-256 cube and are **not** remapped by the terminal colourscheme. What renders here renders the same everywhere.

### What gets dimmed

Hook steps (`(n/m) Updating the MIME type database...`), snapper pre/post snapshots and `==> root: NN`, limine-snapper-sync waits, keyring/integrity/disk-space checks, `:: Retrieving packages`, progress bars, `resolving dependencies`, `==> NOTE:`, `-> Cloning/Downloading`, `is up to date` lines, and directory-permission-diff warnings with their `filesystem: 755 package: 775` follow-ups.

### What stays bright

`(n/m) upgrading <pkg>` uses a transaction verb (`installing|upgrading|removing|reinstalling|downgrading`), which is what separates real work from hooks — the counter prefix and progress bar dim, the package name does not. Same for `==> Making package: <pkg>` during AUR builds, and `repo/pkg version` search hits.

---

## Error severity

Not every `error:` costs you the upgrade. Two tiers:

- **`ERR` (bright red)** — the transaction did not happen. Transaction commit failures, file conflicts, build failures.
- **`SOFT` (muted red)** — it failed, but the packages installed and work:
  - `error updating package install reason` — yay's post-install bookkeeping (`pacman -D --asexplicit`); the package is already installed
  - `is up to date -- skipping`
  - `sudo: timed out reading password` / `sudo: a password is required`

**The demotion list is an allowlist, not a heuristic.** `COSMETIC_ERR` in `bin/pacdim` names specific known-cosmetic strings; anything unrecognised falls through to `ERR` and stays loud. A novel error is never quietened by accident. Getting this wrong in the loud direction costs a glance — getting it wrong the other way hides a broken upgrade behind a colour that reads as "ignore me".

**Known limitation:** the `sudo:` demotion assumes the timeout hit *after* the transaction committed, which is the common case. A sudo timeout *mid*-transaction is genuinely fatal and is indistinguishable from the line alone. `SudoLoop` (below) makes both cases rare.

---

## Coverage

| Command | Filtered | How |
|---|---|---|
| `yay …` | yes | `yay()` shell function |
| `pacman -Q`, `-Ss`, `-Si` | yes | `pacman()` shell function |
| `sudo pacman …` | yes | `sudo()` wrapper, first-arg guard |
| `pac …` | yes | shorthand for `sudo pacman` |
| `sudo` anything else | **no — passthrough** | falls straight through to `command sudo` |

`sudo pacman` cannot be caught by the `pacman()` function: sudo resolves the binary itself, so the shell never sees a `pacman` word to expand. Hence the `sudo()` wrapper. It is deliberately narrow — it intervenes **only** when `$1` is literally `pacman`, so `sudo -i`, `sudo -u foo`, `sudo -S pacman` and everything else are handed to the real binary untouched.

### Escape hatches

| | Effect |
|---|---|
| `NO_PACDIM=1 yay …` | bypass entirely, run the bare command |
| `yay … \| grep foo` | auto-bypass — a non-tty stdout skips the filter, so scripts see clean text |
| `pacdim --demo` | preview the colouring against the bundled sample, installs nothing |

---

## Implementation notes

**A pty is kept attached.** The wrapper runs the real command under `script -qefc … /dev/null`, not as a bare pipe. Without a pty, pacman detects a non-tty and changes its own output — dropping colour, reflowing columns to a default width and altering progress rendering. `script` preserves the exact bare-command appearance, and `-e` propagates the child's exit status.

**Prompts flush on idle.** pacman writes `:: Proceed with installation? [Y/n]` with **no trailing newline**. A line-buffered filter would hold it until after you had already answered blind. `run()` selects on stdin with a 50 ms timeout and flushes any unterminated line when the stream goes quiet, so prompts appear before they block. A line already flushed as a partial is marked `mid_line` and its continuation is emitted uncoloured, so a colour rule is never applied twice to one line.

**`$pipestatus` is read on the line immediately after the pipeline.** In zsh it is overwritten by *any* intervening command — including `[`. Reading it inside an `if` returns the status of the test, not the pipeline, which silently makes every command look successful and breaks `yay … && …` chaining. The shell branch is therefore chosen *before* the pipeline runs, so the assignment always directly follows it.

**Broken pipes exit quietly.** `yay -Ss foo | head` closes the downstream early; `BrokenPipeError` is caught and exits 0 rather than dumping a traceback over pacman's output.

**Existing SGR is stripped before matching**, so yay's own colours cannot interfere with rule matching or leak through. OSC 8 hyperlinks (yay's clickable package URLs) are left intact.

**The `sudo` alias has to be unset around the function definition.** oh-my-zsh's `lib/correction.zsh` sets `alias sudo='nocorrect sudo'`, and zsh refuses to define a function whose name an alias already claims — it fails with `defining function based on alias 'sudo'` followed by `parse error near '()'`. That parse error aborts the rest of `.aliases`, so **every function defined below the failure point silently disappears**. The block therefore stashes the alias, unsets it, defines the function, and restores the alias verbatim; the alias then re-expands onto the function rather than the binary, so `nocorrect` still applies.

Because of this, `.aliases` must be tested in a shell that actually loads oh-my-zsh:

```sh
zsh -ic 'true'                                    # must print no parse errors
zsh -ic 'whence -w yay pacman sudo pac znvim'     # all must resolve
```

`zsh -c 'source ~/.config/.aliases'` is **not** a sufficient test — it skips `.zshrc`, so the colliding alias is absent and the collision cannot reproduce.

---

## Tuning

All rules live in `bin/pacdim`:

| To change | Edit |
|---|---|
| Any colour | the palette block at the top |
| What gets dimmed | `NOISE` |
| Which errors are demoted | `COSMETIC_ERR` |
| Which `(n/m)` lines count as real work | `TXN` |
| Everything else | the ordered `if` chain in `paint()` — **first match wins**, so more specific rules go higher |

After editing, re-check the guarantee:

```sh
pacdim < bin/pacdim-sample.txt | sed 's/\x1b\[[0-9;]*m//g' | diff - bin/pacdim-sample.txt && echo OK
pacdim --demo    # and look at it
```

---

## Related: the password-prompt fix

Separate from colouring, `~/.config/yay/config.json` has two settings that were previously off:

```json
"sudoloop": true,       // background keepalive refreshes the sudo ticket during long builds
"batchinstall": true,   // one pacman invocation for all packages, not one per package
```

With `sudoloop` off, a build outlasting sudo's default 5-minute `timestamp_timeout` re-prompts, and an unattended terminal hits `sudo: timed out reading password`. With `batchinstall` off, each package gets its own `sudo pacman` call and its own prompt. Both on: asked once, up front.

Optional complement — raise the sudo ticket lifetime system-wide:

```sh
echo 'Defaults timestamp_timeout=30' | sudo tee /etc/sudoers.d/timeout
visudo -c
```

Also worth knowing: the snapper hook output on every transaction comes from `snap-pac` + `limine-snapper-sync` (CachyOS defaults). pacdim dims it; removing it entirely means disabling those hooks, which also disables the pre/post rollback snapshots.

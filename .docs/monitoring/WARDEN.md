# warden — automatic triage for journal-notify

`journal-notify.sh` decides what breakage deserves a toast. **warden** answers
the next question — *can this be fixed* — by handing the incident to a headless
Claude Code session.

warden does **not** watch the journal. It hangs off `journal-notify.sh`'s
`notify()` choke point, so there is exactly one detector on this machine and one
notification policy.

- Script: `~/.config/bin/warden` (symlinked to `~/.local/bin/warden`)
- Config: `~/.config/warden/config.json`
- State: `~/.local/state/warden/` (`incidents/`, `reports/`, `state.json`)
- Hook: the `triage()` function in `~/.config/hypr/scripts/journal-notify.sh`
- No unit of its own — sessions run as transient `warden-session-<fp>.service`

## The chain

```
osd writes to the journal
  → journal-notify.sh   jq allowlist → rule + subject
  → should_notify()     escalating cooldown, coalescing, burst cap
  → notify-send         the toast you see
  → triage()            detached, failure-tolerant
  → warden triage       its own gate: rule, cooldown, daily cap
  → systemd-run         warden-session-<fp>.service in background.slice
  → claude -p           diagnosis, verdict, report
  → notify-send         the verdict
```

`triage()` is deliberately `setsid … &` with output discarded: triage is a bonus
on top of the toast and must never delay or break the notification path.

## Two changes this required in journal-notify.sh

**The osd rule missed the deletion guard.** The rule fired on
`blocked|ERROR|Could not|failed`, and the guard writes

```
claude-sessions-laptop: 63 deletions exceed the guard of 25 — sync skipped.
```

which contains none of them. The most actionable osd event on this machine only
ever surfaced as the generic `unitfail` toast, with the reason missing. Added
`sync skipped|exceed the guard`.

**Every user-unit event was attributed to `user@1000.service`.** `$unit` read
`._SYSTEMD_UNIT`, which for anything a `--user` unit runs is the *manager*, not
the unit — verified on a live entry:

```
_SYSTEMD_UNIT      = user@1000.service
_SYSTEMD_USER_UNIT = osd-claude-sessions-laptop.service
```

So every osd sync job shared one cooldown key and the toast named the wrong
thing. `$unit` now prefers `._SYSTEMD_USER_UNIT`. (The `unitfail` rule was
already immune — it parses the unit out of the message text, and its comment
explains exactly this trap.)

> `JQ_FILTER` is a single-quoted shell string. An apostrophe anywhere in those
> jq comments terminates it and the script dies with a bash syntax error a
> hundred lines further down. Check with `bash -n` after editing.

## warden's own gate

A toast is cheap; a session is not. On top of everything journal-notify already
filters:

| Gate | Default | Why |
|---|---|---|
| `triage_rules` | `unitfail, osd, diskfull, storm` | Only these are actionable |
| `cooldown_min` | 360 | One session per fingerprint per 6h |
| `max_sessions_per_day` | 6 | Hard budget |
| `ignore_subjects` | `warden*`, `app-*.scope`, … | Never chase these |

**`oom`, `pressure` and `coredump` are excluded on purpose.** There is nothing
to fix in a kill that already happened, and starting a Claude process *because
memory ran out* means competing for the RAM whose exhaustion triggered it — on a
16GB machine that turns a warning into a second casualty.

Fingerprints normalise digits (`re.sub(r"\d+", "#", …)`) because osd's deletion
count climbs on every retry — 38 → 56 → 63 over three minutes — and raw text
would make each retry a brand-new incident.

`state.json` is written under an `fcntl.flock` (`state_txn()`): journal-notify
can call `warden triage` several times in quick succession while a session
writes its own tally, and an unlocked load/save pair silently drops whichever
write landed in between.

## The session

Runs as a transient unit in `background.slice` with `OOMScoreAdjust=700`,
`MemoryMax=3G`, `CPUWeight=20` — the same posture as every other batch job here,
so it yields to the compositor and the browser
(see [../performance/CPU_PRIORITY.md](../performance/CPU_PRIORITY.md)).

It receives `systemctl cat` + `status` + the last 80 journal lines for the unit,
plus a per-rule `cwd` and `hint` from `context` in the config. The prompt carries
the standing limits from `~/.config/AGENTS.md` — no reboots, no `hyprctl
reload`, no package installs, no `git push`, no unrelated repos — and an explicit
licence to conclude *this needs a human* and change nothing.

It must end with:

```
WARDEN-VERDICT: fixed|no-change|needs-human — <one sentence>
```

**`fixed` is not taken on trust.** For a oneshot or timer-driven unit, warden
re-runs it and checks `systemctl --user is-failed`; a claimed fix that still
fails is reported as `still failing`. Long-lived services are never restarted to
"verify" — that is a good way to break something that was working.

> `claude -p --output-format json` does not always return one object; it can
> emit the whole stream as an array of events, where the answer is the last
> element with `type == "result"`. Treating that array as a dict loses the text
> *and* the cost and stores ~490KB of raw event dump as the report.
> `parse_session_output()` handles both shapes.

## Authority — `session_args`

Passed verbatim to `claude`. This is the only thing deciding what a session may
do.

| Value | Behaviour |
|---|---|
| `[]` (default) | Reads the system and writes a report. Describes the fix — exact files, exact edits — and applies nothing. |
| `["--dangerously-skip-permissions"]` | Applies fixes itself. |

When non-empty, every run is bracketed by a pair of snapper snapshots of
`/home`, recorded in the report:

```sh
undo <path> <snapshot-pre>
```

Unprivileged because the `home` snapper config sets `ALLOW_USERS` and
`SYNC_ACL`.

## Commands

```sh
warden status          # recent incidents, verdicts, today's budget
warden report <id>     # full session transcript
warden fix <id>        # run triage by hand (e.g. after the daily cap)
warden test            # inject a synthetic incident through the real path
warden doctor          # tooling, hook wiring, current authority level
```

`warden doctor` verifies the hook is actually present in `journal-notify.sh` —
the failure mode to watch for is an edit to that script silently dropping it.

## Verifying a change without waiting for breakage

Replay real journal history through the jq filter:

```sh
sed -n "/^JQ_FILTER='/,/^'$/p" ~/.config/hypr/scripts/journal-notify.sh \
  | sed "1s/^JQ_FILTER='//; \$d" > /tmp/f.jq
journalctl --user --since -24h -o json --no-pager | jq -r -f /tmp/f.jq
```

Each output line is `type \t rule \t subject \t body` — exactly what
`journal-notify` will act on. Measured on this machine: 6263 entries in 24h
produced 4 distinct incidents.

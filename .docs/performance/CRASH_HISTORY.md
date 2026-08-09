# Crash History — desktop session losses

Running log, newest first. **Machine:** Arch/CachyOS (`cachyos-x8664`), 15.9 GB RAM, zram-only
swap, `vm.swappiness=150` (CachyOS udev rule). **Compositor:** Hyprland via uwsm —
`wayland-wm@hyprland.desktop.service`.

| Date | What happened | Cause | Status |
|---|---|---|---|
| 2026-07-28 | `user@1000.service` SIGKILLed, whole session lost | **unidentified** | 🔴 open, auditd trap armed |
| 2026-07-23/24 | Three session teardowns | Kernel OOM under memory exhaustion | ✅ mitigated |

---

# 2026-07-28 — user manager SIGKILL (UNRESOLVED)

**The session did not crash — it was killed.**

```
01:11:07.503  user@1000.service: Main process exited, code=killed, status=9/KILL
01:11:07      coredump: PID 491143 "code", SIGTRAP, si_code=SI_KERNEL
01:11:08      user@1000.service: Failed with result 'signal'
01:11:46.938  Power key pressed short → Powering off        (user-initiated)
01:12:28      boot
```

The systemd **user manager's main process** took signal 9, so systemd tore down the entire
session — 259 processes. In the same instant VS Code (PID 491143) self-aborted: `SIGTRAP` with
`si_code=SI_KERNEL` is an `int3`, i.e. a Chromium internal CHECK failure, not an external kill.
The reboot 39 s later was the power button and shut down cleanly; the machine never panicked.

Two and a half minutes earlier the machine was **idle** — 82–94% idle, 9–26 W.

## Ruled out — do not re-investigate these

| Hypothesis | Evidence against |
|---|---|
| Kernel OOM | No `Out of memory` / `Killed process` anywhere in `journalctl -b -1 -k` |
| cgroup OOM | No `Memory cgroup out of memory`; `memory.events` shows no `oom_kill` |
| `systemd-oomd` | Its log is **empty** between start and stop — it killed nothing |
| `OOMPolicy` cascade | `user@1000.service` already had `OOMPolicy=continue` (systemd's default for user managers); never armed |
| oomd scope | `ManagedOOM` is `auto` everywhere except `app.slice`/`background.slice`; it could not target the session |
| Own scripts | Nothing in the dotfiles sends SIGKILL — `claude-reaper`, `dev-server-gc` and the session GC all use SIGTERM |
| Manual kill | Shell history for the window shows only an unrelated `kill <pid>` four minutes earlier |

The `12.8G memory peak / 14.8G swap peak` reported on the unit are **lifetime** figures over
4.5 days and do not pin anything to that night.

## Possible contribution — unproven

`MemoryHigh=6G` had been set on **`app.slice`** at 00:16 that night — the cgroup containing the
VS Code that aborted. It was mis-sized: chosen from a 1.7–2.0 GB idle reading, while `app.slice`
reaches **3.4 GB within minutes of a fresh boot** and far more under vitest workers (~300 MB
each) plus a headless test browser (167 MB across 12 processes). It was therefore reachable in
ordinary loaded use, not only under bloat as claimed when it was set.

`MemoryHigh` throttles rather than kills, but sustained reclaim pushes pages into zram, and zram
is compressed RAM — so filling it consumes physical RAM and tightens the very pressure it was
meant to relieve. A Chromium CHECK failure is a plausible downstream effect of allocation stalls.

Removed at 01:20 (commit `f06202c`) because it was the riskiest recent change with the least
demonstrated benefit — **not** because it was shown to be at fault.

> **Do not reintroduce a slice-wide `MemoryHigh` on `app.slice`.** The per-instance
> `app-code-.scope.d` → `MemoryHigh=9G` backstop is sufficient. See
> [MEMORY_PRESSURE.md](./MEMORY_PRESSURE.md).

## Monitoring

`auditd` armed with a `kill(sig=9)` rule to name the sender on recurrence:

```bash
sudo systemctl start auditd
sudo auditctl -a always,exit -F arch=b64 -S kill -F a1=9 -k sigkill
```

**Caveat:** as set up it was `active` but **not `enabled`**, and `auditctl` rules are not
persistent — the trap is lost on reboot. To make it survive, put the rule in
`/etc/audit/rules.d/` and `systemctl enable auditd`.

Read back after an event:

```bash
sudo ausearch -k sigkill -ts today | grep -B2 "systemd --user"
journalctl -b -1 | grep "code=killed, status=9/KILL"
```

---

# 2026-07-23/24 — three OOM teardowns

**Investigation basis:** kernel OOM task dumps, `systemctl` unit accounting, `systemd-oomd`
state, coredump list, Claude Code transcript sizes. No reboot since 2026-07-16, so all logs
since then were intact.

## The three events, side by side

| | **CRASH 1** | **CRASH 2** | **EVENT 3** |
|---|---|---|---|
| When | 2026-07-23 **23:21:34** | 2026-07-23 **23:57:54** | 2026-07-24 **05:57:19** |
| Gap from prior | — | +36 min | +6 h |
| Signature | kernel OOM-kill | kernel OOM-kill | **clean exit (OnSuccess)** |
| systemd result | `Failed 'oom-kill'` | `Failed 'oom-kill'` | `OnSuccess` (exit 0) |
| Victim | pid 2928639 `2.1.218` (Claude Code) | pid 3000981 `2.1.218` (Claude Code) | none |
| Victim anon-rss | 4.07 GB | 5.83 GB | — |
| Victim total-vm | 7.62 GB | 14.96 GB | — |
| oom_score_adj | 200 | 200 | — |
| Free swap at kill | **108 kB** (~0) | **28 kB** (~0) | n/a |
| Session RAM peak | 9.2 GB | 10.8 GB | **5.5 GB** |
| Session swap peak | 11.4 GB | 11.5 GB | **3.1 GB** |
| Session lifespan | **1d 23h 37m** | **36 min** | 5h 59m |
| Outcome | bounced to SDDM | bounced to SDDM | session ended cleanly |

---

## What `2.1.218` is

The OOM victim's process name (`comm`) is `2.1.218` — **this is Claude Code**, not a project/test process. The name comes from its versioned binary path `~/.local/share/claude/versions/2.1.218`. At any given time 10+ processes carry this name (main session, `bg-pty-host`, `bg-spare` helpers). An earlier note that called this "the game version" or a vitest worker was wrong.

---

## Root cause

A single long-lived **Claude Code (node) process** grows its private heap until it, plus everything else resident, exhausts **both** 15.9 GB RAM **and** 15.9 GB swap. `swappiness=150` makes the kernel swap aggressively, so swap fills to ~0 (108 kB, then 28 kB free at the two kills) before the global OOM killer fires. The killer picks the largest badness score — always Claude Code, by a wide margin (Hyprland itself was ~16 MB in the dumps) — and kills it.

The desktop teardown was a **second, separable failure**: with systemd's default `OOMPolicy=stop`, killing any process inside the compositor's cgroup stopped the whole `wayland-wm@hyprland` unit, ending the Hyprland session and bouncing to SDDM. So one runaway process killed the entire desktop.

**Crash 1 vs Crash 2** are the same failure 36 min apart. Crash 1 was a ~2-day marathon session whose heap crept to 4 GB. Crash 2 was the *restart* after Crash 1: on resume the heap re-ballooned to 5.8 GB within 36 minutes on a box whose swap had not recovered, and it died again — bigger (14.96 GB total-vm).

**Event 3 is not the same class and arguably not a crash.** RAM peaked at 5.5 GB — nowhere near the limit — swap only 3.1 GB, no kernel OOM in the window, and the unit exited cleanly (`OnSuccess`, code 0) after a 6-hour session. Something quit Hyprland normally. The dead session log (`/run/user/1000/hypr/…_1784843889_…/hyprland.log`, 14 MB, ends 05:57:19) contains **no exit/quit/logout dispatch and zero keyboard key events** — it just stops mid-stream on a wall of touchpad palm-detection lines. So *why* it exited is still open, but it is definitively **not** an OOM and shares no mechanism with Crashes 1 and 2.

---

## Hypotheses tested and ruled out

**Vitest fork-army (~21 node workers spiking memory).** Refuted as the cause of the crashes:
- Both OOM victims were Claude Code, not node/vitest.
- Neither OOM task table contained a node fork army — the only node process present was a 10 MB boot daemon (`node-MainThread`). ~21 worker processes each loading worldgen+WASM would each carry their own RSS row; none exist.
- `systemd-oomd` is **inactive** — zero cgroup-level kills, so nothing was reaped without a kernel task dump.
- No node/vitest/Fantasia coredumps, ever.
- Even the worst measured vitest peak (~3 GB across 22 forks) can't OOM a 15 GB box next to a 14 GB Claude Code.
- *The vitest fork cap is still worth keeping as hygiene — it just wasn't the trigger.*

**Test output buffered into Claude Code's heap ("the bridge").** Refuted:
- Claude Code persists tool results to the session `.jsonl`. The transcripts live at each crash were 8.7 MB (Crash 1) and 2.4 MB (Crash 2); the largest transcript anywhere is 73 MB.
- Heap at Crash 2 was 5.8 GB — ~670× the live transcript. Node overhead is 2–4×, not 670×. The memory is not retained test data; it is heap accumulation/leak in the long-running process.

**Memory accounting following the process tree** ("Claude Code ran the tests, so their memory counts as its"). Refuted by mechanism and evidence:
- Linux accounts memory per address space; a parent's RSS never absorbs a child's. Test workers would appear as their own rows (they don't).
- The victim's memory was 5.83 GB `anon-rss` of 5.83 GB total (file-rss 2.4 MB, shmem 0) — ~100% its own private JS heap, not shared/child memory.

---

## Fixes

**Applied (2026-07-24 00:10:59) — desktop survives the kill.**
`~/.config/systemd/user/wayland-wm@.service.d/oom.conf` sets `OOMPolicy=continue`. The kernel kills the one runaway process; the compositor unit keeps running instead of bouncing to SDDM. Confirmed live in the current session (started 05:57:28, after the drop-in). This is why no teardown has recurred. The two crashes predate this file.

**Not yet applied — prevent the pre-kill freeze (recommended).**
`OOMPolicy=continue` saves the desktop *after* the kill, but the swap-thrash *before* the kill still freezes the machine for seconds-to-minutes. Cap Claude Code / VS Code in its own scope so it is throttled or killed *before* dragging the whole box into swap-death:
- Soft: `MemoryHigh=` on VS Code's transient scope (`app-code-.scope.d/`) — applies reclaim pressure, no hard kill.
- Hard: `MemoryMax=` — kills the scope at the ceiling (can lose editor state; use a generous value).
- Alternative: enable `systemd-oomd` with per-slice PSI/swap thresholds on `app.slice`.

**Keep — vitest fork cap.** Capped to 3 forks (env-overridable). Good hygiene; not the crash cause.

**Consider — swappiness.** `vm.swappiness=150` drives the machine deep into swap before OOM, which is what makes the freeze so long. A lower value (e.g. 60–100) would OOM-kill sooner and thrash less. This is a CachyOS udev-rule default; overriding it is a system-level change.

---

## Open thread (separate investigation)

Event 3's clean 05:57:19 exit is unexplained but not memory-related. Originally framed as part of a keyboard-phantom-keypress → touchpad-freeze → crash chain; the log shows no keyboard events and no exit dispatch, so that chain is not supported by evidence. Tracked separately from this crash history.

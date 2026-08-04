#!/usr/bin/env bash
# dev-server-gc: reap abandoned node/vite dev servers.
#
# A dev server started with `pnpm dev` in a terminal keeps running after the
# terminal closes -- it is reparented to the systemd user manager and listens
# forever. The next `pnpm dev` finds the port taken and picks the next one, so
# they accumulate: twelve dashboard/web servers on ports 5201-5310 were found on
# 2026-07-27, holding ~3 GB between them.
#
# A server is reaped only when ALL of these hold:
#   1. it holds a LISTEN socket (it is a server, not a build step)
#   2. its process tree is rooted at the systemd user manager -- i.e. the shell
#      that launched it is gone. A server started from a terminal you still have
#      open, or from VS Code, is never a candidate.
#   3. it is NOT a managed systemd unit. A service's parent is also the user
#      manager, so criterion 2 alone cannot tell "orphaned" from "supervised" --
#      the cgroup can: a unit lives in app.slice/<name>.service, while an
#      orphaned dev server keeps the cgroup of the terminal that launched it.
#      (Learned the hard way: the first run killed codegraph.service, which
#      systemd restarted three seconds later.)
#   4. it has ZERO established connections -- nothing is using it
#   5. it is older than MIN_AGE
#
# Criterion 4 protects a server you are actively hitting in a browser;
# criterion 2 protects one you are about to hit; criterion 3 protects the ones
# you deliberately supervise.
#
# Usage: dev-server-gc.sh [--dry-run]
set -euo pipefail

export DEV_SERVER_GC_MIN_AGE=${DEV_SERVER_GC_MIN_AGE:-3600}   # seconds
export DEV_SERVER_GC_DRY=0
[[ "${1:-}" == "--dry-run" ]] && export DEV_SERVER_GC_DRY=1

python3 - <<'PYEOF'
import os, re, signal, subprocess, sys, glob

dry     = os.environ["DEV_SERVER_GC_DRY"] == "1"
min_age = int(os.environ["DEV_SERVER_GC_MIN_AGE"])
uid     = os.getuid()

def read(pid, f):
    try:
        return open("/proc/%s/%s" % (pid, f)).read()
    except Exception:
        return ""

def ppid_of(pid):
    for line in read(pid, "status").splitlines():
        if line.startswith("PPid:"):
            return int(line.split()[1])
    return None

def cmdline(pid):
    return read(pid, "cmdline").replace("\0", " ").strip()

def comm(pid):
    return read(pid, "comm").strip()

def mem_kb(pid):
    r = s = 0
    for line in read(pid, "status").splitlines():
        if line.startswith("VmRSS:"):
            r = int(line.split()[1])
        elif line.startswith("VmSwap:"):
            s = int(line.split()[1])
    return r + s

# Orphaned user processes are reparented to the systemd *user* manager, not PID 1.
manager_pid = None
for p in glob.glob("/proc/[0-9]*"):
    pid = p.split("/")[-1]
    try:
        if comm(pid) == "systemd" and ppid_of(pid) == 1 and os.stat(p).st_uid == uid:
            manager_pid = int(pid)
            break
    except Exception:
        continue
if manager_pid is None:
    print("cannot locate the systemd user manager; refusing to act")
    sys.exit(0)

clk    = os.sysconf("SC_CLK_TCK")
uptime = float(open("/proc/uptime").read().split()[0])

def age_of(pid):
    st = read(pid, "stat")
    if not st:
        return 0.0
    return uptime - int(st[st.rindex(")") + 2:].split()[19]) / clk

listen, estab = {}, {}
out = subprocess.run(["ss", "-tanp"], capture_output=True, text=True).stdout
for line in out.splitlines()[1:]:
    m = re.search(r"pid=(\d+)", line)
    if not m:
        continue
    fields = line.split()
    pid, state, local = int(m.group(1)), fields[0], fields[3]
    if state == "LISTEN":
        listen.setdefault(pid, []).append(local)
    elif state == "ESTAB":
        estab[pid] = estab.get(pid, 0) + 1

def children(pid):
    return [int(x) for x in read(pid, "task/%d/children" % pid).split()]

def subtree(pid, acc=None):
    acc = [] if acc is None else acc
    acc.append(pid)
    for c in children(pid):
        subtree(c, acc)
    return acc

def cwd_name(pid):
    try:
        return os.path.basename(os.readlink("/proc/%d/cwd" % pid))
    except Exception:
        return "?"

reaped, seen_roots = 0, set()
for pid, ports in sorted(listen.items()):
    cl = cmdline(pid)
    if "node" not in cl and "vite" not in cl:
        continue
    portstr = ",".join(ports)
    live = estab.get(pid, 0)
    if live:
        print("keep   %-26s %d live connection(s)" % (portstr, live))
        continue

    # A managed unit is supervised, not abandoned -- and its parent is the user
    # manager too, so only the cgroup distinguishes it.
    unit = ""
    for line in read(pid, "cgroup").splitlines():
        path = line.rsplit(":", 1)[-1]
        if path.endswith(".service"):
            unit = path.rsplit("/", 1)[-1]
    if unit:
        print("keep   %-26s managed by %s" % (portstr, unit))
        continue

    root = pid
    while True:
        pp = ppid_of(root)
        if pp is None or pp in (0, 1):
            root = None
            break
        if pp == manager_pid:
            break
        root = pp
    if root is None:
        continue

    rc = comm(root)
    if rc not in ("node", "pnpm", "npm", "sh", "bash", "zsh") and "node" not in cmdline(root):
        print("keep   %-26s tree root is %r, not an orphaned dev server" % (portstr, rc))
        continue

    hours = age_of(root) / 3600
    if age_of(root) < min_age:
        print("keep   %-26s only %.1f h old" % (portstr, hours))
        continue
    if root in seen_roots:
        continue
    seen_roots.add(root)

    tree = subtree(root)
    mb = sum(mem_kb(p) for p in tree) / 1024
    label = "%s (%s)" % (portstr, cwd_name(pid))
    if dry:
        print("would reap %-28s %d procs, %.0f MB, age %.1f h" % (label, len(tree), mb, hours))
        continue
    for p in reversed(tree):
        try:
            os.kill(p, signal.SIGTERM)
        except ProcessLookupError:
            pass
        except PermissionError as e:
            print("  cannot kill %d: %s" % (p, e), file=sys.stderr)
    print("reaped %-28s %d procs, %.0f MB freed" % (label, len(tree), mb))
    reaped += 1

# ── Second pass: headless browsers orphaned from agent scratchpads ───────────
# Different shape from a dev server, so the loop above cannot catch it: a
# profiler/test browser holds no LISTEN socket, so it never enters `listen`.
#
# Observed 2026-07-28: `firefox --headless --marionette --profile ./ffprof3`,
# launched by @firefox-devtools/profiler-cli from a Claude Code session, was
# reparented to the user manager when that session moved on. It sat for 16
# minutes at 14% CPU holding 7 renderD128 fds and 167 MB across 12 content
# processes -- with nothing driving it. GPU contention matters here beyond the
# CPU cost: cgroup weights cannot arbitrate the DRM render engine, so an
# orphaned browser competes with the compositor at full strength no matter how
# it is throttled, and shows up as dropped video frames.
#
# Reaped only when ALL hold:
#   1. it is a browser running headless (never a browser you can see)
#   2. its cwd is under an agent scratchpad -- /tmp/claude-<uid>/
#   3. it is reparented to the systemd user manager, i.e. its launcher is gone
#   4. it is not a managed systemd unit
#   5. nothing is connected to it (no ESTAB -- no live marionette/CDP client)
#   6. it is older than BROWSER_MIN_AGE (shorter than the dev-server threshold:
#      these are ephemeral by nature, and one costs more while it lingers)
browser_min_age = int(os.environ.get("DEV_SERVER_GC_BROWSER_MIN_AGE", "900"))
scratch_prefix  = "/tmp/claude-%d/" % uid
BROWSERS        = ("firefox", "chrome", "chromium", "zen-bin", "helium")

def cwd_of(pid):
    try:
        return os.readlink("/proc/%s/cwd" % pid)
    except Exception:
        return ""

browsers_reaped = 0
for p in sorted(glob.glob("/proc/[0-9]*"), key=lambda x: int(x.split("/")[-1])):
    pid = int(p.split("/")[-1])
    try:
        if os.stat(p).st_uid != uid:
            continue
    except Exception:
        continue

    cl = cmdline(pid)
    if "--headless" not in cl:
        continue
    if not any(b in comm(pid) or b in cl.split(" ")[0] for b in BROWSERS):
        continue
    # only the top-level browser process, not its -contentproc children
    if "-contentproc" in cl or "crashhelper" in cl:
        continue

    cwd = cwd_of(pid)
    if not cwd.startswith(scratch_prefix):
        continue
    if ppid_of(pid) != manager_pid:
        print("keep   headless browser %d -- still has a live parent" % pid)
        continue

    unit = ""
    for line in read(pid, "cgroup").splitlines():
        path = line.rsplit(":", 1)[-1]
        if path.endswith(".service"):
            unit = path.rsplit("/", 1)[-1]
    if unit:
        print("keep   headless browser %d -- managed by %s" % (pid, unit))
        continue

    tree = subtree(pid)
    live = sum(estab.get(t, 0) for t in tree)
    if live:
        print("keep   headless browser %d -- %d live connection(s)" % (pid, live))
        continue

    age = age_of(pid)
    if age < browser_min_age:
        print("keep   headless browser %d -- only %.0f min old" % (pid, age / 60))
        continue

    mb = sum(mem_kb(t) for t in tree) / 1024
    label = "%s (%s)" % (comm(pid), os.path.basename(cwd) or "scratchpad")
    if dry:
        print("would reap %-28s %d procs, %.0f MB, age %.0f min" % (label, len(tree), mb, age / 60))
        continue
    for t in reversed(tree):
        try:
            os.kill(t, signal.SIGTERM)
        except ProcessLookupError:
            pass
        except PermissionError as e:
            print("  cannot kill %d: %s" % (t, e), file=sys.stderr)
    print("reaped %-28s %d procs, %.0f MB freed" % (label, len(tree), mb))
    browsers_reaped += 1

if not dry:
    print("dev-server-gc: %d abandoned dev server(s), %d orphaned headless browser(s) reaped"
          % (reaped, browsers_reaped))
PYEOF

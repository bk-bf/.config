#!/usr/bin/env python3
"""Snapshot kitty windows (workspace + cwd + foreground command) for reboot
session restore. Companion to session-restore.sh / session-window.sh.

State comes from `hyprctl clients` (which workspace each window is on) and /proc
(the foreground process's cwd and argv) — no kitty remote control required, so
every running kitty is captured regardless of its listen_on socket. hyprflow is
told to ignore kitty (hyprflow/config.toml) so the two never both relaunch it.

Run periodically via the kitty-session-save.timer systemd user unit.
"""
import json
import os
import shlex
import subprocess
import sys
import tempfile
import time

STATE_DIR = os.path.expanduser("~/.local/share/kitty-session")
STATE_FILE = os.path.join(STATE_DIR, "session.json")
SHELLS = {"sh", "bash", "zsh", "fish", "dash", "-sh", "-bash", "-zsh", "-fish"}


def read_bytes(path):
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except OSError:
        return None


def build_process_tables():
    """Return (children_by_ppid, comm_by_pid) from a single /proc scan."""
    kids, comm = {}, {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        data = read_bytes(f"/proc/{entry}/stat")
        if not data:
            continue
        s = data.decode("latin1")
        rp = s.rfind(")")
        pid = int(entry)
        comm[pid] = s[s.find("(") + 1:rp]
        after = s[rp + 2:].split()
        kids.setdefault(int(after[1]), []).append(pid)  # after[1] = ppid
    return kids, comm


def stat_after(pid):
    data = read_bytes(f"/proc/{pid}/stat")
    if not data:
        return None
    s = data.decode("latin1")
    return s[s.rfind(")") + 2:].split()


def cmdline(pid):
    data = read_bytes(f"/proc/{pid}/cmdline")
    if not data:
        return []
    return [p.decode("utf-8", "replace") for p in data.split(b"\0") if p]


def cwd_of(pid):
    try:
        return os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        return None


def foreground(kpid, kids, comm):
    """Foreground process of the kitty window: kitty's child is the shell, and
    the controlling tty's tpgid names the foreground process-group leader."""
    shell = next((c for c in kids.get(kpid, []) if comm.get(c) in SHELLS), None)
    if shell is None:
        childs = kids.get(kpid, [])
        shell = childs[0] if childs else kpid
    after = stat_after(shell)
    tpgid = int(after[5]) if after else -1  # field 8 (0-based 5 after comm) = tpgid
    fg = tpgid if tpgid > 0 else shell
    is_shell = fg == shell or comm.get(fg) in SHELLS
    return fg, shell, is_shell


def main():
    try:
        clients = json.loads(subprocess.check_output(["hyprctl", "clients", "-j"]))
    except (OSError, subprocess.CalledProcessError, ValueError):
        return 1

    kids, comm = build_process_tables()
    windows = []
    for c in clients:
        if "kitty" not in (c.get("class") or "").lower():
            continue
        ws = (c.get("workspace") or {}).get("id")
        if not isinstance(ws, int) or ws < 1:
            continue  # skip special / scratchpad workspaces
        kpid = c.get("pid")
        if not kpid:
            continue
        fg, shell, is_shell = foreground(kpid, kids, comm)
        windows.append({
            "workspace": ws,
            "cwd": cwd_of(fg) or cwd_of(shell) or os.path.expanduser("~"),
            "cmd": "" if is_shell else shlex.join(cmdline(fg)),
            "title": c.get("title", ""),
        })

    windows.sort(key=lambda w: (w["workspace"], w["title"]))
    os.makedirs(STATE_DIR, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=STATE_DIR, prefix=".session.", suffix=".json")
    with os.fdopen(fd, "w") as fh:
        json.dump({"saved_at": int(time.time()), "windows": windows}, fh, indent=2)
    os.replace(tmp, STATE_FILE)
    return 0


if __name__ == "__main__":
    sys.exit(main())

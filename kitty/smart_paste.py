
import json
import os
import subprocess
import time
from typing import Any

from kittens.tui.handler import result_handler
from kitty.fast_data_types import add_timer

CLIP_PUSH = os.path.expanduser('~/.config/bin/clip-push')
SSH_CONFIG = os.path.expanduser('~/.ssh/config')
HERDR = os.path.expanduser('~/.local/bin/herdr')
UPLOAD_TIMEOUT = 25.0

SSH_FLAGS_WITH_VALUE = frozenset('bcDEeFIiJLlmOopQRSWw')


def _ssh_aliases() -> dict[str, str]:
    aliases: dict[str, str] = {}
    host = None
    try:
        with open(SSH_CONFIG) as f:
            for line in f:
                parts = line.split('#', 1)[0].replace('=', ' ').split()
                if len(parts) < 2:
                    continue
                if parts[0].lower() == 'host':
                    host = parts[1]
                elif parts[0].lower() == 'hostname' and host and '*' not in host:
                    aliases.setdefault(parts[1], host)
    except OSError:
        pass
    return aliases


def _hostname_from_ssh(argv: list[str]) -> str | None:
    skip = False
    for arg in argv[1:]:
        if skip:
            skip = False
            continue
        if arg.startswith('-'):
            if len(arg) == 2 and arg[1] in SSH_FLAGS_WITH_VALUE:
                skip = True
            continue
        return arg
    return None


def _host_from_argv(argv: list[str]) -> str | None:
    if not argv:
        return None
    prog = os.path.basename(argv[0])
    if prog == 'mosh-client' and len(argv) >= 3:
        return _ssh_aliases().get(argv[-2], argv[-2])
    if prog == 'ssh':
        return _hostname_from_ssh(argv)
    return None


def _cmdline(pid: int) -> list[str]:
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return [a.decode('utf-8', 'replace') for a in f.read().split(b'\0') if a]
    except OSError:
        return []


def _children_by_parent() -> dict[int, list[int]]:
    kids: dict[int, list[int]] = {}
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/stat', 'rb') as f:
                stat = f.read()
        except OSError:
            continue
        end = stat.rfind(b')')
        fields = stat[end + 2:].split()
        if len(fields) < 2:
            continue
        try:
            kids.setdefault(int(fields[1]), []).append(int(entry))
        except ValueError:
            continue
    return kids


def _descendants(root: int) -> list[int]:
    kids = _children_by_parent()
    out: list[int] = []
    seen: set[int] = set()
    stack = [root]
    while stack:
        pid = stack.pop()
        if pid in seen:
            continue
        seen.add(pid)
        out.append(pid)
        stack.extend(kids.get(pid, ()))
    return out


def _herdr_focused_host() -> tuple[bool, str | None]:
    try:
        proc = subprocess.run(
            [HERDR, 'pane', 'process-info', '--current'],
            capture_output=True, text=True, timeout=2,
        )
    except Exception:
        return False, None
    if proc.returncode != 0:
        return False, None
    try:
        info = json.loads(proc.stdout)['result']['process_info']
        procs = info['foreground_processes']
    except Exception:
        return False, None
    for p in procs:
        host = _host_from_argv(p.get('argv') or [])
        if host:
            return True, host
    return True, None


def _remote_host(w: Any) -> str | None:
    try:
        procs = w.child.foreground_processes
    except Exception:
        procs = []
    for proc in procs:
        host = _host_from_argv(proc.get('cmdline') or [])
        if host:
            return host

    try:
        pid = w.child.pid
    except Exception:
        return None
    if not pid:
        return None

    below = _descendants(pid)
    cmdlines = {p: _cmdline(p) for p in below}

    if any(argv and os.path.basename(argv[0]) == 'herdr' for argv in cmdlines.values()):
        answered, host = _herdr_focused_host()
        if answered:
            return host

    hosts = {h for argv in cmdlines.values() if (h := _host_from_argv(argv))}
    return hosts.pop() if len(hosts) == 1 else None


def _upload_then_type(w: Any, boss: Any, host: str) -> None:
    try:
        proc = subprocess.Popen(
            [CLIP_PUSH, '--host', host],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
    except OSError as err:
        _report(boss, f'Could not run clip-push: {err}')
        return

    deadline = time.monotonic() + UPLOAD_TIMEOUT

    def poll(timer_id: int) -> None:
        if proc.poll() is None:
            if time.monotonic() < deadline:
                add_timer(poll, 0.1, False)
            else:
                proc.kill()
                _report(boss, f'Timed out sending the clipboard image to {host}.')
            return
        out, err = proc.communicate()
        path = out.strip()
        if proc.returncode == 0 and path:
            if not getattr(w, 'destroyed', False):
                w.write_to_child(path + ' ')
        else:
            _report(boss, err.strip() or f'clip-push failed for {host}.')

    add_timer(poll, 0.1, False)


def _report(boss: Any, message: str) -> None:
    try:
        boss.show_error('Paste', message)
    except Exception:
        pass


def main(args: list[str]) -> str:
    raise SystemExit('smart_paste runs without a UI')


@result_handler(no_ui=True)
def handle_result(args: list[str], answer: str, target_window_id: int, boss: Any) -> None:
    w = boss.window_for_dispatch or boss.active_window
    if w is None:
        return
    if w.send_paste_event():
        return

    try:
        mimes = boss.clipboard.get_available_mime_types_for_paste()
    except Exception:
        mimes = ()

    if any(m.startswith('image/') for m in mimes):
        host = _remote_host(w)
        if host:
            _upload_then_type(w, boss, host)
        else:
            w.write_to_child('\x16')
        return

    text = boss.clipboard.get_text()
    if text:
        w.paste_with_actions(text)

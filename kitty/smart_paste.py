"""Paste that follows the clipboard rather than the key.

Kitty's built-in paste is text-only, so an image on the clipboard arrives as
nothing. Programs that read the clipboard themselves — Claude Code, which
attaches images and pastes text from the same Ctrl+V — need the keypress
instead. This picks per paste: image on the clipboard forwards a literal
Ctrl+V (0x16) to the running program, anything else pastes text as usual.
"""

from typing import Any

from kittens.tui.handler import result_handler


def main(args: list[str]) -> str:
    raise SystemExit('smart_paste runs without a UI')


@result_handler(no_ui=True)
def handle_result(args: list[str], answer: str, target_window_id: int, boss: Any) -> None:
    w = boss.window_for_dispatch or boss.active_window
    if w is None:
        return
    # A program using the clipboard-read protocol handles its own paste.
    if w.send_paste_event():
        return

    try:
        mimes = boss.clipboard.get_available_mime_types_for_paste()
    except Exception:
        mimes = ()

    if any(m.startswith('image/') for m in mimes):
        w.write_to_child('\x16')
        return

    text = boss.clipboard.get_text()
    if text:
        w.paste_with_actions(text)

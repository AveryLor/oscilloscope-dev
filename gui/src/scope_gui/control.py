"""Host -> ESP32 control commands: formats the six SET_* lines documented in
docs/CONTROL.md and matched by esp32/main/cmd_parse.c, plus a small debounce
helper so a dragged slider doesn't flood the link with one line per pixel.

The fmt_set_*() functions validate their own ranges before formatting, ahead
of the firmware doing the same -- a UI bug should raise here, in Python,
rather than silently produce a line the firmware drops.
"""

from __future__ import annotations

from typing import Callable

from PySide6.QtCore import QTimer


def _check_range(name: str, value: int, lo: int, hi: int) -> None:
    if not (lo <= value <= hi):
        raise ValueError(f"{name} must be in [{lo}, {hi}], got {value}")


def fmt_set_timebase(dec_factor: int) -> str:
    _check_range("dec_factor", dec_factor, 0, 0xFFFF)
    return f"SET_TIMEBASE {dec_factor}"


def fmt_set_hoffset(pre_count: int, post_count: int) -> str:
    _check_range("pre_count", pre_count, 0, 0xFFFF)
    _check_range("post_count", post_count, 0, 0xFFFF)
    return f"SET_HOFFSET {pre_count} {post_count}"


def fmt_set_trigger(level: int, src: int, edge: int, hyst: int) -> str:
    _check_range("level", level, 0, 1023)
    _check_range("src", src, 0, 2)
    _check_range("edge", edge, 0, 2)
    _check_range("hyst", hyst, 0, 255)
    return f"SET_TRIGGER {level} {src} {edge} {hyst}"


def fmt_set_vertical(atten: int, preamp: int, lmh_atten: int, offset_code: int) -> str:
    _check_range("atten", atten, 0, 2)
    _check_range("preamp", preamp, 0, 1)
    _check_range("lmh_atten", lmh_atten, 0, 10)
    _check_range("offset_code", offset_code, 0, 4095)
    return f"SET_VERTICAL {atten} {preamp} {lmh_atten} {offset_code}"


def fmt_set_coupling(dc_coupled: bool) -> str:
    return f"SET_COUPLING {1 if dc_coupled else 0}"


def fmt_set_term(term_50r: bool) -> str:
    return f"SET_TERM {1 if term_50r else 0}"


class DebouncedSender:
    """Coalesces rapid submit() calls into one send() after `delay_ms` of
    quiet -- so a slider drag sends a line per settled position rather than
    per pixel of motion, while still guaranteeing the final value goes out
    once the drag stops."""

    def __init__(self, send: Callable[[str], bool], delay_ms: int = 80) -> None:
        self._send = send
        self._pending: str | None = None
        self._timer = QTimer()
        self._timer.setSingleShot(True)
        self._timer.setInterval(delay_ms)
        self._timer.timeout.connect(self._flush)

    def submit(self, line: str) -> None:
        self._pending = line
        self._timer.start()

    def _flush(self) -> None:
        if self._pending is not None:
            self._send(self._pending)
            self._pending = None

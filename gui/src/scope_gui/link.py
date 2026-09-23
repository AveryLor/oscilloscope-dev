"""Serial link: a background thread owns the port, resyncs the incoming
sample stream on the magic word, and a locked write path sends control
commands (see docs/CONTROL.md) the other direction on the same connection."""

from __future__ import annotations

import queue
import threading
from dataclasses import dataclass

import serial
import serial.tools.list_ports

from . import frame as frame_mod
from .frame import HDR_BYTES, MAGIC, Frame, ParseError

DEFAULT_BAUD = 921_600


@dataclass
class FrameEvent:
    frame: Frame


@dataclass
class BadEvent:
    reason: str


@dataclass
class DisconnectedEvent:
    reason: str


Event = FrameEvent | BadEvent | DisconnectedEvent


class Demux:
    """Pulls frames out of a byte stream that may start mid-frame, carry stray
    log text, or split a frame across reads. Kept separate from the serial
    port so the framing rules can be unit tested against recorded bytes."""

    def __init__(self) -> None:
        self._buf = bytearray()
        self._magic = MAGIC.to_bytes(4, "little")

    def push(self, data: bytes) -> None:
        self._buf.extend(data)

    def next_frame(self) -> Frame | str | None:
        """Returns the next Frame, a string describing a frame that failed to
        validate, or None if more bytes are needed. Call repeatedly until it
        returns None."""
        magic = self._magic
        while True:
            idx = self._buf.find(magic)
            if idx == -1:
                # A magic word may straddle two reads, so keep a short tail.
                keep = max(0, len(self._buf) - (len(magic) - 1))
                del self._buf[:keep]
                return None
            if idx > 0:
                del self._buf[:idx]

            if len(self._buf) < HDR_BYTES:
                return None

            try:
                n_cols = frame_mod.cols_of(self._buf)
            except ParseError as exc:
                # Not a real frame start after all; step over this magic word
                # and keep scanning.
                del self._buf[:len(magic)]
                return str(exc)

            total = HDR_BYTES + n_cols * 4 + 4
            if len(self._buf) < total:
                return None  # wait for the rest

            try:
                parsed = frame_mod.parse(bytes(self._buf[:total]))
            except ParseError as exc:
                del self._buf[:len(magic)]
                return str(exc)

            del self._buf[:total]
            return parsed


class Link:
    """Owns an open serial port: a reader thread feeds a Demux and posts
    events to a bounded queue (depth 2, so a UI that falls behind drops old
    captures rather than queuing them -- only the newest is worth drawing),
    and send() writes control command lines the other direction."""

    def __init__(self, port: str, baud: int = DEFAULT_BAUD, timeout: float = 0.2) -> None:
        self._serial = serial.Serial(port, baudrate=baud, timeout=timeout)
        self._write_lock = threading.Lock()
        self._stop = threading.Event()
        self.events: queue.Queue[Event] = queue.Queue(maxsize=2)
        self._thread = threading.Thread(target=self._read_loop, daemon=True)
        self._thread.start()

    def send(self, line: str) -> bool:
        """Writes one control command line (see docs/CONTROL.md), appending
        the newline terminator. Returns False and posts a DisconnectedEvent if
        the write fails; the caller does not need to handle the failure
        itself, since the UI already reacts to DisconnectedEvent."""
        try:
            with self._write_lock:
                self._serial.write((line + "\n").encode("ascii"))
            return True
        except serial.SerialException as exc:
            self._push(DisconnectedEvent(str(exc)))
            return False

    def close(self) -> None:
        self._stop.set()
        try:
            self._serial.close()
        except serial.SerialException:
            pass

    def _push(self, event: Event) -> None:
        try:
            self.events.put_nowait(event)
        except queue.Full:
            pass  # UI is behind; dropping is intended

    def _read_loop(self) -> None:
        demux = Demux()
        while not self._stop.is_set():
            try:
                data = self._serial.read(4096)
            except serial.SerialException as exc:
                self._push(DisconnectedEvent(str(exc)))
                return
            if not data:
                continue
            demux.push(data)

            while True:
                item = demux.next_frame()
                if item is None:
                    break
                if isinstance(item, Frame):
                    self._push(FrameEvent(item))
                else:
                    self._push(BadEvent(item))


def list_ports() -> list[str]:
    return [p.device for p in serial.tools.list_ports.comports()]

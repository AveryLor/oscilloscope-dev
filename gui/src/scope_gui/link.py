"""Serial link: a reader process owns the port, resyncs the incoming
sample stream on the magic word, and a locked write path sends control
commands (see docs/CONTROL.md) the other direction on the same connection."""

from __future__ import annotations

import multiprocessing as mp
import queue
from dataclasses import dataclass

import serial
import serial.tools.list_ports

from . import frame as frame_mod
from .frame import HDR_BYTES, MAGIC, BadCrc, Frame, ParseError

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
            except BadCrc as exc:
                # Say *how* it broke: another frame's magic inside this one
                # means bytes went missing (overrun); otherwise the length is
                # right and the bits are wrong (line noise).
                inner = self._buf.find(magic, len(magic), total)
                kind = "bytes lost" if inner != -1 else "bit errors"
                del self._buf[:len(magic)]
                return f"{exc} ({kind})"
            except ParseError as exc:
                del self._buf[:len(magic)]
                return str(exc)

            del self._buf[:total]
            return parsed


def _put(q, event: Event) -> None:
    try:
        q.put_nowait(event)
    except queue.Full:
        pass  # UI is behind; dropping is intended


def _reader_main(port, baud, events, commands, opened, stop) -> None:
    """Child-process body: owns the port, demuxes frames, writes commands.

    This runs in its own process, not a thread, on purpose. A reader thread
    shares the GIL with Qt rendering; a ~45 ms paint stall let the kernel's
    4 KB n_tty buffer fill, the cp210x driver stopped polling, and the
    CP2102's 576-byte FIFO overflowed -- silently dropping bytes mid-frame
    (CRC mismatch, "bytes lost"). A separate process keeps draining the port
    no matter what the GUI is doing."""
    try:
        ser = serial.serial_for_url(port, baudrate=baud, timeout=0.05)
    except (serial.SerialException, ValueError, OSError) as exc:
        opened.put(str(exc))
        return
    opened.put(None)

    demux = Demux()
    try:
        while not stop.is_set():
            while True:
                try:
                    line = commands.get_nowait()
                except queue.Empty:
                    break
                ser.write(line)

            data = ser.read(4096)
            if not data:
                continue
            demux.push(data)
            while (item := demux.next_frame()) is not None:
                _put(events, FrameEvent(item) if isinstance(item, Frame) else BadEvent(item))
    except (serial.SerialException, OSError) as exc:
        _put(events, DisconnectedEvent(str(exc)))
    finally:
        try:
            ser.close()
        except (serial.SerialException, OSError):
            pass


class _Events:
    """The queue the UI polls. Wraps the child's multiprocessing queue so a
    reader process that dies without saying why still surfaces as a
    DisconnectedEvent instead of a silently frozen trace."""

    def __init__(self, q, proc) -> None:
        self._q = q
        self._proc = proc
        self._reported_death = False
        self.closing = False

    def get_nowait(self) -> Event:
        try:
            return self._q.get_nowait()
        except queue.Empty:
            if not self.closing and not self._reported_death and not self._proc.is_alive():
                self._reported_death = True
                return DisconnectedEvent(f"reader process exited (code {self._proc.exitcode})")
            raise


class Link:
    """Owns an open serial port via a reader process (see _reader_main) that
    feeds a Demux and posts events to a bounded queue -- a UI that falls
    behind drops captures rather than queuing them, since only the newest is
    worth drawing -- and send() queues control command lines the other way."""

    def __init__(self, port: str, baud: int = DEFAULT_BAUD, open_timeout: float = 5.0) -> None:
        # spawn, not fork: forking a process that already runs Qt threads is unsafe.
        ctx = mp.get_context("spawn")
        self._events_q = ctx.Queue(maxsize=8)
        self._commands = ctx.Queue()
        self._stop = ctx.Event()
        opened = ctx.Queue()
        self._proc = ctx.Process(
            target=_reader_main,
            args=(port, baud, self._events_q, self._commands, opened, self._stop),
            daemon=True,
        )
        self._proc.start()
        try:
            err = opened.get(timeout=open_timeout)
        except queue.Empty:
            err = "timed out opening port"
        if err is not None:
            self._proc.join(timeout=1.0)
            if self._proc.is_alive():
                self._proc.terminate()
            raise serial.SerialException(err)
        self.events = _Events(self._events_q, self._proc)

    def send(self, line: str) -> bool:
        """Queues one control command line (see docs/CONTROL.md) for the
        reader process to write, appending the newline terminator. Returns
        False if the reader process is gone; the UI learns why from the
        DisconnectedEvent it posts."""
        if not self._proc.is_alive():
            return False
        self._commands.put((line + "\n").encode("ascii"))
        return True

    def close(self) -> None:
        self.events.closing = True
        self._stop.set()
        self._proc.join(timeout=1.0)
        if self._proc.is_alive():
            self._proc.terminate()
            self._proc.join(timeout=1.0)


def list_ports() -> list[str]:
    return [p.device for p in serial.tools.list_ports.comports()]

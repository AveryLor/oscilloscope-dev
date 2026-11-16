from scope_gui import frame
from scope_gui.link import Demux

from _frame_builder import build_frame


def test_waits_for_more_bytes_instead_of_yielding_a_partial_frame():
    d = Demux()
    d.push(frame.MAGIC.to_bytes(4, "little"))
    assert d.next_frame() is None


def test_skips_leading_noise_that_never_contains_a_frame():
    d = Demux()
    d.push(b"no frame here at all, just log spew")
    assert d.next_frame() is None
    # The tail kept in case a magic word straddles two reads must stay bounded.
    assert len(d._buf) < 4


def test_resyncs_onto_a_frame_that_follows_stray_text():
    d = Demux()
    d.push(b"I (123) stray boot log line\n")
    d.push(build_frame(seq=7))

    result = d.next_frame()
    assert isinstance(result, frame.Frame)
    assert result.seq == 7
    assert d.next_frame() is None


def test_reports_a_string_reason_for_a_frame_with_a_corrupted_crc():
    raw = bytearray(build_frame())
    raw[-1] ^= 0xFF
    d = Demux()
    d.push(bytes(raw))

    result = d.next_frame()
    assert isinstance(result, str)


def test_delivers_frames_split_across_multiple_pushes():
    raw = build_frame(seq=99)
    d = Demux()
    d.push(raw[:10])
    assert d.next_frame() is None
    d.push(raw[10:])

    result = d.next_frame()
    assert isinstance(result, frame.Frame)
    assert result.seq == 99


def test_link_reader_process_delivers_frames_and_writes_commands():
    import os
    import queue
    import time

    from scope_gui.link import FrameEvent, Link

    master, slave = os.openpty()
    try:
        link = Link(os.ttyname(slave), 921_600)
        try:
            os.write(master, b"junk" + build_frame(seq=7))
            deadline = time.monotonic() + 5.0
            event = None
            while time.monotonic() < deadline:
                try:
                    event = link.events.get_nowait()
                    break
                except queue.Empty:
                    time.sleep(0.01)
            assert isinstance(event, FrameEvent)
            assert event.frame.seq == 7

            assert link.send("SET_COUPLING 1")
            got = b""
            deadline = time.monotonic() + 5.0
            while not got.endswith(b"\n") and time.monotonic() < deadline:
                got += os.read(master, 64)
            assert got == b"SET_COUPLING 1\n"
        finally:
            link.close()
    finally:
        os.close(master)
        os.close(slave)


def test_link_raises_when_the_port_cannot_be_opened():
    import pytest
    import serial

    from scope_gui.link import Link

    with pytest.raises(serial.SerialException):
        Link("/dev/does-not-exist-scope", 921_600)

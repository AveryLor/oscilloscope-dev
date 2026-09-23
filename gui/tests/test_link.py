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

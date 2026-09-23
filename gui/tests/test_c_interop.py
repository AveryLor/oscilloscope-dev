"""Checks this package's parser against bytes produced by the firmware's own
packer, so the two implementations of the wire format cannot drift apart
silently. docs/STREAM.md is the contract they both follow.

The fixture holds stray log text, then two back-to-back frames, exactly as
the ESP32 emits them. Regenerate it after any format change:

    gcc -Wall -Wextra -Werror -O2 -I esp32/main \\
        gui/tests/fixtures/emit_frame.c esp32/main/stream_frame.c -o /tmp/emit_frame
    /tmp/emit_frame > gui/tests/fixtures/c_frames.bin
"""

from pathlib import Path

from scope_gui import frame
from scope_gui.link import Demux

FIXTURE = (Path(__file__).parent / "fixtures" / "c_frames.bin").read_bytes()


def check_metadata(f: frame.Frame, expect_seq: int) -> None:
    """Field values written by gui/tests/fixtures/emit_frame.c."""
    assert f.seq == expect_seq
    assert f.sample_count == 16384
    assert f.dec_factor == 7
    assert f.pre_count == 1024
    assert f.post_count == 2048
    assert f.trig_ptr == 8192
    assert f.trig_level == 512
    assert f.afe_atten == 2
    assert f.lmh_atten == 6
    assert f.dac_offset == 2048

    assert f.triggered
    assert f.overrange
    assert not f.peak
    assert f.dc_coupled
    assert f.preamp_hg
    assert not f.term_50r

    assert len(f.cols) == 1000
    for c, (ymin, ymax) in enumerate(f.cols):
        assert ymin == 400 + c % 100, f"column {c} min"
        assert ymax == 600 + c % 100, f"column {c} max"


def test_parses_frames_built_by_the_firmware_packer():
    d = Demux()
    d.push(FIXTURE)

    first = d.next_frame()
    assert isinstance(first, frame.Frame), "a frame after the leading log text"
    check_metadata(first, 0xDEADBEEF)

    second = d.next_frame()
    assert isinstance(second, frame.Frame), "the back-to-back second frame"
    check_metadata(second, 0xDEADBEF0)

    assert d.next_frame() is None, "fixture holds exactly two frames"


def test_resyncs_when_the_stream_is_joined_mid_frame():
    # Start 40 bytes in, so the first frame is truncated and must be skipped.
    d = Demux()
    d.push(FIXTURE[40:])

    found = None
    for _ in range(10):
        item = d.next_frame()
        if isinstance(item, frame.Frame):
            found = item
            break
        if item is None:
            break
        # else: a false magic-word hit inside the truncated frame; keep scanning

    assert found is not None, "expected to resync onto the second frame"
    check_metadata(found, 0xDEADBEF0)


def test_rejects_a_frame_whose_payload_was_corrupted_in_transit():
    corrupted = bytearray(FIXTURE)
    first_payload = 23 + frame.HDR_BYTES + 8
    corrupted[first_payload] ^= 0xFF

    d = Demux()
    d.push(bytes(corrupted))

    result = d.next_frame()
    assert isinstance(result, str), "a corrupted payload must not parse as a good frame"

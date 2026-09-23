"""Test-only frame assembly, shared by test_frame.py and test_link.py. Builds
raw wire bytes field-by-field rather than reusing scope_gui.frame's parser, so
a bug in parse() can't hide itself from its own test fixtures."""

from __future__ import annotations

import zlib

from scope_gui.frame import HDR_BYTES, MAGIC, VERSION


def build_frame(
    *,
    seq: int = 1,
    sample_count: int = 100,
    dec_factor: int = 0,
    pre_count: int = 50,
    post_count: int = 50,
    trig_ptr: int = 25,
    trig_level: int = 512,
    afe_atten: int = 0,
    afe_flags: int = 0,
    lmh_atten: int = 0,
    dac_offset: int = 2048,
    flags: int = 0,
    cols: list[tuple[int, int]] | None = None,
) -> bytes:
    if cols is None:
        cols = [(100, 200)] * 4
    n_cols = len(cols)

    hdr = bytearray()
    hdr += MAGIC.to_bytes(4, "little")
    hdr += bytes([VERSION, flags])
    hdr += n_cols.to_bytes(2, "little")
    hdr += seq.to_bytes(4, "little")
    hdr += sample_count.to_bytes(4, "little")
    hdr += dec_factor.to_bytes(2, "little")
    hdr += pre_count.to_bytes(2, "little")
    hdr += post_count.to_bytes(2, "little")
    hdr += trig_ptr.to_bytes(4, "little")
    hdr += trig_level.to_bytes(2, "little")
    hdr += (0).to_bytes(2, "little")  # overrange_cnt, reserved
    hdr += bytes([afe_atten, afe_flags, lmh_atten, 0])  # 0 = pad
    hdr += dac_offset.to_bytes(2, "little")
    assert len(hdr) == HDR_BYTES

    payload = bytearray()
    for ymin, ymax in cols:
        payload += ymin.to_bytes(2, "little")
        payload += ymax.to_bytes(2, "little")

    body = bytes(hdr) + bytes(payload)
    crc = zlib.crc32(body[4:]) & 0xFFFFFFFF
    return body + crc.to_bytes(4, "little")

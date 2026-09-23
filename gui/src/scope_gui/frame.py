"""Wire-frame parsing for the ESP32 -> host sample stream.

The format is documented in docs/STREAM.md and written by
esp32/main/stream_frame.c; this module is the read side. Keep all three in
step -- gui/tests/test_c_interop.py checks this module against bytes produced
by the real firmware packer.
"""

from __future__ import annotations

import zlib
from dataclasses import dataclass

MAGIC = 0x53434F50  # "SCOP", little-endian on the wire
VERSION = 1
HDR_BYTES = 36

# Columns beyond this are treated as corrupt framing, not a real capture --
# the firmware only ever sends 1000, this is a generous sanity ceiling.
MAX_COLS = 4096

FLAG_PEAK = 1 << 0
FLAG_TRIGGERED = 1 << 1
FLAG_OVERRANGE = 1 << 2

AFE_DC_COUPLED = 1 << 0
AFE_TERM_50R = 1 << 1
AFE_PREAMP_HG = 1 << 2

# LMH6518 preamp steps (datasheet), and its ladder attenuator step size.
_PREAMP_LG_DB = 18.8
_PREAMP_HG_DB = 38.8
_LADDER_STEP_DB = 2.0

# Input divider network ratios for afe_atten 0/1/2.
_DIVIDER_RATIO = (1.0, 10.0, 100.0)

# AD9215 default internal reference gives a 2.0 Vpp full-scale differential
# input; mid-code (512) is 0 V at the ADC pins. Verify against board
# calibration if measurements drift -- this is the one constant in this file
# that depends on how the reference was actually configured in hardware.
ADC_FS_VOLTS = 2.0
ADC_CODE_MID = 512
_ADC_LSB_VOLTS = ADC_FS_VOLTS / 1024


class ParseError(Exception):
    """Base class for frame parse failures."""


class BadVersion(ParseError):
    def __init__(self, version: int) -> None:
        self.version = version
        super().__init__(f"unsupported frame version {version} (expected {VERSION})")


class BadColumnCount(ParseError):
    def __init__(self, n_cols: int) -> None:
        self.n_cols = n_cols
        super().__init__(f"implausible column count {n_cols}")


class BadCrc(ParseError):
    def __init__(self) -> None:
        super().__init__("CRC mismatch")


@dataclass(frozen=True)
class Frame:
    seq: int
    sample_count: int
    dec_factor: int
    pre_count: int
    post_count: int
    trig_ptr: int
    trig_level: int
    afe_atten: int
    lmh_atten: int
    dac_offset: int
    peak: bool
    triggered: bool
    overrange: bool
    dc_coupled: bool
    term_50r: bool
    preamp_hg: bool
    cols: tuple[tuple[int, int], ...]  # (ymin, ymax) codes, one pair per column

    def sample_period(self) -> float:
        """Seconds per sample, from the 105 MHz encode clock and decimation."""
        return (self.dec_factor + 1) / 105_000_000.0

    def duration(self) -> float:
        return self.sample_count * self.sample_period()

    def volts_per_count(self) -> float:
        """Volts at the probe tip per ADC code step, given the current AFE
        settings (input divider, LMH6518 preamp + ladder attenuation)."""
        preamp_db = _PREAMP_HG_DB if self.preamp_hg else _PREAMP_LG_DB
        gain_db = preamp_db - self.lmh_atten * _LADDER_STEP_DB
        gain_v_per_v = 10 ** (gain_db / 20.0)
        divider = _DIVIDER_RATIO[self.afe_atten]
        return _ADC_LSB_VOLTS * divider / gain_v_per_v

    def code_to_volts(self, code: int) -> float:
        return (code - ADC_CODE_MID) * self.volts_per_count()

    def trig_fraction(self) -> float | None:
        """Trigger position as a fraction of the record, or None if the record
        is empty."""
        if self.sample_count == 0:
            return None
        return min(1.0, self.trig_ptr / self.sample_count)


def cols_of(header: bytes) -> int:
    """Reads n_cols out of a buffer that starts at the magic word and holds at
    least the version and n_cols fields. Raises BadVersion/BadColumnCount
    without needing the CRC or payload, so a caller can size its read before
    the rest of the frame has arrived."""
    version = header[4]
    if version != VERSION:
        raise BadVersion(version)
    n_cols = int.from_bytes(header[6:8], "little")
    if n_cols == 0 or n_cols > MAX_COLS:
        raise BadColumnCount(n_cols)
    return n_cols


def parse(buf: bytes) -> Frame:
    """Parses one complete frame (magic word through the trailing CRC)."""
    n_cols = cols_of(buf)
    payload_end = HDR_BYTES + n_cols * 4
    total = payload_end + 4

    crc_stored = int.from_bytes(buf[payload_end:total], "little")
    crc_calc = zlib.crc32(buf[4:payload_end]) & 0xFFFFFFFF
    if crc_calc != crc_stored:
        raise BadCrc()

    flags = buf[5]
    afe_flags = buf[31]

    cols = tuple(
        (
            int.from_bytes(buf[off:off + 2], "little"),
            int.from_bytes(buf[off + 2:off + 4], "little"),
        )
        for off in range(HDR_BYTES, payload_end, 4)
    )

    return Frame(
        seq=int.from_bytes(buf[8:12], "little"),
        sample_count=int.from_bytes(buf[12:16], "little"),
        dec_factor=int.from_bytes(buf[16:18], "little"),
        pre_count=int.from_bytes(buf[18:20], "little"),
        post_count=int.from_bytes(buf[20:22], "little"),
        trig_ptr=int.from_bytes(buf[22:26], "little"),
        trig_level=int.from_bytes(buf[26:28], "little"),
        afe_atten=buf[30],
        lmh_atten=buf[32],
        dac_offset=int.from_bytes(buf[34:36], "little"),
        peak=bool(flags & FLAG_PEAK),
        triggered=bool(flags & FLAG_TRIGGERED),
        overrange=bool(flags & FLAG_OVERRANGE),
        dc_coupled=bool(afe_flags & AFE_DC_COUPLED),
        term_50r=bool(afe_flags & AFE_TERM_50R),
        preamp_hg=bool(afe_flags & AFE_PREAMP_HG),
        cols=cols,
    )

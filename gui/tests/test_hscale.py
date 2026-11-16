"""The horizontal-scale display above the plot: acquisition mode cycled by the
HS knob's button, plus the decimation and time/div set by the knob."""

from __future__ import annotations

from _frame_builder import build_frame

from scope_gui import frame
from scope_gui.app import acq_mode, fmt_hscale


def _f(**kw) -> frame.Frame:
    return frame.parse(build_frame(**kw))


def test_mode_follows_the_frame_flags():
    assert acq_mode(_f()) == "sampled"
    assert acq_mode(_f(flags=frame.FLAG_PEAK)) == "peak"
    assert acq_mode(_f(flags=frame.FLAG_HIRES)) == "hires"
    # The FPGA lets peak win if both are set; the display must agree.
    assert acq_mode(_f(flags=frame.FLAG_PEAK | frame.FLAG_HIRES)) == "peak"


def test_summary_shows_mode_decimation_and_time_per_div():
    # 1000 samples at /8 (dec_factor 7) = 80 us record -> 8 us/div.
    text = fmt_hscale(_f(flags=frame.FLAG_HIRES, dec_factor=7, sample_count=1000))
    assert text == "HIGH-RES (CIC)  ·  /8  ·  8.00 µs/div"

    text = fmt_hscale(_f(dec_factor=0, sample_count=2048))
    assert text.startswith("SAMPLED  ·  /1  ·  ")

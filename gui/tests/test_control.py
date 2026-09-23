"""Table-driven checks that the six SET_* formatters produce exactly the wire
grammar esp32/main/cmd_parse.c expects (docs/CONTROL.md), and reject anything
outside the range the firmware accepts. See esp32/test/test_cmd_parse.c for
the matching decode-side tests."""

import pytest

from scope_gui import control


@pytest.mark.parametrize(
    "dec_factor,expected",
    [(0, "SET_TIMEBASE 0"), (65535, "SET_TIMEBASE 65535"), (1234, "SET_TIMEBASE 1234")],
)
def test_fmt_set_timebase(dec_factor, expected):
    assert control.fmt_set_timebase(dec_factor) == expected


@pytest.mark.parametrize("dec_factor", [-1, 65536])
def test_fmt_set_timebase_rejects_out_of_range(dec_factor):
    with pytest.raises(ValueError):
        control.fmt_set_timebase(dec_factor)


def test_fmt_set_hoffset():
    assert control.fmt_set_hoffset(100, 200) == "SET_HOFFSET 100 200"
    assert control.fmt_set_hoffset(0, 0) == "SET_HOFFSET 0 0"


@pytest.mark.parametrize("pre,post", [(-1, 0), (0, -1), (65536, 0), (0, 65536)])
def test_fmt_set_hoffset_rejects_out_of_range(pre, post):
    with pytest.raises(ValueError):
        control.fmt_set_hoffset(pre, post)


def test_fmt_set_trigger():
    assert control.fmt_set_trigger(512, 0, 0, 8) == "SET_TRIGGER 512 0 0 8"
    assert control.fmt_set_trigger(1023, 2, 2, 255) == "SET_TRIGGER 1023 2 2 255"


@pytest.mark.parametrize(
    "level,src,edge,hyst",
    [(1024, 0, 0, 0), (0, 3, 0, 0), (0, 0, 3, 0), (0, 0, 0, 256), (-1, 0, 0, 0)],
)
def test_fmt_set_trigger_rejects_out_of_range(level, src, edge, hyst):
    with pytest.raises(ValueError):
        control.fmt_set_trigger(level, src, edge, hyst)


def test_fmt_set_vertical():
    assert control.fmt_set_vertical(1, 1, 5, 2048) == "SET_VERTICAL 1 1 5 2048"
    assert control.fmt_set_vertical(0, 0, 0, 0) == "SET_VERTICAL 0 0 0 0"
    assert control.fmt_set_vertical(2, 1, 10, 4095) == "SET_VERTICAL 2 1 10 4095"


@pytest.mark.parametrize(
    "atten,preamp,lmh_atten,offset",
    [(3, 0, 0, 0), (0, 2, 0, 0), (0, 0, 11, 0), (0, 0, 0, 4096)],
)
def test_fmt_set_vertical_rejects_out_of_range(atten, preamp, lmh_atten, offset):
    with pytest.raises(ValueError):
        control.fmt_set_vertical(atten, preamp, lmh_atten, offset)


def test_fmt_set_coupling():
    assert control.fmt_set_coupling(True) == "SET_COUPLING 1"
    assert control.fmt_set_coupling(False) == "SET_COUPLING 0"


def test_fmt_set_term():
    assert control.fmt_set_term(True) == "SET_TERM 1"
    assert control.fmt_set_term(False) == "SET_TERM 0"

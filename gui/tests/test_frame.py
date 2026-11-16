import zlib

import pytest

from scope_gui import frame

from _frame_builder import build_frame


def test_crc_matches_reference_vector():
    # The standard CRC-32 check value for the ASCII string "123456789".
    assert zlib.crc32(b"123456789") & 0xFFFFFFFF == 0xCBF43926


def test_round_trips_a_built_frame():
    raw = build_frame(
        seq=42,
        sample_count=1000,
        dec_factor=3,
        pre_count=400,
        post_count=600,
        trig_ptr=250,
        trig_level=600,
        afe_atten=1,
        afe_flags=frame.AFE_DC_COUPLED | frame.AFE_PREAMP_HG,
        lmh_atten=4,
        dac_offset=1500,
        flags=frame.FLAG_TRIGGERED | frame.FLAG_OVERRANGE,
        cols=[(100, 200), (300, 400), (50, 900)],
    )
    f = frame.parse(raw)

    assert f.seq == 42
    assert f.sample_count == 1000
    assert f.dec_factor == 3
    assert f.pre_count == 400
    assert f.post_count == 600
    assert f.trig_ptr == 250
    assert f.trig_level == 600
    assert f.afe_atten == 1
    assert f.lmh_atten == 4
    assert f.dac_offset == 1500
    assert f.triggered is True
    assert f.overrange is True
    assert f.peak is False
    assert f.dc_coupled is True
    assert f.preamp_hg is True
    assert f.term_50r is False
    assert f.cols == ((100, 200), (300, 400), (50, 900))


def test_rejects_a_bad_version():
    raw = bytearray(build_frame())
    raw[4] = 99
    with pytest.raises(frame.BadVersion):
        frame.parse(bytes(raw))


def test_rejects_a_corrupted_payload():
    raw = bytearray(build_frame())
    raw[frame.HDR_BYTES] ^= 0xFF
    with pytest.raises(frame.BadCrc):
        frame.parse(bytes(raw))


def test_rejects_an_absurd_column_count():
    raw = bytearray(build_frame())
    raw[6:8] = (0xFFFF).to_bytes(2, "little")
    with pytest.raises(frame.BadColumnCount):
        frame.parse(bytes(raw))


def test_attenuation_scales_volts_per_count():
    base = frame.parse(build_frame(afe_atten=0, afe_flags=0, lmh_atten=0))
    ten_x = frame.parse(build_frame(afe_atten=1, afe_flags=0, lmh_atten=0))
    hundred_x = frame.parse(build_frame(afe_atten=2, afe_flags=0, lmh_atten=0))

    assert ten_x.volts_per_count() == pytest.approx(base.volts_per_count() * 10)
    assert hundred_x.volts_per_count() == pytest.approx(base.volts_per_count() * 100)

    hg = frame.parse(build_frame(afe_atten=0, afe_flags=frame.AFE_PREAMP_HG, lmh_atten=0))
    assert hg.volts_per_count() < base.volts_per_count()  # more gain, fewer volts/count


def test_parses_gain_reduced_and_hires_flags():
    f = frame.parse(build_frame(flags=frame.FLAG_GAIN_REDUCED | frame.FLAG_HIRES))
    assert f.gain_reduced is True
    assert f.hires is True
    assert f.peak is False
    assert f.overrange is False

    f = frame.parse(build_frame(flags=frame.FLAG_PEAK | frame.FLAG_OVERRANGE))
    assert f.gain_reduced is False
    assert f.hires is False


def test_settings_key_changes_only_when_a_setting_does():
    base = frame.parse(build_frame(seq=1, lmh_atten=4))
    # A new capture with the same settings: different seq and data, same key.
    same = frame.parse(build_frame(seq=2, lmh_atten=4, cols=[(1, 2)] * 4,
                                   flags=frame.FLAG_TRIGGERED))
    assert same.settings_key() == base.settings_key()

    # Each echoed control setting moves the key (a knob turn shows up here).
    for change in (
        {"dec_factor": 7},
        {"pre_count": 10},
        {"post_count": 10},
        {"trig_level": 100},
        {"afe_atten": 2},
        {"lmh_atten": 5},
        {"dac_offset": 100},
        {"afe_flags": frame.AFE_PREAMP_HG},
        {"afe_flags": frame.AFE_DC_COUPLED},
        {"afe_flags": frame.AFE_TERM_50R},
    ):
        kwargs = {"lmh_atten": 4, **change}
        assert frame.parse(build_frame(**kwargs)).settings_key() != base.settings_key(), change

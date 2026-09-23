"""Streams synthetic frames (see docs/PROTOCOL.md / scope_gui.frame) over a
serial port so the GUI can be exercised without real ESP32 hardware.

Usage:
    socat -d -d pty,raw,echo=0,link=/tmp/vscope0 pty,raw,echo=0,link=/tmp/vscope1 &
    python tools/fake_scope.py --port /tmp/vscope0
    oscilloscope-gui --port /tmp/vscope1
"""

from __future__ import annotations

import argparse
import math
import time
import zlib

import serial

MAGIC = 0x53434F50
VERSION = 1
FLAG_TRIGGERED = 1 << 1
ADC_CODE_MID = 512


def build_frame(seq: int, n_cols: int, t: float, freq_hz: float, amplitude: int) -> bytes:
    sample_count = n_cols
    pre_count = n_cols // 2
    post_count = n_cols - pre_count
    trig_ptr = pre_count
    trig_level = ADC_CODE_MID

    hdr = bytearray()
    hdr += MAGIC.to_bytes(4, "little")
    hdr += bytes([VERSION, FLAG_TRIGGERED])
    hdr += n_cols.to_bytes(2, "little")
    hdr += seq.to_bytes(4, "little")
    hdr += sample_count.to_bytes(4, "little")
    hdr += (0).to_bytes(2, "little")  # dec_factor
    hdr += pre_count.to_bytes(2, "little")
    hdr += post_count.to_bytes(2, "little")
    hdr += trig_ptr.to_bytes(4, "little")
    hdr += trig_level.to_bytes(2, "little")
    hdr += (0).to_bytes(2, "little")  # reserved
    hdr += bytes([0, 0, 0, 0])  # afe_atten, afe_flags, lmh_atten, pad
    hdr += (2048).to_bytes(2, "little")  # dac_offset
    assert len(hdr) == 36

    payload = bytearray()
    for i in range(n_cols):
        phase = 2 * math.pi * freq_hz * (t + i / n_cols)
        center = ADC_CODE_MID + amplitude * math.sin(phase)
        wobble = 6 * math.sin(20 * phase)  # gives the envelope visible thickness
        ymin = max(0, min(1023, int(center - abs(wobble))))
        ymax = max(0, min(1023, int(center + abs(wobble))))
        payload += ymin.to_bytes(2, "little")
        payload += ymax.to_bytes(2, "little")

    body = bytes(hdr) + bytes(payload)
    crc = zlib.crc32(body[4:]) & 0xFFFFFFFF
    return body + crc.to_bytes(4, "little")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="serial port/pty to write frames to")
    parser.add_argument("--baud", type=int, default=921_600)
    parser.add_argument("--cols", type=int, default=500, help="samples per frame")
    parser.add_argument("--freq", type=float, default=1.0, help="waveform frequency, Hz")
    parser.add_argument("--amplitude", type=int, default=400, help="ADC code amplitude (0-511)")
    parser.add_argument("--fps", type=float, default=20.0, help="frames per second")
    args = parser.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=0)
    seq = 0
    period = 1.0 / args.fps
    t0 = time.monotonic()
    print(f"streaming to {args.port} at {args.fps} fps, ctrl-c to stop")
    try:
        while True:
            t = time.monotonic() - t0
            frame = build_frame(seq, args.cols, t, args.freq, args.amplitude)
            ser.write(frame)
            seq += 1
            time.sleep(period)
    except KeyboardInterrupt:
        pass
    finally:
        ser.close()


if __name__ == "__main__":
    main()

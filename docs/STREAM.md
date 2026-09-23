# Oscilloscope ESP32 -> host sample stream

One-way binary stream over the ESP32's USB-UART link. The ESP32 arms the FPGA,
waits for each frozen record, reduces it to a fixed number of `{min, max}`
columns, and writes one frame per capture.

Source of truth for the numbers below:

| Artifact | Role |
|----------|------|
| `esp32/main/stream_frame.h` | Magic, version, offsets, flag bits |
| `esp32/main/stream_frame.c` | Frame writer |
| `gui/src/frame.rs` | Frame parser |
| this file | Prose: framing, field meanings |

Change one, change all four.

`esp32/main/stream_frame.c` and `envelope.c` deliberately avoid ESP-IDF headers
so they build on a host compiler. `esp32/test/` exercises them directly, and
`gui/tests/c_interop.rs` parses bytes this writer produced, so the two ends of
the format cannot drift apart without a test failing.

This is a different link from `docs/PROTOCOL.md`, which covers the ESP32 <-> FPGA
SPI register contract. This document starts where that one ends.

## Link parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Interface | UART0 | GPIO1 TX / GPIO3 RX, via the board's USB-serial bridge |
| Baud | 921600 | `STREAM_BAUD`; the same wire `idf.py monitor` uses |
| Format | 8N1, no flow control | |
| Direction | ESP32 -> host only | the host sends nothing back |

The ESP32 is a classic ESP32 with no native USB, so "over USB" means this UART
behind the bridge chip. Because that is also the console, `stream_init()`
silences `ESP_LOG` output once the first capture is armed; init-time logs still
appear, so bring-up stays debuggable. If any stray text does reach the wire, the
magic word and CRC below let the host resync without restarting.

## Why columns instead of samples

A full 16384-entry record is 32 kB. At 921600 baud that is ~0.35 s per frame,
capping the display near 3 frames/s. Reducing to 1000 columns of `{min, max}`
gives 4 kB per frame and ~20 frames/s.

The reduction keeps the min and max of every sample that falls in a column
rather than picking one sample per column, so a spike narrower than a column
still shows up as a tall band instead of disappearing. This is the same
envelope approach the FPGA's old display pipeline used, moved into firmware.

When a record holds fewer entries than there are columns, the last value is held
across the skipped columns so the trace stays continuous.

## Frame layout

All fields little-endian. Header is 36 bytes, followed by `n_cols` column pairs,
followed by a 4-byte CRC.

| Offset | Size | Field | Meaning |
|--------|------|-------|---------|
| 0 | 4 | `magic` | `0x53434F50` ("SCOP"), resync marker |
| 4 | 1 | `version` | `1` |
| 5 | 1 | `flags` | see below |
| 6 | 2 | `n_cols` | columns that follow (1000) |
| 8 | 4 | `seq` | frame counter; gaps mean dropped frames |
| 12 | 4 | `sample_count` | record entries before reduction |
| 16 | 2 | `dec_factor` | timebase decimation - 1 |
| 18 | 2 | `pre_count` | samples captured before the trigger |
| 20 | 2 | `post_count` | samples captured after the trigger |
| 22 | 4 | `trig_ptr` | trigger position within the record |
| 26 | 2 | `trig_level` | trigger level, 10-bit code |
| 28 | 2 | `overrange_cnt` | reserved, currently 0 (see `flags`) |
| 30 | 1 | `afe_atten` | 0 = 1x, 1 = 10x, 2 = 100x input divider |
| 31 | 1 | `afe_flags` | see below |
| 32 | 1 | `lmh_atten` | LMH6518 ladder code, 2 dB per step |
| 33 | 1 | pad | 0 |
| 34 | 2 | `dac_offset` | MCP4726 12-bit vertical offset code |
| 36 | 4*n | `cols` | per column: `u16 ymin`, `u16 ymax`, 10-bit codes |
| 36+4n | 4 | `crc32` | over bytes 4 .. 36+4n |

### `flags`

| Bit | Name | Meaning |
|-----|------|---------|
| 0 | `PEAK` | record came from peak-detect mode |
| 1 | `TRIGGERED` | a real trigger fired; clear means an AUTO timeout |
| 2 | `OVERRANGE` | at least one sample in the record clipped |

### `afe_flags`

| Bit | Name | Meaning |
|-----|------|---------|
| 0 | `DC_COUPLED` | clear means AC coupled |
| 1 | `TERM_50R` | clear means 1 MOhm |
| 2 | `PREAMP_HG` | LMH6518 high-gain preamp selected |

The front-end settings ship raw rather than pre-combined into a gain figure: the
LMH6518 preamp steps are 18.8 dB and 38.8 dB, which an integer dB field cannot
carry without skewing a measurement. The host holds the same datasheet numbers
and does the arithmetic in floating point.

### CRC

CRC-32, the standard reflected polynomial `0xEDB88320`, init `0xFFFFFFFF`, final
xor `0xFFFFFFFF`. It covers everything after the magic word, so a host that
resyncs mid-stream can still validate the frame it landed on.

## Host receive loop

```
scan for magic 0x53434F50
read 32 more header bytes
check version, sanity-check n_cols
read 4 * n_cols payload bytes and the 4-byte CRC
verify CRC; on mismatch discard and resume scanning for magic
```

Frames arrive unsolicited and continuously. A host that falls behind should drop
older frames rather than queue them: only the newest capture is worth drawing.

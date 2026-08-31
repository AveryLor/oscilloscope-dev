# Oscilloscope ESP32 <-> FPGA SPI protocol

The ESP32 is the SPI master (VSPI / `SPI3_HOST`), the Tang Nano 20K FPGA is the
slave. One extra line, `FPGA_IRQ` (FPGA -> ESP32 GPIO16, active-high, idle low),
signals "a capture is frozen and ready to read".

Source of truth for the numbers below:

| Artifact | Role |
|----------|------|
| `fpga/rtl/scope_regs.svh` | RTL register addresses + bit positions (`localparam`) |
| `esp32/main/scope_proto.h` | Same values as C `#define`s + record decode helper |
| this file | Prose: framing, sequences, field meanings |

Change one, change all three.

## Electrical / link parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| SPI mode | 0 (CPOL=0, CPHA=0) | assumed; confirm on a scope during bring-up |
| Bit order | MSB first | |
| Word size | 8 bits | |
| SCLK | <= 40 MHz | `timing.sdc` `spi_sclk` period 25 ns; keep the ESP32 `clock_speed_hz` in sync |
| CS | active low, idle high | one frame per CS assertion |
| IRQ | active high, idle low | ESP32 uses an internal pull-down + posedge ISR |

`spi_sclk` is treated as fully asynchronous to the 105 MHz capture clock
(`set_clock_groups -asynchronous`).

## Framing

Byte 0 of every frame is the header:

```
bit  7   6   5   4   3   2   1   0
    RW  A6  A5  A4  A3  A2  A1  A0
```

- `RW = 1`: read. `RW = 0`: write.
- `A[6:0]`: start address.

### Write frame

```
MOSI: [hdr:0,addr] [d0] [d1] [d2] ...
MISO: (don't care)
```

`d0` is written to `reg[addr]`, `d1` to `reg[addr+1]`, and so on until CS
deasserts. Writing a read-only register is silently ignored.

### Read frame

```
MOSI: [hdr:1,addr] [xx] [xx] [xx] ...
MISO: [xx]         [00] [r0] [r1] ...
```

The FPGA sends one **turnaround byte** (`0x00`) in the slot after the header,
then `reg[addr]`, `reg[addr+1]`, ... The master must clock one extra dummy byte
before the first real data byte.

### `REG_REC_DATA` (0x40)

The one register whose address does **not** auto-increment. Each read byte pops
the next byte from the record readout FIFO. Reads past the end of the record
return `0xFF` (`SCOPE_REC_PAD`) and set `RECST_UNDERFLOW` in `REG_REC_STATUS`.

Multi-byte fields (`*_L`/`*_H`, `*_0..3`) are **little-endian**: the lowest
address holds the least-significant byte.

## Register map

| Addr | Name | R/W | Reset | Meaning |
|------|------|-----|-------|---------|
| 0x00 | `ID0` | RO | `'S'` | magic |
| 0x01 | `ID1` | RO | `'C'` | magic |
| 0x02 | `VER_MAJ` | RO | 1 | protocol major |
| 0x03 | `VER_MIN` | RO | 0 | protocol minor |
| 0x04 | `CAPS` | RO | build | b0 peak-detect, b1 ext-trig, b2 SDRAM (0 in v1), b3 built with `SAMPLE_DEPTH=32768` |
| 0x05..0x06 | `BUF_DEPTH` | RO | `SAMPLE_DEPTH` | sample capacity, 16-bit LE |
| 0x08 | `CONTROL` | RW | 0x00 | see below |
| 0x09 | `MODE` | RW | 0x00 | b1:0 mode (0 NORMAL / 1 AUTO / 2 SINGLE), b2 peak-detect enable |
| 0x0A | `TRIG_CFG` | RW | 0x00 | b1:0 source (0 level / 1 ext / 2 force-only), b3:2 edge (0 rising / 1 falling / 2 either) |
| 0x0C..0x0D | `TRIG_LEVEL` | RW | 0x0200 | 10-bit level code (corrected domain), 16-bit LE; also driven by the trigger knob |
| 0x0E | `TRIG_HYST` | RW | 0x08 | level-trigger hysteresis code |
| 0x10..0x11 | `DEC_FACTOR` | RW | 0 | decimation - 1 (0 => /1), 16-bit LE; also driven by the horizontal-scale knob |
| 0x14..0x15 | `PRE_COUNT` | RW | `DEPTH/2` | pre-trigger samples, 16-bit LE; the horizontal-offset knob shifts the pre/post split |
| 0x16..0x17 | `POST_COUNT` | RW | `DEPTH/2` | post-trigger samples, 16-bit LE |
| 0x18..0x1B | `AUTO_TMO` | RW | ~100 ms | auto-trigger timeout in prescaled capture ticks, 32-bit LE |
| 0x1C..0x1D | `PROBE_DIV` | RW | 0 | probe-comp half period in 27 MHz cycles (0 => 1 kHz), 16-bit LE |
| 0x1E | `PROBE_CTL` | RW | 0x01 | b0 probe-comp enable |
| 0x20 | `STATUS` | RO | - | b2:0 acq state, b3 frozen, b4 pll_lock, b5 irq, b6 triggered_by_auto, b7 overrun |
| 0x21..0x24 | `SAMPLE_COUNT` | RO | - | valid entries in the frozen record, 32-bit LE |
| 0x25..0x28 | `TRIG_PTR` | RO | - | trigger sample offset within the record, 32-bit LE |
| 0x29..0x2A | `TRIG_PHASE` | RO | - | decimation phase counter at the trigger event, 16-bit LE |
| 0x2B..0x2C | `OVERRANGE_CNT` | RO | - | over-range samples in the record, 16-bit LE |
| 0x30..0x31 | `ENC_HS` | RO | 0 | signed 16-bit raw horizontal-scale encoder count (diagnostic) |
| 0x32..0x33 | `ENC_HO` | RO | 0 | signed 16-bit raw horizontal-offset encoder count (diagnostic) |
| 0x34..0x35 | `ENC_TG` | RO | 0 | signed 16-bit raw trigger-level encoder count (diagnostic) |
| 0x36 | `ENC_BTN` | RO | 0 | b0 hs level, b1 hs event, b2 ho level, b3 ho event, b4 tg level, b5 tg event; event bits clear on read |
| 0x40 | `REC_DATA` | RO | - | pop one record byte (no address increment) |
| 0x41 | `REC_STATUS` | RO | - | b0 fifo_empty, b1 record_done, b2 underflow |

### `CONTROL` bits (0x08)

| Bit | Name | Kind | Effect |
|-----|------|------|--------|
| 0 | `ARM` | W1 | arm the acquisition engine |
| 1 | `ABORT` | W1 | abort to IDLE, discard any in-progress capture |
| 2 | `FORCE_TRIG` | W1 | force an immediate trigger |
| 3 | `AUTO_REARM` | level | re-arm automatically after each dump |
| 4 | `INVERT_EN` | level | apply the VIN+/VIN- mid-scale code inversion |
| 5 | `IRQ_CLR` | W1 | acknowledge and clear `FPGA_IRQ` |
| 6 | `REC_REWIND` | W1 | restart the record readout from the first sample |
| 7 | `SOFT_RESET` | W1 | soft-reset the datapath (settings preserved) |

## Sequences

### Configure + arm

```
write MODE, TRIG_CFG, TRIG_LEVEL, TRIG_HYST, DEC_FACTOR, PRE_COUNT,
      POST_COUNT, AUTO_TMO, INVERT_EN/AUTO_REARM bits of CONTROL
write CONTROL with ARM
```

Writing any config register updates the working value immediately; the FPGA
commits the whole set into the capture domain atomically on the next change. A
knob turn updates the same working value, so `TRIG_LEVEL` / `DEC_FACTOR` /
`PRE_COUNT` / `POST_COUNT` read back the current effective setting whichever
source last moved it.

### Read a frozen record

```
wait for FPGA_IRQ rising  (or poll STATUS.frozen)
read STATUS               -> confirm frozen = 1
read SAMPLE_COUNT (4 B)   -> N entries
read TRIG_PTR (4 B), TRIG_PHASE (2 B), OVERRANGE_CNT (2 B)
loop: read REC_DATA       -> 2*N bytes, little-endian entries
write CONTROL with IRQ_CLR
(optional) write CONTROL with ARM   (not needed if AUTO_REARM is set)
```

Each entry is two bytes: `byte0 = code[7:0]`, `byte1 = {is_max, over_range,
0,0,0,0, code[9:8]}`. `scope_decode_sample()` in `scope_proto.h` unpacks one.

`TRIG_PTR` is the index (in entries) of the trigger sample within the record, so
the host aligns the trace by placing entry `TRIG_PTR` at t = 0. `TRIG_PHASE` is
the sub-sample decimation-counter value at the trigger for fine horizontal
positioning on slow timebases.

### Re-arm race

If `ARM` is written while a dump is still in progress, the FPGA finishes handing
the record across (drains the readout FIFO) before it clears `frozen` and resumes
writing. The host may safely `ARM` immediately after the last `REC_DATA` read.

## Peak-detect (`MODE.b2`)

On slow timebases each decimation window emits **two** entries — the window
minimum then the window maximum — so a narrow glitch inside the window still
shows up. `SAMPLE_COUNT` then counts min/max entries (twice the number of
windows) and `is_max` distinguishes them.

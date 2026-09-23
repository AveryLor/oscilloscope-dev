# Oscilloscope host -> ESP32 control commands

Plain-text line commands over the same USB-UART link `docs/STREAM.md` streams
sample frames out on, in the opposite direction. The GUI sends one line per
control change; the ESP32 applies it to the FPGA's acquisition registers or
the analog front end and never writes a reply.

Source of truth for the grammar below:

| Artifact | Role |
|----------|------|
| `esp32/main/cmd_parse.h` | Command grammar, field ranges |
| `esp32/main/cmd_parse.c` | Line parser |
| `gui/src/scope_gui/control.py` | Line formatter |
| this file | Prose: grammar, rationale |

Change one, change all four.

`esp32/main/cmd_parse.c` deliberately avoids ESP-IDF headers so it builds on a
host compiler; `esp32/test/test_cmd_parse.c` exercises it directly, and
`gui/tests/test_control.py` checks the formatter produces exactly the strings
the parser accepts, so the two ends of the grammar cannot drift apart without
a test failing.

This is a different link from `docs/PROTOCOL.md`, which covers the ESP32 <-> FPGA
SPI register contract these commands ultimately drive.

## Link parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Interface | UART0 | same physical connection as the sample stream |
| Baud | 921600 | matches `STREAM_BAUD`; UART is full duplex, so this direction doesn't contend with the stream |
| Format | 8N1, no flow control | |
| Direction | host -> ESP32 only | the ESP32 never writes text on this wire; see "Why no ACK" below |

## Grammar

One command per line, fields space-separated, terminated by `\n` (a trailing
`\r` is stripped and tolerated). Every field is an unsigned decimal integer;
no signs, no whitespace runs, no trailing garbage after the last field.

| Command | Fields | Ranges | Drives |
|---------|--------|--------|--------|
| `SET_TIMEBASE` | `dec_factor` | u16 | `REG_DEC_FACTOR_L/H` |
| `SET_HOFFSET` | `pre_count` `post_count` | u16 u16 | `REG_PRE_COUNT_L/H`, `REG_POST_COUNT_L/H` |
| `SET_TRIGGER` | `level` `src` `edge` `hyst` | u16(0-1023) u8(0-2) u8(0-2) u8 | `REG_TRIG_CFG`, `REG_TRIG_LEVEL_L/H`, `REG_TRIG_HYST` |
| `SET_VERTICAL` | `atten` `preamp` `lmh_atten` `offset_code` | u8(0-2) u8(0-1) u8(0-10) u16(0-4095) | `afe_set()` |
| `SET_COUPLING` | `mode` | u8(0=AC 1=DC) | `afe_set()` |
| `SET_TERM` | `mode` | u8(0=1MOhm 1=50Ohm) | `afe_set()` |

`src`: 0 = level, 1 = ext, 2 = force. `edge`: 0 = rising, 1 = falling, 2 =
either. `preamp`: 0 = low gain (18.8 dB), 1 = high gain (38.8 dB). `atten`: 0
= 1x, 1 = 10x, 2 = 100x. These match `docs/PROTOCOL.md`'s register map and
`esp32/main/afe.h`'s `afe_config_t` exactly.

Example lines:

```
SET_TIMEBASE 3
SET_HOFFSET 1024 1024
SET_TRIGGER 512 0 0 8
SET_VERTICAL 1 0 4 2048
SET_COUPLING 1
SET_TERM 0
```

## Why plain text, not a binary/CRC frame

`docs/STREAM.md` uses a binary framed protocol with a CRC because it carries
continuous, high-throughput data (~20 frames/s, 4 KB each) where a corrupted
frame must be actively detected and discarded. Control traffic is the
opposite: low-rate bursts from slider drags, at most a few lines per second.
For that, plain text wins on every axis that matters here: it's trivial to
construct in Python and parse with a hand-rolled tokenizer in C, it's
debuggable by typing a line into a raw serial terminal, and it's
self-healing — a dropped line just leaves the old setting in place until the
next line corrects it, so there's nothing worth a checksum over.

## Malformed-line handling

`cmd_parse_line()` rejects a line outright on any unknown keyword, wrong field
count, non-numeric token, out-of-range value, or trailing garbage — it never
partially applies a command. `esp32/main/cmd.c`'s line reader also drops
anything that overruns its line buffer without a `\n` (a torn or garbled
write) and resyncs on the next newline, rather than ever indexing out of
bounds.

## Why no ACK

The ESP32 never writes text back on this UART — only the binary stream from
`docs/STREAM.md` goes out on it. Recreating a reply channel here would
reintroduce exactly the stray-text-vs-binary-frame interleaving hazard that
document already solves for boot logs. Instead, every stream frame already
echoes the fields these commands set — `dec_factor`, `pre_count`,
`post_count`, `trig_level`, `afe_atten`, `afe_flags`, `lmh_atten`,
`dac_offset` — so the GUI confirms a command landed by watching the next
frame rather than waiting on a reply.

## Rate limiting

`SET_TIMEBASE` / `SET_HOFFSET` / `SET_TRIGGER` write FPGA registers directly
through `esp32/main/live_cfg.c` and are not rate-limited in firmware — these
are combinational register writes with no mechanical part, and the FPGA
applies them live (see `docs/PROTOCOL.md`'s "Configure + arm": no re-arm is
needed).

`SET_VERTICAL` / `SET_COUPLING` / `SET_TERM` drive `afe_set()`, which throws
mechanical relays and talks to the LMH6518 over SPI and the MCP4726 over I2C.
`esp32/main/cmd.c` coalesces these through a depth-1 queue (`xQueueOverwrite`)
so only the latest requested state survives a burst, and a dedicated task
applies at most one update every 80 ms (~12.5 Hz) — reacting immediately after
an idle period, never falling indefinitely behind during a fast drag. The GUI
also debounces slider drags client-side (`control.DebouncedSender`, 80 ms) as
a first line of defense, but the firmware floor is what actually protects the
relays regardless of what the client sends.

## Gaps: what a virtual dial cannot reproduce

`trig_src`, `trig_edge`, and `trig_hyst` are set by `SET_TRIGGER` but are
never echoed back in the sample stream (`docs/STREAM.md`'s frame layout only
carries `trig_level`), so the GUI cannot sync these three from a device it
just connected to — they start at the GUI's own defaults and track whatever
it last sent. Only `trig_level`, `dec_factor`, `pre_count`, `post_count`, and
every `SET_VERTICAL`/`SET_COUPLING`/`SET_TERM` field can be read back this
way.

The physical encoder push-buttons (`ENC_BTN`, `docs/PROTOCOL.md` 0x36) have no
emulated equivalent here — v1 control scope is the five continuous-value dials
(timebase, horizontal offset, trigger level, vertical scale, vertical offset)
plus the two toggle switches (coupling, termination), not the buttons.

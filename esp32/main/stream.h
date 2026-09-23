#pragma once

/*
 * Frozen captures -> host, over the USB-UART link.
 *
 * The ESP32 arms the FPGA, waits for a frozen record, reduces it to a fixed
 * number of {min, max} columns and writes one binary frame per capture. The
 * reduction is what keeps the link usable: a full 16384-entry record is 32 kB,
 * which at 921600 baud would cap the display at ~3 frames/s. A min/max envelope
 * over STREAM_COLS columns is 4 kB and holds ~20 frames/s while still showing
 * transients that fall between columns, which plain subsampling would drop.
 *
 * The wire format itself lives in stream_frame.h; see docs/STREAM.md.
 */

#define STREAM_COLS 1000u
#define STREAM_BAUD 921600

/* Start the capture/stream task. Call after afe_init() and fpga_link_init(). */
void stream_init(void);

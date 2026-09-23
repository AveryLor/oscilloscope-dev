#pragma once

/*
 * Host -> ESP32 control channel: reads text command lines off UART0 (the same
 * wire stream.c streams binary sample frames out on — full duplex, no
 * contention) and applies them. See docs/CONTROL.md for the wire grammar and
 * cmd_parse.h for the line parser this drives.
 *
 * FPGA-register commands (timebase/h-offset/trigger) are hot-write and go
 * straight through live_cfg.c. AFE commands (vertical/coupling/termination)
 * drive mechanical relays plus SPI/I2C, so they are coalesced and rate-limited
 * through a queue rather than applied on every line received.
 */

/* Starts the RX-parsing and AFE-apply tasks. Call after stream_init() (reuses
 * its UART0 driver install) and after afe_init()/fpga_link_init(). */
void cmd_init(void);

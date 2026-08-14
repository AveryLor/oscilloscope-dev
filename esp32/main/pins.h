#pragma once

/*
 * NodeMCU-32S GPIO map (Oscilloscope Rev 1.0).
 * Names only — no drivers yet.
 */

/* Hardware I2C: MCP4726 + trigger header J5 */
#define PIN_I2C_SDA 21
#define PIN_I2C_SCL 22

/* Shared VSPI: LMH6518 VGA + FPGA dump */
#define PIN_SPI_SCLK 18
#define PIN_SPI_MOSI 23 /* VGA SDIO (write) and FPGA MOSI */
#define PIN_SPI_MISO 19 /* FPGA only; not on Altium yet */
#define PIN_VGA_CS   27
#define PIN_FPGA_CS  5
#define PIN_FPGA_IRQ 16 /* capture-ready; not on Altium yet */

/* Analog frontend relay FETs */
#define PIN_RELAY_100X_10X  32
#define PIN_RELAY_10X_1X    33
#define PIN_RELAY_DC_COUP   25
#define PIN_RELAY_50_OHM    26

/* Vertical encoders (ESP32) */
#define PIN_DIAL_VS_A   36
#define PIN_DIAL_VS_B   39
#define PIN_DIAL_VS_BTN 34
#define PIN_DIAL_VO_A   35
#define PIN_DIAL_VO_B   13
#define PIN_DIAL_VO_BTN 14

/* J5 future trigger module */
#define PIN_ESP_FLEX_1 17
#define PIN_ESP_FLEX_2 4
#define PIN_ESP_FLEX_3 15 /* idle-high at boot */

/* Reserved: GPIO1/3 USB-UART, GPIO6–11 flash, GPIO0/2/12 strapping */

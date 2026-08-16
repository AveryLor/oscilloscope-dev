#pragma once

/*
 * ESP32 DevKit V1 (Elegoo, ESP-WROOM-32) GPIO map (Oscilloscope Rev 1.0).
 * Same GPIOs as the prior NodeMCU-32S map — see README.md for the
 * DevKit V1 silkscreen labels. Names only — no drivers yet.
 */

/* Hardware I2C: MCP4726 + trigger header J5 (VSPIHD / VSPIWP unused) */
#define PIN_I2C_SDA 21 /* P21 */
#define PIN_I2C_SCL 22 /* P22 */

/* VSPI (SPI3) IOMUX defaults: FPGA dump only (4-wire) */
#define PIN_FPGA_SCLK 18 /* P18 VSPICLK */
#define PIN_FPGA_MOSI 23 /* P23 VSPID */
#define PIN_FPGA_MISO 19 /* P19 VSPIQ; not on Altium yet */
#define PIN_FPGA_CS   5  /* P5  VSPICS0 */
#define PIN_FPGA_IRQ  16 /* P16; capture-ready; not on Altium yet */

/* HSPI (SPI2) IOMUX defaults: LMH6518 VGA only (write-oriented 3-wire).
 * GPIO12 HSPIQ unused (strapping). GPIO6–11 are flash SPI0/1. */
#define PIN_VGA_SCLK 14 /* P14 HSPICLK */
#define PIN_VGA_MOSI 13 /* P13 HSPID → LMH6518 SDIO, writes only */
#define PIN_VGA_CS   15 /* P15 HSPICS0; idle-high at boot */

/* Analog frontend relay FETs */
#define PIN_RELAY_100X_10X  32 /* P32 */
#define PIN_RELAY_10X_1X    33 /* P33 */
#define PIN_RELAY_DC_COUP   25 /* P25 */
#define PIN_RELAY_50_OHM    26 /* P26 */

/* Vertical encoders (ESP32) */
#define PIN_DIAL_VS_A   36 /* SVP */
#define PIN_DIAL_VS_B   39 /* SVN */
#define PIN_DIAL_VS_BTN 34 /* P34 */
#define PIN_DIAL_VO_A   35 /* P35 */
#define PIN_DIAL_VO_B   17 /* P17; was ESP_FLEX_1 */
#define PIN_DIAL_VO_BTN 4  /* P4; was ESP_FLEX_2; HSPIHD unused */

/* J5 future trigger module — FLEX_1/2 used for DIAL_VO_* */
#define PIN_ESP_FLEX_3 27 /* P27; not an SPI controller pin */

/* Reserved: GPIO1/3 USB-UART, GPIO6–11 flash, GPIO0/2/12 strapping */

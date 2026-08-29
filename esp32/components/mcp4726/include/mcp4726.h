#ifndef MCP4726_H
#define MCP4726_H

/*
 * MCP4726 — single-channel 12-bit I2C DAC with a configurable voltage
 * reference. On this board it sets the vertical-path offset that the LMH6518
 * front end adds to the signal.
 *
 * Two transactions are used:
 *
 *  - Fast write (command bits 00): 2 bytes, updates only the volatile DAC
 *    register and power-down bits.
 *        byte 0: 0 0 PD1 PD0 D11 D10 D9 D8   (PD = 00 => normal operation)
 *        byte 1: D7 D6 D5 D4 D3 D2 D1 D0
 *
 *  - Write volatile configuration + DAC (command bits 010): 3 bytes, also sets
 *    the reference source and output gain. Used once at init.
 *        byte 0: 0 1 0 VREF1 VREF0 PD1 PD0 G
 *        byte 1: D11..D4
 *        byte 2: D3..D0 0 0 0 0
 *
 * NOTE: the command/config bit layout above is the standard MCP4725/MCP4726
 * protocol from memory — confirm against the MCP4726 datasheet before relying
 * on the configuration path. The fast-write path is the well-worn one.
 *
 * Default 7-bit address is 0x60 (MCP4726A0).
 */

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "driver/i2c_master.h"

#ifdef __cplusplus
extern "C" {
#endif

#define MCP4726_ADDR_DEFAULT 0x60
#define MCP4726_CODE_MAX     0x0FFF
#define MCP4726_CODE_MID     0x0800

/* byte 0 bits 4..3 — reference source for "write volatile config" */
typedef enum {
    MCP4726_VREF_VDD           = 0, /* VDD, unbuffered (gain bit ignored) */
    MCP4726_VREF_PIN_UNBUFFERED = 2,
    MCP4726_VREF_PIN_BUFFERED   = 3,
} mcp4726_vref_t;

/* byte 0 bit 0 — output gain, only meaningful when VREF != VDD */
typedef enum {
    MCP4726_GAIN_1X = 0,
    MCP4726_GAIN_2X = 1,
} mcp4726_gain_t;

typedef struct {
    i2c_master_dev_handle_t dev;
} mcp4726_dev_t;

/*
 * Attach the DAC to an already-created I2C master bus. If cfg_vref/cfg_gain are
 * applied (write_config = true) the volatile configuration is written once;
 * otherwise the device keeps its EEPROM-loaded configuration.
 */
esp_err_t mcp4726_init(mcp4726_dev_t *dev, i2c_master_bus_handle_t bus,
                       uint8_t addr, bool write_config,
                       mcp4726_vref_t cfg_vref, mcp4726_gain_t cfg_gain);

/* Fast write: update the volatile 12-bit DAC output (code clamped to 0..4095). */
esp_err_t mcp4726_set_code(mcp4726_dev_t *dev, uint16_t code12);

#ifdef __cplusplus
}
#endif

#endif /* MCP4726_H */

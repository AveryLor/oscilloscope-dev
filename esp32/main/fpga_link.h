#pragma once

/*
 * Tang Nano 20K oscilloscope link (ESP32 = VSPI master, FPGA = slave).
 *
 * Wraps the SPI register protocol in scope_proto.h: bring up the bus and the
 * capture-ready interrupt, push an acquisition configuration, arm, wait for the
 * FPGA_IRQ line, and read the frozen record back as decoded samples. See
 * docs/PROTOCOL.md for the wire format.
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"
#include "scope_proto.h"

// Acquisition parameters for one capture
typedef struct {
    uint8_t  mode;          // MODE_NORMAL / MODE_AUTO / MODE_SINGLE
    bool     peak_detect;   // MODE_PEAK_EN
    uint8_t  trig_src;      // TRIGCFG_SRC_LEVEL / _EXT / _FORCE
    uint8_t  trig_edge;     // TRIGCFG_EDGE_RISING / _FALLING / _EITHER (unshifted)
    uint16_t trig_level;    // 10-bit code
    uint8_t  trig_hyst;
    uint16_t dec_factor;    // decimation - 1
    uint16_t pre_count;
    uint16_t post_count;
    uint32_t auto_timeout;  // capture ticks; 0 disables the AUTO timeout
    bool     invert_en;     // correct the swapped VIN+/VIN-
    bool     auto_rearm;
} scope_acq_cfg_t;

/* Bring up VSPI + the FPGA_IRQ interrupt. Safe to call once from app_main. */
esp_err_t fpga_link_init(void);

/* Raw register access. addr auto-increments across the burst on the FPGA side
 * (except REG_REC_DATA). len is the number of data bytes. */
esp_err_t fpga_link_write_reg(uint8_t addr, const uint8_t *data, size_t len);
esp_err_t fpga_link_read_reg(uint8_t addr, uint8_t *data, size_t len);

/* Convenience wrappers. */
esp_err_t fpga_link_write8(uint8_t addr, uint8_t value);
esp_err_t fpga_link_read8(uint8_t addr, uint8_t *value);

/* True once REG_ID0/ID1 read back 'S'/'C' and STATUS reports the PLL locked. */
bool fpga_link_present(void);

/* Serialise cfg into the FPGA registers and set CONTROL.ARM. */
esp_err_t scope_arm(const scope_acq_cfg_t *cfg);

/* Block until FPGA_IRQ asserts (or timeout_ms elapses). Returns ESP_OK when a
 * record is ready, ESP_ERR_TIMEOUT otherwise. */
esp_err_t scope_wait_ready(uint32_t timeout_ms);

/* Read the frozen record. Writes up to max_samples decoded entries into out and
 * returns the number written via *n_out; also returns the trigger sample offset
 * within the record via *trig_off (may be NULL). Acknowledges the IRQ. */
esp_err_t scope_read_record(scope_sample_t *out, size_t max_samples,
                            size_t *n_out, uint32_t *trig_off);

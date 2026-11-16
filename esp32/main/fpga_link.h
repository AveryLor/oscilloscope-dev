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

// Capture buffer depth (capture_buffer.sv DEPTH). A SAMPLE_COUNT above this
// can only come from a broken SPI link, e.g. MISO floating reads 0xFFFFFFFF.
#define SCOPE_REC_MAX_SAMPLES 16384u

// Acquisition parameters for one capture
typedef struct {
    uint8_t  mode;          // MODE_NORMAL / MODE_AUTO / MODE_SINGLE
    bool     peak_detect;   // MODE_PEAK_EN
    bool     hires;         // MODE_HIRES_EN (ignored unless CAPS_HIRES)
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

/* Serialise cfg into the FPGA registers and set CONTROL.ARM. Use once at
 * boot (or to deliberately reset every setting): it overwrites whatever the
 * FPGA knobs have done since. */
esp_err_t scope_arm(const scope_acq_cfg_t *cfg);

/* Re-arm after a dump without touching any acquisition setting: writes only
 * the CONTROL level bits (invert_en, auto_rearm) plus ARM. The FPGA registers
 * stay the single source of truth, so knob turns and the HS-button mode cycle
 * survive every capture. */
esp_err_t scope_rearm(const scope_acq_cfg_t *cfg);

/* Read the effective acquisition settings back from the FPGA (MODE through
 * POST_COUNT in one burst). Fields not held in that range keep their value. */
esp_err_t scope_read_effective(scope_acq_cfg_t *cfg);

/* Over-range protection. read: ALARM register (ALARM_OR_TRIP | ALARM_OR_ACTIVE).
 * clear: acknowledge the sticky trip. cfg: window log2 and /256 threshold. */
esp_err_t scope_alarm_read(uint8_t *alarm);

/* Block until the FPGA_ALARM line is high (or rises) or timeout_ms passes.
 * ESP_ERR_TIMEOUT if neither: callers then poll REG_ALARM as a fallback, so
 * the firmware works with or without the J4-3 -> J5-5 jumper. */
esp_err_t scope_wait_alarm(uint32_t timeout_ms);

/* Write CONTROL W1 bits (IRQ_CLR, REC_REWIND, ...) while preserving the
 * level bits last set by scope_arm / scope_rearm. Use this for every
 * one-shot CONTROL write. */
esp_err_t fpga_control_strobe(uint8_t w1_bits);
esp_err_t scope_alarm_clear(void);
esp_err_t scope_or_protect_cfg(uint8_t win_log2, uint8_t thr);

/* Block until FPGA_IRQ asserts (or timeout_ms elapses). Returns ESP_OK when a
 * record is ready, ESP_ERR_TIMEOUT otherwise. */
esp_err_t scope_wait_ready(uint32_t timeout_ms);

/* Read the frozen record. Writes up to max_samples decoded entries into out and
 * returns the number written via *n_out; also returns the trigger sample offset
 * within the record via *trig_off (may be NULL). Acknowledges the IRQ. */
esp_err_t scope_read_record(scope_sample_t *out, size_t max_samples,
                            size_t *n_out, uint32_t *trig_off);

/* Column-reduced view of one record: per column, the min and max code seen. */
typedef struct {
    uint16_t *ymin;
    uint16_t *ymax;
    size_t    n_cols;       // columns ymin/ymax point at; set by the caller
    uint32_t  sample_count; // entries in the record before reduction
    uint32_t  trig_off;     // trigger position within the record
    uint8_t   over_range;   // any sample in the record clipped
} scope_envelope_t;

/* Read the frozen record straight into a min/max envelope of n_cols columns,
 * reducing as the bytes arrive so the whole record never has to be buffered.
 * env->ymin/ymax must each hold n_cols entries. Acknowledges the IRQ. */
esp_err_t scope_read_envelope(scope_envelope_t *env, size_t n_cols);

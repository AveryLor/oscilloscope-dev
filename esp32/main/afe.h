#pragma once

/*
 * Analog front end (vertical path) coordinator.
 *
 * Owns board-level policy for one input channel and drives the three devices
 * that set vertical gain and offset:
 *   - input divider / termination / coupling relay FETs (pins.h PIN_RELAY_*)
 *   - LMH6518 DVGA over HSPI          (components/lmh6518)
 *   - MCP4726 offset DAC over I2C     (components/mcp4726)
 *
 * The LMH6518 device drivers stay register-level; this module is where a
 * requested volts/div and offset turn into concrete relay states, preamp and
 * ladder settings, and a DAC code.
 */

#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"
#include "lmh6518.h"

/* Input divider network — two relay FETs, three usable ratios. */
typedef enum {
    AFE_ATTEN_1X,
    AFE_ATTEN_10X,
    AFE_ATTEN_100X,
} afe_atten_t;

typedef struct {
    afe_atten_t      atten;       // PIN_RELAY_100X_10X / PIN_RELAY_10X_1X
    bool             dc_coupled;  // PIN_RELAY_DC_COUP  (false => AC)      
    bool             term_50r;    // PIN_RELAY_50_OHM   (false => 1 MΩ)    
    lmh6518_bw_t     bw;
    lmh6518_preamp_t preamp;
    uint8_t          lmh_atten;   // LMH6518 ladder code, 0..LMH6518_ATTEN_MAX 
    uint16_t         offset_code; // MCP4726 12-bit offset
} afe_config_t;

/*
 * Bring up the relay GPIOs, the HSPI bus + LMH6518, and the I2C bus + MCP4726,
 * then apply a safe default: maximum input attenuation, AC coupling, 1 MΩ
 * termination, LMH6518 {LG, max ladder attenuation, full bandwidth, aux on},
 * and mid-scale offset. Logs the resulting state.
 */
esp_err_t afe_init(void);

/* Apply a full front-end configuration in one call. */
esp_err_t afe_set(const afe_config_t *cfg);

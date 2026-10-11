#pragma once

/*
 * ADC capture deskew: lines up the 10 AD9215 data bits (and OR) so the FPGA
 * samples every bit mid-eye. The bits reach the FPGA on traces of different
 * lengths across three IO banks, so a single sample edge cannot suit them all.
 * The FPGA provides the controls (a PLL phase common to every lane, plus one
 * IODELAY per lane) and an eye monitor; this module sweeps them and picks the
 * settings. See docs/PROTOCOL.md "ADC deskew".
 *
 * Calibration needs a signal that toggles every bit: a sine of a few MHz
 * driven close to full scale is ideal. Too slow or too small an input leaves
 * the upper bits idle, and those lanes fall back to their neighbours' median
 * tap. Run it once per board (CALIBRATE, docs/CONTROL.md); the result is kept
 * in NVS and re-applied at every boot.
 */

#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"
#include "deskew_find.h"

typedef struct {
    uint8_t  pll_phase;              // PLL_PHASE value
    uint8_t  taps[DESKEW_LANES];     // DLY_TAP_D0..D9, DLY_TAP_OR
    uint8_t  lanes_found;            // lanes that had their own crossover
} deskew_cal_t;

/* Writes cal into the FPGA and waits for the IODELAY stepper to settle. The
 * PLL phase change resets the capture domain, so re-arm afterwards. */
esp_err_t deskew_apply(const deskew_cal_t *cal);

/* Runs the full sweep, applies the result and saves it to NVS. Takes several
 * seconds and disturbs capture throughout; the caller owns the FPGA for the
 * duration and must re-arm afterwards. Returns ESP_ERR_NOT_FOUND (with the
 * FPGA left at its power-up settings) if no phase found any lane. */
esp_err_t deskew_calibrate(deskew_cal_t *out);

/* Loads a saved calibration from NVS and applies it. ESP_ERR_NOT_FOUND if
 * none has been saved yet, in which case the FPGA stays at its defaults. */
esp_err_t deskew_load_and_apply(void);

/* Asks stream_task to run deskew_calibrate() at the top of its next loop, so
 * the calibration never races a capture. Safe from any task. */
void deskew_request(void);

/* stream_task side: true once per deskew_request(). */
bool deskew_take_request(void);

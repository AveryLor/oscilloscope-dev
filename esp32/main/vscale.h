#pragma once

/*
 * Vertical-scale ladder: one ordered list of front-end settings the
 * vertical-scale knob walks, 2 dB of total gain per step.
 *
 * Total gain = LMH6518 preamp (18.8 dB low / 38.8 dB high)
 *            - 2 dB x LMH6518 ladder code (0..10)
 *            - 20 dB x input divider (1x / 10x / 100x)
 *
 * Step 0 is the most gain (most zoomed in), step VSCALE_STEPS-1 the least:
 *
 *   steps  0.. 9   1x    high-gain preamp, ladder 0..9    38.8 .. 20.8 dB
 *   steps 10..20   1x    low-gain preamp,  ladder 0..10   18.8 .. -1.2 dB
 *   steps 21..30   10x   low-gain preamp,  ladder 1..10   -3.2 .. -21.2 dB
 *   steps 31..40   100x  low-gain preamp,  ladder 1..10  -23.2 .. -41.2 dB
 *
 * The relay divider is only brought in once the LMH6518 has run out of
 * attenuation, so the relays click exactly twice across the whole range.
 *
 * Kept free of ESP-IDF headers so it builds on a host compiler
 * (esp32/test/test_vscale.c). Field encodings match afe.h / docs/CONTROL.md:
 * atten 0 = 1x, 1 = 10x, 2 = 100x; preamp 0 = low gain, 1 = high gain.
 */

#include <stdint.h>

#define VSCALE_STEPS   41
#define VSCALE_STEP_DDB 20 /* tenths of a dB per step */

typedef struct {
    uint8_t atten;     // 0 = 1x, 1 = 10x, 2 = 100x
    uint8_t preamp;    // 0 = low gain, 1 = high gain
    uint8_t lmh_atten; // LMH6518 ladder code, 0..10
} vscale_step_t;

/* Total front-end gain of a setting, in tenths of a dB (38.8 dB -> 388). */
int vscale_gain_ddb(uint8_t atten, uint8_t preamp, uint8_t lmh_atten);

/* Ladder step whose gain is closest to the given setting. Any legal setting
 * maps to a step, including ones the ladder itself never produces (for
 * example 10x with the high-gain preamp, set from the GUI). */
int vscale_index_of(uint8_t atten, uint8_t preamp, uint8_t lmh_atten);

/* Settings for a step. index is clamped to 0..VSCALE_STEPS-1. */
vscale_step_t vscale_at(int index);

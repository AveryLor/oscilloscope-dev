#pragma once
/*
 * Vertical-scale knob (DIAL_VS_A/B, pins.h).
 *
 * Decodes the encoder with the PCNT peripheral and, for each detent, steps
 * the front-end gain one notch (2 dB) along the vscale.h ladder through
 * cmd_vscale_nudge(). Clockwise zooms in (more gain, fewer volts/div); flip
 * VKNOB_DIR in vknob.c if the wiring turns out the other way round.
 *
 * GPIO36/39 are input-only and have no internal pull-ups, so the encoder
 * relies on the pull-ups on the board.
 */
#include "esp_err.h"

/* Call after cmd_init() (it posts to cmd.c's AFE queue). */
esp_err_t vknob_init(void);

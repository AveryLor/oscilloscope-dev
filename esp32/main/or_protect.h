#pragma once
/*
 * Over-range protection task.
 *
 * Waits for the FPGA over-range alarm (an edge on PIN_FPGA_ALARM if the
 * J4-3 -> J5-5 jumper is fitted, otherwise a REG_ALARM poll every
 * OR_POLL_MS), then steps the front-end gain down one notch via
 * afe_protect_step() and acknowledges the alarm. Independent of the capture
 * loop, so it reacts even while the scope waits for a trigger.
 */
#include "esp_err.h"

esp_err_t or_protect_init(void);

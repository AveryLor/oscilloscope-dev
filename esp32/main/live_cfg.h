#pragma once

/*
 * Mutex-guarded mirror of the acquisition config currently commanded into the
 * FPGA, shared between stream.c (which reads it into every frame's metadata)
 * and cmd.c (which writes it in response to host SET_TIMEBASE / SET_HOFFSET /
 * SET_TRIGGER commands, see docs/CONTROL.md).
 *
 * Without this, a second writer of the FPGA's acquisition registers would
 * leave stream.c's local copy stale: the registers themselves are hot-write
 * (docs/PROTOCOL.md), so the FPGA already reflects the new value, but the
 * frames streamed to the host would keep echoing the old one.
 */

#include "esp_err.h"
#include "fpga_link.h"

/* Seeds the mirror and writes cfg into the FPGA via scope_arm(). Call once,
 * before stream_task's loop starts. */
esp_err_t live_cfg_init(const scope_acq_cfg_t *initial);

/* Copies the current mirror out. Safe to call from any task. */
void live_cfg_get_acq(scope_acq_cfg_t *out);

/* Each of these updates the mirror and writes the corresponding FPGA register
 * burst directly (no re-arm: the registers are hot-write). Safe to call from
 * any task. */
esp_err_t live_cfg_set_dec_factor(uint16_t dec_factor);
esp_err_t live_cfg_set_hoffset(uint16_t pre_count, uint16_t post_count);
esp_err_t live_cfg_set_trigger(uint16_t level, uint8_t src, uint8_t edge, uint8_t hyst);

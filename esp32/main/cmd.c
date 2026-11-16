#include "cmd.h"

#include "driver/uart.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include "afe.h"
#include "cmd_parse.h"
#include "live_cfg.h"
#include "vscale.h"

static const char *TAG = "cmd";

#define CMD_UART     UART_NUM_0
#define CMD_MAX_LINE 128
#define AFE_APPLY_FLOOR_MS 80 // caps relay/SPI/I2C churn at ~12.5 Hz

// The running "next AFE state to apply", mutated in place by each
// vertical/coupling/term command and by the vertical-scale knob so that
// back-to-back changes of different kinds compose instead of each one
// clobbering the others' field with a stale afe_get() snapshot. Written by
// cmd_rx_task (host commands) and the vknob task, hence s_afe_lock.
static afe_config_t      s_afe_target;
static SemaphoreHandle_t s_afe_lock;
static QueueHandle_t     s_afe_queue; // depth 1: latest-wins coalescing

static void afe_apply_task(void *arg) {
    (void)arg;
    for (;;) {
        afe_config_t cfg;
        xQueueReceive(s_afe_queue, &cfg, portMAX_DELAY);
        afe_set(&cfg);
        vTaskDelay(pdMS_TO_TICKS(AFE_APPLY_FLOOR_MS));
    }
}

static void dispatch(const cmd_t *cmd) {
    switch (cmd->kind) {
    case CMD_SET_TIMEBASE:
        (void)live_cfg_set_dec_factor(cmd->as.timebase.dec_factor);
        break;
    case CMD_SET_HOFFSET:
        (void)live_cfg_set_hoffset(cmd->as.hoffset.pre_count, cmd->as.hoffset.post_count);
        break;
    case CMD_SET_TRIGGER:
        (void)live_cfg_set_trigger(cmd->as.trigger.level, cmd->as.trigger.src,
                                   cmd->as.trigger.edge, cmd->as.trigger.hyst);
        break;
    case CMD_SET_ACQ:
        (void)live_cfg_set_acq(cmd->as.acq.mode == CMD_ACQ_PEAK,
                               cmd->as.acq.mode == CMD_ACQ_HIRES);
        break;
    case CMD_SET_VERTICAL:
        xSemaphoreTake(s_afe_lock, portMAX_DELAY);
        s_afe_target.atten       = (afe_atten_t)cmd->as.vertical.atten;
        s_afe_target.preamp      = cmd->as.vertical.preamp ? LMH6518_PREAMP_HG : LMH6518_PREAMP_LG;
        s_afe_target.lmh_atten   = cmd->as.vertical.lmh_atten;
        s_afe_target.offset_code = cmd->as.vertical.offset_code;
        xQueueOverwrite(s_afe_queue, &s_afe_target);
        xSemaphoreGive(s_afe_lock);
        break;
    case CMD_SET_COUPLING:
        xSemaphoreTake(s_afe_lock, portMAX_DELAY);
        s_afe_target.dc_coupled = cmd->as.coupling.dc_coupled;
        xQueueOverwrite(s_afe_queue, &s_afe_target);
        xSemaphoreGive(s_afe_lock);
        break;
    case CMD_SET_TERM:
        xSemaphoreTake(s_afe_lock, portMAX_DELAY);
        s_afe_target.term_50r = cmd->as.term.term_50r;
        xQueueOverwrite(s_afe_queue, &s_afe_target);
        xSemaphoreGive(s_afe_lock);
        break;
    }
}

void cmd_vscale_nudge(int detents) {
    if (detents == 0 || s_afe_queue == NULL || s_afe_lock == NULL) {
        return;
    }
    xSemaphoreTake(s_afe_lock, portMAX_DELAY);

    // Step from what the user is looking at. Normally that is the pending
    // target, so several detents inside one 80 ms apply window add up. While
    // an over-range backoff is in force the hardware sits below the target,
    // and the next afe_set() drops the backoff: stepping from the target
    // would then jump the gain back up past the level that tripped it.
    afe_config_t from = s_afe_target;
    if (afe_backoff_active()) {
        afe_get(&from);
    }
    const int index = vscale_index_of((uint8_t)from.atten,
                                      from.preamp == LMH6518_PREAMP_HG ? 1 : 0,
                                      from.lmh_atten);
    // Step 0 is the most gain, so zooming in walks towards it.
    const vscale_step_t step = vscale_at(index - detents);

    s_afe_target.atten     = (afe_atten_t)step.atten;
    s_afe_target.preamp    = step.preamp ? LMH6518_PREAMP_HG : LMH6518_PREAMP_LG;
    s_afe_target.lmh_atten = step.lmh_atten;
    xQueueOverwrite(s_afe_queue, &s_afe_target);

    xSemaphoreGive(s_afe_lock);
}

static void handle_line(const char *buf, size_t len) {
    cmd_t cmd;
    if (cmd_parse_line(buf, len, &cmd)) {
        dispatch(&cmd);
    }
    // A malformed line is dropped silently: there is no ACK channel (see
    // docs/CONTROL.md), and the next well-formed line from the GUI corrects
    // whatever state a garbled one would have set.
}

static void cmd_rx_task(void *arg) {
    (void)arg;

    static char linebuf[CMD_MAX_LINE];
    size_t line_len = 0;
    bool   dropping = false; // recovering from a line that overran the buffer

    uint8_t chunk[128];
    for (;;) {
        int n = uart_read_bytes(CMD_UART, chunk, sizeof(chunk), pdMS_TO_TICKS(50));
        for (int i = 0; i < n; i++) {
            uint8_t b = chunk[i];

            if (b == '\r') {
                continue; // stripped unconditionally, never stored
            }
            if (b == '\n') {
                if (!dropping) {
                    handle_line(linebuf, line_len);
                }
                line_len = 0;
                dropping = false;
                continue;
            }
            if (dropping) {
                continue; // discard until the next newline
            }
            if (line_len >= CMD_MAX_LINE) {
                // Torn/oversized line: give up on it rather than overrun the
                // buffer, and resync on the next newline.
                line_len = 0;
                dropping = true;
                continue;
            }
            linebuf[line_len++] = (char)b;
        }
    }
}

void cmd_init(void) {
    afe_get(&s_afe_target);

    s_afe_lock  = xSemaphoreCreateMutex();
    s_afe_queue = xQueueCreate(1, sizeof(afe_config_t));
    if (s_afe_queue == NULL || s_afe_lock == NULL) {
        ESP_LOGE(TAG, "afe queue/lock create failed");
        return;
    }

    xTaskCreate(cmd_rx_task, "cmd_rx", 3072, NULL, 4, NULL);
    xTaskCreate(afe_apply_task, "afe_apply", 4096, NULL, 3, NULL);
}

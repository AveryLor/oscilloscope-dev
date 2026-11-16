#include "vknob.h"

#include "driver/pulse_cnt.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "cmd.h"
#include "pins.h"

static const char *TAG = "vknob";

// Quadrature edges per mechanical detent. The FPGA-side knobs are the same
// part and rest with both contacts released, i.e. one full cycle per detent.
#define VKNOB_COUNTS_PER_DETENT 4
// +1: clockwise zooms in (more gain). Set to -1 if the knob feels reversed.
#define VKNOB_DIR 1
#define VKNOB_POLL_MS 10
// Contact bounce shorter than this is ignored in hardware. The ESP32 filter
// tops out at 1023 APB cycles (~12.7 us); bounce longer than that still nets
// to zero in a quadrature decoder as long as only one contact is moving.
#define VKNOB_GLITCH_NS 10000
// Counter range before the driver folds it into its accumulator. A multiple
// of VKNOB_COUNTS_PER_DETENT so folding never shifts the detent phase.
#define VKNOB_LIMIT 32000

static pcnt_unit_handle_t s_unit;

static void vknob_task(void *arg) {
    (void)arg;
    int consumed = 0; // counts already turned into detents
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(VKNOB_POLL_MS));
        int count = 0;
        if (pcnt_unit_get_count(s_unit, &count) != ESP_OK) {
            continue;
        }
        // Whole detents only; a partial turn stays in the counter until the
        // knob settles into the next detent or falls back to this one.
        const int detents = (count - consumed) / VKNOB_COUNTS_PER_DETENT;
        if (detents != 0) {
            consumed += detents * VKNOB_COUNTS_PER_DETENT;
            cmd_vscale_nudge(VKNOB_DIR * detents);
        }
    }
}

esp_err_t vknob_init(void) {
    const pcnt_unit_config_t unit_cfg = {
        .high_limit = VKNOB_LIMIT,
        .low_limit = -VKNOB_LIMIT,
        .flags.accum_count = 1, // get_count keeps counting across the limits
    };
    esp_err_t err = pcnt_new_unit(&unit_cfg, &s_unit);
    if (err != ESP_OK) {
        return err;
    }

    const pcnt_glitch_filter_config_t filter = {.max_glitch_ns = VKNOB_GLITCH_NS};
    err = pcnt_unit_set_glitch_filter(s_unit, &filter);
    if (err != ESP_OK) {
        return err;
    }

    // Standard x4 quadrature: each channel counts the other's edges, with the
    // direction given by its own level.
    const pcnt_chan_config_t cfg_a = {
        .edge_gpio_num = PIN_DIAL_VS_A,
        .level_gpio_num = PIN_DIAL_VS_B,
    };
    const pcnt_chan_config_t cfg_b = {
        .edge_gpio_num = PIN_DIAL_VS_B,
        .level_gpio_num = PIN_DIAL_VS_A,
    };
    pcnt_channel_handle_t ch_a = NULL, ch_b = NULL;
    err = pcnt_new_channel(s_unit, &cfg_a, &ch_a);
    if (err != ESP_OK) {
        return err;
    }
    err = pcnt_new_channel(s_unit, &cfg_b, &ch_b);
    if (err != ESP_OK) {
        return err;
    }
    err = pcnt_channel_set_edge_action(ch_a, PCNT_CHANNEL_EDGE_ACTION_DECREASE,
                                       PCNT_CHANNEL_EDGE_ACTION_INCREASE);
    if (err != ESP_OK) {
        return err;
    }
    err = pcnt_channel_set_level_action(ch_a, PCNT_CHANNEL_LEVEL_ACTION_KEEP,
                                        PCNT_CHANNEL_LEVEL_ACTION_INVERSE);
    if (err != ESP_OK) {
        return err;
    }
    err = pcnt_channel_set_edge_action(ch_b, PCNT_CHANNEL_EDGE_ACTION_INCREASE,
                                       PCNT_CHANNEL_EDGE_ACTION_DECREASE);
    if (err != ESP_OK) {
        return err;
    }
    err = pcnt_channel_set_level_action(ch_b, PCNT_CHANNEL_LEVEL_ACTION_KEEP,
                                        PCNT_CHANNEL_LEVEL_ACTION_INVERSE);
    if (err != ESP_OK) {
        return err;
    }

    // accum_count only compensates at limits that are also watch points.
    err = pcnt_unit_add_watch_point(s_unit, VKNOB_LIMIT);
    if (err != ESP_OK) {
        return err;
    }
    err = pcnt_unit_add_watch_point(s_unit, -VKNOB_LIMIT);
    if (err != ESP_OK) {
        return err;
    }

    err = pcnt_unit_enable(s_unit);
    if (err != ESP_OK) {
        return err;
    }
    err = pcnt_unit_clear_count(s_unit);
    if (err != ESP_OK) {
        return err;
    }
    err = pcnt_unit_start(s_unit);
    if (err != ESP_OK) {
        return err;
    }

    if (xTaskCreate(vknob_task, "vknob", 3072, NULL, 4, NULL) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    ESP_LOGI(TAG, "vertical-scale knob on GPIO%d/%d", PIN_DIAL_VS_A, PIN_DIAL_VS_B);
    return ESP_OK;
}

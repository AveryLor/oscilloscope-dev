#include "stream.h"

#include "driver/uart.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "afe.h"
#include "fpga_link.h"
#include "scope_proto.h"
#include "stream_frame.h"

static const char *TAG = "stream";

#define STREAM_UART        UART_NUM_0
#define STREAM_TX_BUF      (8 * 1024)
#define CAPTURE_TIMEOUT_MS 1000

static uint16_t s_ymin[STREAM_COLS];
static uint16_t s_ymax[STREAM_COLS];
static uint8_t  s_frame[STREAM_HDR_BYTES + STREAM_COLS * 4 + 4];

static esp_err_t stream_uart_init(void) {
    const uart_config_t cfg = {
        .baud_rate  = STREAM_BAUD,
        .data_bits  = UART_DATA_8_BITS,
        .parity     = UART_PARITY_DISABLE,
        .stop_bits  = UART_STOP_BITS_1,
        .flow_ctrl  = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    esp_err_t err = uart_driver_install(STREAM_UART, 256, STREAM_TX_BUF, 0, NULL, 0);
    if (err != ESP_OK) {
        return err;
    }
    return uart_param_config(STREAM_UART, &cfg);
}

// The front-end settings go out as-is rather than pre-combined into a gain
// figure: the LMH6518's preamp steps are 18.8/38.8 dB, which no integer dB
// field can carry without losing enough precision to skew a measurement. The
// host has the same datasheet numbers and does the arithmetic in floating point.
static uint8_t afe_flags_of(const afe_config_t *afe) {
    uint8_t v = 0;
    if (afe->dc_coupled)                  v |= STREAM_AFE_DC_COUPLED;
    if (afe->term_50r)                    v |= STREAM_AFE_TERM_50R;
    if (afe->preamp == LMH6518_PREAMP_HG) v |= STREAM_AFE_PREAMP_HG;
    return v;
}

static void stream_task(void *arg) {
    (void)arg;

    // Free-running AUTO capture: the FPGA re-arms itself after every dump, so
    // the host sees a live trace without asking for each one. The AUTO timeout
    // means an idle input still produces frames instead of waiting forever for
    // an edge that never comes.
    const scope_acq_cfg_t acq = {
        .mode         = MODE_AUTO,
        .peak_detect  = false,
        .trig_src     = TRIGCFG_SRC_LEVEL,
        .trig_edge    = TRIGCFG_EDGE_RISING,
        .trig_level   = SCOPE_CODE_MID,
        .trig_hyst    = 4,
        .dec_factor   = 0,
        .pre_count    = 1024,
        .post_count   = 1024,
        .auto_timeout = 1000000,
        .invert_en    = true,
        .auto_rearm   = true,
    };

    esp_err_t err = scope_arm(&acq);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "arm: %s", esp_err_to_name(err));
        vTaskDelete(NULL);
        return;
    }

    // Past this point the binary stream owns the wire, so text logs would land
    // in the middle of frames. The host can still resync on the magic word if
    // anything does slip through.
    esp_log_level_set("*", ESP_LOG_NONE);

    scope_envelope_t env = {
        .ymin   = s_ymin,
        .ymax   = s_ymax,
        .n_cols = STREAM_COLS,
    };
    uint32_t seq = 0;

    for (;;) {
        if (scope_wait_ready(CAPTURE_TIMEOUT_MS) != ESP_OK) {
            // No capture within the window: re-arm rather than wedging, in
            // case an IRQ edge was lost.
            (void)scope_arm(&acq);
            continue;
        }
        if (scope_read_envelope(&env, STREAM_COLS) != ESP_OK) {
            continue;
        }

        uint8_t status = 0;
        (void)fpga_link_read8(REG_STATUS, &status);

        afe_config_t afe;
        afe_get(&afe);

        stream_meta_t meta = {
            .flags         = 0,
            .seq           = seq++,
            .sample_count  = env.sample_count,
            .dec_factor    = acq.dec_factor,
            .pre_count     = acq.pre_count,
            .post_count    = acq.post_count,
            .trig_ptr      = env.trig_off,
            .trig_level    = acq.trig_level,
            .overrange_cnt = 0,
            .afe_atten     = (uint8_t)afe.atten,
            .afe_flags     = afe_flags_of(&afe),
            .lmh_atten     = afe.lmh_atten,
            .dac_offset    = afe.offset_code,
        };
        if (acq.peak_detect)             meta.flags |= STREAM_FLAG_PEAK;
        if (!(status & STAT_TRIGD_AUTO)) meta.flags |= STREAM_FLAG_TRIGGERED;
        if (env.over_range)              meta.flags |= STREAM_FLAG_OVERRANGE;

        size_t len = stream_build_frame(s_frame, sizeof(s_frame), &meta,
                                        s_ymin, s_ymax, STREAM_COLS);
        if (len > 0) {
            uart_write_bytes(STREAM_UART, (const char *)s_frame, len);
        }
    }
}

void stream_init(void) {
    esp_err_t err = stream_uart_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "uart init: %s", esp_err_to_name(err));
        return;
    }
    ESP_LOGI(TAG, "streaming %u cols at %d baud", (unsigned)STREAM_COLS, STREAM_BAUD);
    xTaskCreate(stream_task, "scope_stream", 4096, NULL, 5, NULL);
}

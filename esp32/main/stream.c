#include "stream.h"

#include "driver/uart.h"
#include "esp_rom_uart.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "afe.h"
#include "fpga_link.h"
#include "live_cfg.h"
#include "scope_proto.h"
#include "stream_frame.h"

static const char *TAG = "stream";

#define STREAM_UART        UART_NUM_0
#define STREAM_TX_BUF      (8 * 1024)
#define CAPTURE_TIMEOUT_MS 1000 // floor; scaled up with the timebase below
#define READ_RETRY_MS      100

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
    // Let the boot log drain at the console baud before switching, or its
    // tail (including fpga_link's ready line) is garbled.
    esp_rom_output_tx_wait_idle(0);
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

// How long to wait for a capture before assuming an IRQ edge was lost. A
// record takes (pre + post) x (dec + 1) sample clocks of 10 ns to fill, which
// passes the fixed floor at the slowest timebases the horizontal-scale knob
// reaches (2048 samples at /65536 is 1.34 s). Without scaling, the task would
// re-arm before every such capture finished and the trace would freeze.
// Allow twice the fill time (prefill plus the wait for a trigger) on top of
// the floor.
static uint32_t capture_timeout_ms(const scope_acq_cfg_t *acq) {
    // A record can never be longer than the buffer, whatever the registers
    // say; this also bounds the wait if a bad read returns garbage counts.
    uint32_t samples = (uint32_t)acq->pre_count + acq->post_count;
    if (samples > SCOPE_REC_MAX_SAMPLES) {
        samples = SCOPE_REC_MAX_SAMPLES;
    }
    const uint64_t fill_ns = (uint64_t)samples * ((uint64_t)acq->dec_factor + 1u) * 10u;
    return CAPTURE_TIMEOUT_MS + (uint32_t)(2u * fill_ns / 1000000u);
}

static void stream_task(void *arg) {
    (void)arg;

    // Free-running AUTO capture: this task re-arms after every dump, so the
    // host sees a live trace without asking for each one. The AUTO timeout
    // means an idle input still produces frames instead of waiting forever for
    // an edge that never comes. FPGA auto-rearm stays off: its rearm handshake
    // loops straight back in top.sv, so the buffer restarts (rec_count -> 0)
    // a few clocks after freezing, long before the ESP32 can read the record.
    const scope_acq_cfg_t initial = {
        .mode         = MODE_AUTO,
        .peak_detect  = false,
        .hires        = false,
        .trig_src     = TRIGCFG_SRC_LEVEL,
        .trig_edge    = TRIGCFG_EDGE_RISING,
        .trig_level   = SCOPE_CODE_MID,
        .trig_hyst    = 4,
        .dec_factor   = 0,
        .pre_count    = 1024,
        .post_count   = 1024,
        .auto_timeout = 1000000,
        .invert_en    = true,
        .auto_rearm   = false,
    };

    // live_cfg owns the shared mirror of this config from here on: stream.c
    // reads it every loop iteration below, and cmd.c's SET_TIMEBASE /
    // SET_HOFFSET / SET_TRIGGER handlers write it live (see live_cfg.h).
    esp_err_t err = live_cfg_init(&initial);
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
    // Settings the FPGA is capturing with, refreshed from its registers every
    // loop so a knob turn is picked up even when no capture completes.
    scope_acq_cfg_t effective = initial;

    for (;;) {
        if (scope_wait_ready(capture_timeout_ms(&effective)) != ESP_OK) {
            // Pick up a timebase change made while we were waiting, so the
            // next wait is sized for it.
            (void)scope_read_effective(&effective);
            // No capture within the window: re-arm rather than wedging, in
            // case an IRQ edge was lost. Re-read live_cfg first so the re-arm
            // re-applies whatever the host most recently commanded instead of
            // reverting to the boot-time defaults.
            // Only the ARM strobe and CONTROL level bits are written: every
            // acquisition setting already lives in the FPGA registers.
            scope_acq_cfg_t acq;
            live_cfg_get_acq(&acq);
            (void)scope_rearm(&acq);
            continue;
        }
        if (scope_read_envelope(&env, STREAM_COLS) != ESP_OK) {
            // A dead link reads STATUS as all ones, so scope_wait_ready passes
            // instantly every time; sleep so this loop can't starve IDLE.
            vTaskDelay(pdMS_TO_TICKS(READ_RETRY_MS));
            continue;
        }

        scope_acq_cfg_t acq;
        live_cfg_get_acq(&acq);
        // The FPGA owns the effective settings (host writes, knobs and the
        // HS-button mode cycle all land there), so report those, not the
        // ESP32's mirror of the last host command.
        (void)scope_read_effective(&acq);
        effective = acq;

        // STATUS describes the frozen record, so read it before re-arming.
        uint8_t status = 0;
        (void)fpga_link_read8(REG_STATUS, &status);
        (void)scope_rearm(&acq);


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
        if (acq.hires)                   meta.flags |= STREAM_FLAG_HIRES;
        if (afe_backoff_active())        meta.flags |= STREAM_FLAG_GAIN_REDUCED;
        if (!(status & STAT_TRIGD_AUTO)) meta.flags |= STREAM_FLAG_TRIGGERED;
        if (env.over_range)              meta.flags |= STREAM_FLAG_OVERRANGE;

        size_t len = stream_build_frame(s_frame, sizeof(s_frame), &meta,
                                        s_ymin, s_ymax, STREAM_COLS);
        if (len > 0) {
            // Captures can arrive faster than 921600 baud drains them. Once the
            // TX ring buffer is full, uart_write_bytes busy-spins instead of
            // blocking, starving IDLE until the task WDT fires and prints its
            // backtrace straight into the middle of a frame. Blocking here
            // until the previous frame is out keeps the CPU free and means the
            // next capture is read fresh rather than queued stale.
            uart_wait_tx_done(STREAM_UART, portMAX_DELAY);
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

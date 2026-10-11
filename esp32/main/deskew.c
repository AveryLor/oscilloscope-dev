#include "deskew.h"

#include <stdatomic.h>
#include <string.h>

#include "esp_log.h"
#include "esp_rom_sys.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"

#include "fpga_link.h"
#include "scope_proto.h"

static const char *TAG = "deskew";

#define CHK(x) do { esp_err_t _e = (x); if (_e != ESP_OK) return _e; } while (0)

#define COARSE_STEP   4u
#define COARSE_N      (DESKEW_TAPS / COARSE_STEP)
#define FINE_SPAN     4                 // refine +/- this many taps, step 1
#define FINE_N        (2 * FINE_SPAN + 1)
#define MIN_ACTIVITY  64u               // edges per window to trust a point
#define EYE_WINDOW_US 625u              // 65536 cycles at 105 MHz
#define POLL_US       25u
#define POLL_LIMIT    80
#define PHASE_SETTLE_MS 20              // capture-domain reset + PLL settle

#define NVS_NS   "deskew"
#define NVS_KEY  "cal"
#define NVS_VER  1u

typedef struct {
    uint8_t ver;
    uint8_t pll_phase;
    uint8_t taps[DESKEW_LANES];
} deskew_blob_t;

static atomic_bool s_request;

// Sweep scratch. Static: too big for a task stack, and only one calibration
// ever runs at a time (stream_task owns it).
static uint16_t s_a[DESKEW_LANES][COARSE_N];
static uint16_t s_b[DESKEW_LANES][COARSE_N];
static int16_t  s_xover[DESKEW_PHASES][DESKEW_LANES];

// ---- FPGA access -----------------------------------------------------------

static esp_err_t wait_stepper(void) {
    // The write reaches the stepper through the SPI->HK FIFO; give it a moment
    // to raise busy before the first poll can read a stale idle.
    esp_rom_delay_us(POLL_US);
    for (int i = 0; i < POLL_LIMIT; i++) {
        uint8_t st = 0;
        CHK(fpga_link_read8(REG_DESKEW_STATUS, &st));
        if (!(st & DSKST_BUSY)) {
            return ESP_OK;
        }
        esp_rom_delay_us(POLL_US);
    }
    return ESP_ERR_TIMEOUT;
}

static esp_err_t set_all_taps(const uint8_t taps[DESKEW_LANES]) {
    CHK(fpga_link_write_reg(REG_DLY_TAP_D0, taps, DESKEW_LANES));
    return wait_stepper();
}

static esp_err_t set_lane_tap(unsigned lane, uint8_t tap) {
    CHK(fpga_link_write8((uint8_t)(REG_DLY_TAP_D0 + lane), tap & DLY_TAP_MASK));
    return wait_stepper();
}

static esp_err_t set_phase(uint8_t phase) {
    CHK(fpga_link_write8(REG_PLL_PHASE, phase & PLL_PHASE_MASK));
    vTaskDelay(pdMS_TO_TICKS(PHASE_SETTLE_MS));
    uint8_t st = 0;
    CHK(fpga_link_read8(REG_STATUS, &st));
    return (st & STAT_PLL_LOCK) ? ESP_OK : ESP_ERR_INVALID_STATE;
}

static esp_err_t measure(unsigned lane, uint16_t *a, uint16_t *b) {
    CHK(fpga_link_write8(REG_EYE_CTL, (uint8_t)((lane & EYECTL_SEL_MASK) | EYECTL_START)));
    esp_rom_delay_us(EYE_WINDOW_US);
    for (int i = 0; i < POLL_LIMIT; i++) {
        uint8_t st = 0;
        CHK(fpga_link_read8(REG_DESKEW_STATUS, &st));
        if (st & DSKST_EYE_DONE) {
            uint8_t c[4];
            CHK(fpga_link_read_reg(REG_EYE_A_L, c, sizeof(c)));
            *a = (uint16_t)(c[0] | (c[1] << 8));
            *b = (uint16_t)(c[2] | (c[3] << 8));
            return ESP_OK;
        }
        esp_rom_delay_us(POLL_US);
    }
    return ESP_ERR_TIMEOUT;
}

// ---- NVS -------------------------------------------------------------------

static esp_err_t save(const deskew_cal_t *cal) {
    deskew_blob_t blob = { .ver = NVS_VER, .pll_phase = cal->pll_phase };
    memcpy(blob.taps, cal->taps, sizeof(blob.taps));

    nvs_handle_t h;
    CHK(nvs_open(NVS_NS, NVS_READWRITE, &h));
    esp_err_t err = nvs_set_blob(h, NVS_KEY, &blob, sizeof(blob));
    if (err == ESP_OK) {
        err = nvs_commit(h);
    }
    nvs_close(h);
    return err;
}

// ---- Public ----------------------------------------------------------------

esp_err_t deskew_apply(const deskew_cal_t *cal) {
    CHK(set_all_taps(cal->taps));
    return set_phase(cal->pll_phase);
}

esp_err_t deskew_load_and_apply(void) {
    nvs_handle_t h;
    esp_err_t err = nvs_open(NVS_NS, NVS_READONLY, &h);
    if (err != ESP_OK) {
        return ESP_ERR_NOT_FOUND;   // namespace never written
    }
    deskew_blob_t blob;
    size_t len = sizeof(blob);
    err = nvs_get_blob(h, NVS_KEY, &blob, &len);
    nvs_close(h);
    if (err != ESP_OK || len != sizeof(blob) || blob.ver != NVS_VER) {
        return ESP_ERR_NOT_FOUND;
    }

    deskew_cal_t cal = { .pll_phase = blob.pll_phase };
    memcpy(cal.taps, blob.taps, sizeof(cal.taps));
    err = deskew_apply(&cal);
    ESP_LOGI(TAG, "applied saved calibration: phase %u (%s)", cal.pll_phase,
             esp_err_to_name(err));
    return err;
}

esp_err_t deskew_calibrate(deskew_cal_t *out) {
    uint8_t coarse_taps[COARSE_N];
    for (unsigned i = 0; i < COARSE_N; i++) {
        coarse_taps[i] = (uint8_t)(i * COARSE_STEP);
    }
    uint8_t active[DESKEW_LANES] = {0};

    // 1. Coarse sweep: every phase, every lane, taps 0..124 in steps of 4.
    //    All lanes move together; the eye monitor measures one lane at a time.
    for (unsigned p = 0; p < DESKEW_PHASES; p++) {
        CHK(set_phase((uint8_t)p));
        for (unsigned ti = 0; ti < COARSE_N; ti++) {
            uint8_t taps[DESKEW_LANES];
            memset(taps, coarse_taps[ti], sizeof(taps));
            CHK(set_all_taps(taps));
            for (unsigned l = 0; l < DESKEW_LANES; l++) {
                CHK(measure(l, &s_a[l][ti], &s_b[l][ti]));
                if ((uint32_t)s_a[l][ti] + s_b[l][ti] >= MIN_ACTIVITY) {
                    active[l] = 1;
                }
            }
            // The measurements busy-wait; yield a tick per step so the idle
            // task (and its watchdog) still runs over the ~10 s sweep.
            vTaskDelay(1);
        }
        for (unsigned l = 0; l < DESKEW_LANES; l++) {
            s_xover[p][l] = (int16_t)deskew_find_crossover(s_a[l], s_b[l], coarse_taps,
                                                           COARSE_N, MIN_ACTIVITY);
        }
    }

    const int best = deskew_pick_phase(s_xover, active);
    if (best == DESKEW_NONE) {
        ESP_LOGW(TAG, "no lane found an eye; is a busy full-scale signal applied?");
        const deskew_cal_t dflt = { .pll_phase = PLL_PHASE_DEFAULT };
        (void)deskew_apply(&dflt);
        return ESP_ERR_NOT_FOUND;
    }

    // 2. Fine sweep at the chosen phase: +/- FINE_SPAN taps, step 1, per lane.
    CHK(set_phase((uint8_t)best));
    int16_t xover[DESKEW_LANES];
    for (unsigned l = 0; l < DESKEW_LANES; l++) {
        xover[l] = active[l] ? s_xover[best][l] : (int16_t)DESKEW_NONE;
        if (xover[l] == DESKEW_NONE) {
            continue;
        }
        uint16_t fa[FINE_N], fb[FINE_N];
        uint8_t  ft[FINE_N];
        unsigned n = 0;
        for (int t = xover[l] - FINE_SPAN; t <= xover[l] + FINE_SPAN; t++) {
            if (t < 0 || t >= (int)DESKEW_TAPS) {
                continue;
            }
            ft[n] = (uint8_t)t;
            CHK(set_lane_tap(l, ft[n]));
            CHK(measure(l, &fa[n], &fb[n]));
            n++;
        }
        const int fine = deskew_find_crossover(fa, fb, ft, n, MIN_ACTIVITY);
        if (fine != DESKEW_NONE) {
            xover[l] = (int16_t)fine;
        }
    }

    deskew_cal_t cal = { .pll_phase = (uint8_t)best };
    cal.lanes_found = (uint8_t)deskew_fill_taps(xover, cal.taps);
    CHK(deskew_apply(&cal));

    unsigned n_active = 0;
    for (unsigned l = 0; l < DESKEW_LANES; l++) n_active += active[l];
    ESP_LOGI(TAG, "phase %d, %u/%u active lanes found an eye", best,
             cal.lanes_found, n_active);
    for (unsigned l = 0; l < DESKEW_LANES; l++) {
        ESP_LOGI(TAG, "  lane %u tap %u%s", l, cal.taps[l],
                 xover[l] == DESKEW_NONE ? " (median fill)" : "");
    }

    esp_err_t err = save(&cal);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "save to NVS failed: %s", esp_err_to_name(err));
    }
    if (out) {
        *out = cal;
    }
    return ESP_OK;
}

void deskew_request(void) {
    atomic_store(&s_request, true);
}

bool deskew_take_request(void) {
    return atomic_exchange(&s_request, false);
}

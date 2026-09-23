#include "live_cfg.h"

#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#include "scope_proto.h"

static scope_acq_cfg_t  s_cfg;
static SemaphoreHandle_t s_lock;

esp_err_t live_cfg_init(const scope_acq_cfg_t *initial) {
    s_lock = xSemaphoreCreateMutex();
    if (s_lock == NULL) {
        return ESP_ERR_NO_MEM;
    }
    s_cfg = *initial;
    return scope_arm(&s_cfg);
}

void live_cfg_get_acq(scope_acq_cfg_t *out) {
    xSemaphoreTake(s_lock, portMAX_DELAY);
    *out = s_cfg;
    xSemaphoreGive(s_lock);
}

esp_err_t live_cfg_set_dec_factor(uint16_t dec_factor) {
    uint8_t burst[2] = {
        (uint8_t)(dec_factor & 0xFFu),
        (uint8_t)(dec_factor >> 8),
    };
    esp_err_t err = fpga_link_write_reg(REG_DEC_FACTOR_L, burst, sizeof(burst));
    if (err != ESP_OK) {
        return err;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_cfg.dec_factor = dec_factor;
    xSemaphoreGive(s_lock);
    return ESP_OK;
}

esp_err_t live_cfg_set_hoffset(uint16_t pre_count, uint16_t post_count) {
    // REG_PRE_COUNT_L..REG_POST_COUNT_H (0x14..0x17) is one contiguous burst.
    uint8_t burst[4] = {
        (uint8_t)(pre_count & 0xFFu),
        (uint8_t)(pre_count >> 8),
        (uint8_t)(post_count & 0xFFu),
        (uint8_t)(post_count >> 8),
    };
    esp_err_t err = fpga_link_write_reg(REG_PRE_COUNT_L, burst, sizeof(burst));
    if (err != ESP_OK) {
        return err;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_cfg.pre_count  = pre_count;
    s_cfg.post_count = post_count;
    xSemaphoreGive(s_lock);
    return ESP_OK;
}

esp_err_t live_cfg_set_trigger(uint16_t level, uint8_t src, uint8_t edge, uint8_t hyst) {
    uint8_t trig_cfg = (uint8_t)((src & TRIGCFG_SRC_MASK) |
                                 ((edge << TRIGCFG_EDGE_SHIFT) & TRIGCFG_EDGE_MASK));
    esp_err_t err = fpga_link_write8(REG_TRIG_CFG, trig_cfg);
    if (err != ESP_OK) {
        return err;
    }

    // REG_TRIG_LEVEL_L..REG_TRIG_HYST (0x0C..0x0E) is one contiguous burst.
    uint8_t burst[3] = {
        (uint8_t)(level & 0xFFu),
        (uint8_t)(level >> 8),
        hyst,
    };
    err = fpga_link_write_reg(REG_TRIG_LEVEL_L, burst, sizeof(burst));
    if (err != ESP_OK) {
        return err;
    }

    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_cfg.trig_level = level;
    s_cfg.trig_src   = src;
    s_cfg.trig_edge  = edge;
    s_cfg.trig_hyst  = hyst;
    xSemaphoreGive(s_lock);
    return ESP_OK;
}

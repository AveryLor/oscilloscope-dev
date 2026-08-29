#include "afe.h"
#include "driver/gpio.h"
#include "driver/spi_master.h"
#include "driver/i2c_master.h"
#include "esp_log.h"
#include "pins.h"
#include "mcp4726.h"

static const char *TAG = "afe";

#define AFE_SPI_HOST SPI2_HOST // HSPI — see pins.h 

static lmh6518_dev_t s_vga;
static mcp4726_dev_t s_dac;
static i2c_master_bus_handle_t s_i2c;

// Safe power-on state: smallest signal reaches the ADC, nothing gets clamped. 
static const afe_config_t k_default = {
    .atten       = AFE_ATTEN_100X,
    .dc_coupled  = false,
    .term_50r    = false,
    .bw          = LMH6518_BW_FULL,
    .preamp      = LMH6518_PREAMP_LG,
    .lmh_atten   = LMH6518_ATTEN_MAX,
    .offset_code = MCP4726_CODE_MID,
};

/*
 * Divider-relay truth table. Polarity and the exact two-line encoding are a
 * guess pending the schematic — TODO: confirm PIN_RELAY_100X_10X /
 * PIN_RELAY_10X_1X active levels and the 1x/10x/100x mapping.
 */
static void afe_apply_atten(afe_atten_t a) {
    int sel_100x = (a == AFE_ATTEN_100X);
    int sel_10x  = (a == AFE_ATTEN_10X);
    gpio_set_level(PIN_RELAY_100X_10X, sel_100x);
    gpio_set_level(PIN_RELAY_10X_1X, sel_10x);
}

static esp_err_t afe_gpio_init(void) {
    const gpio_config_t io = {
        .pin_bit_mask = (1ULL << PIN_RELAY_100X_10X) |
                        (1ULL << PIN_RELAY_10X_1X) |
                        (1ULL << PIN_RELAY_DC_COUP) |
                        (1ULL << PIN_RELAY_50_OHM),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    return gpio_config(&io);
}

static esp_err_t afe_spi_init(void) {
    const spi_bus_config_t bus = {
        .mosi_io_num = PIN_VGA_MOSI,
        .sclk_io_num = PIN_VGA_SCLK,
        .miso_io_num = -1, // LMH6518 readback not wired 
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = 4,
    };
    esp_err_t err = spi_bus_initialize(AFE_SPI_HOST, &bus, SPI_DMA_DISABLED);
    if (err != ESP_OK) {
        return err;
    }
    return lmh6518_init(&s_vga, AFE_SPI_HOST, PIN_VGA_CS);
}

static esp_err_t afe_i2c_init(void) {
    const i2c_master_bus_config_t bus = {
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .i2c_port = I2C_NUM_0,
        .sda_io_num = PIN_I2C_SDA,
        .scl_io_num = PIN_I2C_SCL,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    esp_err_t err = i2c_new_master_bus(&bus, &s_i2c);
    if (err != ESP_OK) {
        return err;
    }
    return mcp4726_init(&s_dac, s_i2c, MCP4726_ADDR_DEFAULT,
                        true, MCP4726_VREF_VDD, MCP4726_GAIN_1X);
}

esp_err_t afe_set(const afe_config_t *cfg) {
    if (cfg == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    afe_apply_atten(cfg->atten);
    gpio_set_level(PIN_RELAY_DC_COUP, cfg->dc_coupled);
    gpio_set_level(PIN_RELAY_50_OHM, cfg->term_50r);

    const lmh6518_state_t vga = {
        .preamp = cfg->preamp,
        .atten  = cfg->lmh_atten,
        .bw     = cfg->bw,
        .aux    = LMH6518_AUX_ON,
    };
    esp_err_t err = lmh6518_set_state(&s_vga, &vga);
    if (err != ESP_OK) {
        return err;
    }

    return mcp4726_set_code(&s_dac, cfg->offset_code);
}

esp_err_t afe_init(void) {
    esp_err_t err = afe_gpio_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "gpio init: %s", esp_err_to_name(err));
        return err;
    }
    err = afe_spi_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "spi/lmh6518 init: %s", esp_err_to_name(err));
        return err;
    }
    err = afe_i2c_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "i2c/mcp4726 init: %s", esp_err_to_name(err));
        return err;
    }

    err = afe_set(&k_default);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "apply default: %s", esp_err_to_name(err));
        return err;
    }

    ESP_LOGI(TAG,
             "ready: atten=100x coupling=AC term=1M lmh={LG,ladder=%d,BW_full} offset=0x%03x",
             LMH6518_ATTEN_MAX, MCP4726_CODE_MID);
    return ESP_OK;
}

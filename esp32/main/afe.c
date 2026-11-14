#include "afe.h"
#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "driver/spi_master.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "mcp4726.h"
#include "pins.h"

static const char *TAG = "afe";

#define AFE_SPI_HOST SPI2_HOST // HSPI — see pins.h

static lmh6518_dev_t s_vga;
static mcp4726_dev_t s_dac;
static i2c_master_bus_handle_t s_i2c;

// Safe power-on state: smallest signal reaches the ADC, nothing gets clamped.
static const afe_config_t k_default = {
    .atten = AFE_ATTEN_100X,
    .dc_coupled = false,
    .term_50r = false,
    .bw = LMH6518_BW_FULL,
    .preamp = LMH6518_PREAMP_LG,
    .lmh_atten = LMH6518_ATTEN_MAX,
    .offset_code = MCP4726_CODE_MID,
};

/*
 * Divider-relay truth table. Polarity and the exact two-line encoding are a
 * guess pending the schematic — TODO: confirm PIN_RELAY_100X_10X /
 * PIN_RELAY_10X_1X active levels and the 1x/10x/100x mapping.
 */
// Effective configuration actually applied to the hardware (request + pins +
// over-range backoff); reported in the sample stream so the host can turn ADC
// codes into volts.
static afe_config_t s_cfg;

// Last configuration requested through afe_set (by the host or at boot).
static afe_config_t s_req;

// Over-range protection backoff, layered on top of s_req. Cleared by the
// next afe_set, i.e. by any deliberate vertical change from the user.
static bool    s_bo_force_lg;  // preamp forced to low gain
static uint8_t s_bo_ladder;    // extra LMH6518 ladder steps (2 dB each)
static uint8_t s_bo_atten;     // extra input-divider steps (x10 each)

// afe_set (command task) and afe_protect_step (stream task) both drive the
// relays, SPI and I2C devices.
static SemaphoreHandle_t s_lock;

// Roughly 0db?
#define AFE_VGA_UNITY_PREAMP LMH6518_PREAMP_LG
#define AFE_VGA_UNITY_LADDER 9

// Pin the offset DAC at half scale (VDD/2), ignoring host offset commands
#define AFE_DAC_FIXED_CODE MCP4726_CODE_MID

// Just dissable all IO inits for relays
#define AFE_RELAYS_ENABLED 0

void afe_get(afe_config_t *out) {
  xSemaphoreTake(s_lock, portMAX_DELAY);
  *out = s_cfg;
  xSemaphoreGive(s_lock);
}

#if AFE_RELAYS_ENABLED
static void afe_apply_atten(afe_atten_t a) {
  int sel_100x = (a == AFE_ATTEN_100X);
  int sel_10x = (a == AFE_ATTEN_10X);
  gpio_set_level(PIN_RELAY_100X_10X, sel_100x);
  gpio_set_level(PIN_RELAY_10X_1X, sel_10x);
}

static esp_err_t afe_gpio_init(void) {
  const gpio_config_t io = {
      .pin_bit_mask = (1ULL << PIN_RELAY_100X_10X) |
                      (1ULL << PIN_RELAY_10X_1X) | (1ULL << PIN_RELAY_DC_COUP) |
                      (1ULL << PIN_RELAY_50_OHM),
      .mode = GPIO_MODE_OUTPUT,
      .pull_up_en = GPIO_PULLUP_DISABLE,
      .pull_down_en = GPIO_PULLDOWN_DISABLE,
      .intr_type = GPIO_INTR_DISABLE,
  };
  return gpio_config(&io);
}
#endif

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
  return mcp4726_init(&s_dac, s_i2c, MCP4726_ADDR_DEFAULT, true,
                      MCP4726_VREF_PIN_BUFFERED, MCP4726_GAIN_1X);
}

// Requested config with the bring-up pins applied, before any backoff.
static afe_config_t afe_base_locked(void) {
  afe_config_t b = s_req;
  b.preamp = AFE_VGA_UNITY_PREAMP;
  b.lmh_atten = AFE_VGA_UNITY_LADDER;
  b.offset_code = AFE_DAC_FIXED_CODE;
  return b;
}

// Base config plus the protection backoff: what the hardware should be.
static afe_config_t afe_effective_locked(void) {
  afe_config_t e = afe_base_locked();
  if (s_bo_force_lg) {
    e.preamp = LMH6518_PREAMP_LG;
  }
  unsigned ladder = (unsigned)e.lmh_atten + s_bo_ladder;
  e.lmh_atten = (uint8_t)(ladder > LMH6518_ATTEN_MAX ? LMH6518_ATTEN_MAX : ladder);
  unsigned atten = (unsigned)e.atten + s_bo_atten;
  e.atten = (afe_atten_t)(atten > AFE_ATTEN_100X ? AFE_ATTEN_100X : atten);
  return e;
}

static esp_err_t afe_apply_locked(void) {
  const afe_config_t e = afe_effective_locked();
  s_cfg = e;
#if AFE_RELAYS_ENABLED
  afe_apply_atten(e.atten);
  gpio_set_level(PIN_RELAY_DC_COUP, e.dc_coupled);
  gpio_set_level(PIN_RELAY_50_OHM, e.term_50r);
#endif

  const lmh6518_state_t vga = {
      .preamp = e.preamp,
      .atten = e.lmh_atten,
      .bw = e.bw,
      .aux = LMH6518_AUX_ON,
  };
  esp_err_t err = lmh6518_set_state(&s_vga, &vga);
  if (err != ESP_OK) {
    return err;
  }

  return mcp4726_set_code(&s_dac, e.offset_code);
}

esp_err_t afe_set(const afe_config_t *cfg) {
  if (cfg == NULL) {
    return ESP_ERR_INVALID_ARG;
  }
  xSemaphoreTake(s_lock, portMAX_DELAY);
  s_req = *cfg;
  // A deliberate vertical change from the user supersedes any automatic
  // backoff: they are choosing the range now.
  s_bo_force_lg = false;
  s_bo_ladder = 0;
  s_bo_atten = 0;
  esp_err_t err = afe_apply_locked();
  xSemaphoreGive(s_lock);
  return err;
}

/*
 * One step of over-range protection, cheapest-to-undo first:
 *   1. high-gain preamp -> low-gain (-20 dB)
 *   2. one more LMH6518 ladder step (-2 dB) until the ladder is at maximum
 *   3. one more input-divider step (x10) until 100x, if the relays are enabled
 * Returns ESP_ERR_NOT_FOUND when every stage is already at minimum gain.
 */
esp_err_t afe_protect_step(void) {
  xSemaphoreTake(s_lock, portMAX_DELAY);
  const afe_config_t e = afe_effective_locked();
  esp_err_t err = ESP_OK;
  if (e.preamp == LMH6518_PREAMP_HG) {
    s_bo_force_lg = true;
  } else if (e.lmh_atten < LMH6518_ATTEN_MAX) {
    s_bo_ladder++;
  } else if (AFE_RELAYS_ENABLED && e.atten < AFE_ATTEN_100X) {
    s_bo_atten++;
  } else {
    err = ESP_ERR_NOT_FOUND;
  }
  if (err == ESP_OK) {
    err = afe_apply_locked();
  }
  xSemaphoreGive(s_lock);
  return err;
}

bool afe_backoff_active(void) {
  xSemaphoreTake(s_lock, portMAX_DELAY);
  const bool active = s_bo_force_lg || s_bo_ladder != 0 || s_bo_atten != 0;
  xSemaphoreGive(s_lock);
  return active;
}

esp_err_t afe_init(void) {
  esp_err_t err;
  s_lock = xSemaphoreCreateMutex();
  if (s_lock == NULL) {
    return ESP_ERR_NO_MEM;
  }
#if AFE_RELAYS_ENABLED
  err = afe_gpio_init();
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "gpio init: %s", esp_err_to_name(err));
    return err;
  }
#endif
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

  ESP_LOGI(TAG, "ready: relays=%s lmh={LG,ladder=%d,BW_full} offset=0x%03x",
           AFE_RELAYS_ENABLED ? "100x/AC/1M" : "untouched", s_cfg.lmh_atten,
           MCP4726_CODE_MID);
  return ESP_OK;
}

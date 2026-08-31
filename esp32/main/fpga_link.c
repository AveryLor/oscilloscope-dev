#include "fpga_link.h"
#include <string.h>
#include "driver/gpio.h"
#include "driver/spi_master.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "esp_log.h"
#include "pins.h"

static const char *TAG = "fpga_link";

#define FPGA_SPI_HOST SPI3_HOST          // VSPI — see pins.h
#define FPGA_SPI_HZ   (20 * 1000 * 1000) // <= timing.sdc spi_sclk (40 MHz ceiling)
#define REC_BYTES_PER_SAMPLE 2
#define FPGA_LINK_MAX_DATA   512         // data bytes per register burst

#define CHK(x) do { esp_err_t _e = (x); if (_e != ESP_OK) return _e; } while (0)

static spi_device_handle_t s_spi;
static SemaphoreHandle_t   s_irq_sem;
static bool                s_ready; 

// Capture-ready edge from the FPGA. The line is held high until acknowledged
static void IRAM_ATTR fpga_irq_isr(void *arg) {
    (void)arg;
    BaseType_t hp = pdFALSE;
    xSemaphoreGiveFromISR(s_irq_sem, &hp);
    if (hp) {
        portYIELD_FROM_ISR();
    }
}

static esp_err_t fpga_link_spi_init(void) {
    const spi_bus_config_t bus = {
        .mosi_io_num     = PIN_FPGA_MOSI,
        .miso_io_num     = PIN_FPGA_MISO,
        .sclk_io_num     = PIN_FPGA_SCLK,
        .quadwp_io_num   = -1,
        .quadhd_io_num   = -1,
        .max_transfer_sz = 4096,
    };
    esp_err_t err = spi_bus_initialize(FPGA_SPI_HOST, &bus, SPI_DMA_CH_AUTO);
    if (err != ESP_OK) {
        return err;
    }

    const spi_device_interface_config_t dev = {
        .mode           = 0, // CPOL = 0, CPHA = 0
        .clock_speed_hz = FPGA_SPI_HZ,
        .spics_io_num   = PIN_FPGA_CS,  // driver owns CS, idle high
        .queue_size     = 2,
        .command_bits   = 0,
        .address_bits   = 0,
    };
    return spi_bus_add_device(FPGA_SPI_HOST, &dev, &s_spi);
}

static esp_err_t fpga_link_irq_init(void) {
    s_irq_sem = xSemaphoreCreateBinary();
    if (s_irq_sem == NULL) {
        return ESP_ERR_NO_MEM;
    }

    const gpio_config_t io = {
        .pin_bit_mask = (1ULL << PIN_FPGA_IRQ),
        .mode         = GPIO_MODE_INPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_ENABLE,   // idle-low if the FPGA is absent
        .intr_type    = GPIO_INTR_POSEDGE,
    };
    esp_err_t err = gpio_config(&io);
    if (err != ESP_OK) {
        return err;
    }

    err = gpio_install_isr_service(0);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return err;   // INVALID_STATE = another driver already installed it
    }
    return gpio_isr_handler_add(PIN_FPGA_IRQ, fpga_irq_isr, NULL);
}

esp_err_t fpga_link_write_reg(uint8_t addr, const uint8_t *data, size_t len) {
    if ((len > 0 && data == NULL) || len > FPGA_LINK_MAX_DATA) {
        return ESP_ERR_INVALID_ARG;
    }
    uint8_t buf[1 + FPGA_LINK_MAX_DATA];
    buf[0] = SCOPE_HDR_WRITE(addr);
    if (len) {
        memcpy(&buf[1], data, len);
    }

    spi_transaction_t t;
    memset(&t, 0, sizeof(t));
    t.length    = 8 * (1 + len);
    t.tx_buffer = buf;
    return spi_device_polling_transmit(s_spi, &t);
}

esp_err_t fpga_link_read_reg(uint8_t addr, uint8_t *data, size_t len) {
    if (len == 0 || data == NULL || len > FPGA_LINK_MAX_DATA) {
        return ESP_ERR_INVALID_ARG;
    }
    // Frame: header, one turnaround byte, then len data bytes.
    const size_t total = 2 + len;
    uint8_t tx[2 + FPGA_LINK_MAX_DATA];
    uint8_t rx[2 + FPGA_LINK_MAX_DATA];
    memset(tx, 0, total);
    tx[0] = SCOPE_HDR_READ(addr);

    spi_transaction_t t;
    memset(&t, 0, sizeof(t));
    t.length    = 8 * total;
    t.rxlength  = 8 * total;
    t.tx_buffer = tx;
    t.rx_buffer = rx;
    esp_err_t err = spi_device_polling_transmit(s_spi, &t);
    if (err != ESP_OK) {
        return err;
    }
    memcpy(data, &rx[2], len);
    return ESP_OK;
}

esp_err_t fpga_link_write8(uint8_t addr, uint8_t value) {
    return fpga_link_write_reg(addr, &value, 1);
}

esp_err_t fpga_link_read8(uint8_t addr, uint8_t *value) {
    return fpga_link_read_reg(addr, value, 1);
}

bool fpga_link_present(void) {
    uint8_t id[2] = {0, 0};
    uint8_t status = 0;
    if (fpga_link_read_reg(REG_ID0, id, 2) != ESP_OK) {
        return false;
    }
    if (fpga_link_read8(REG_STATUS, &status) != ESP_OK) {
        return false;
    }
    return (id[0] == SCOPE_ID0_VAL) && (id[1] == SCOPE_ID1_VAL)
        && (status & STAT_PLL_LOCK);
}

esp_err_t fpga_link_init(void) {
    esp_err_t err = fpga_link_spi_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "spi init: %s", esp_err_to_name(err));
        return err;
    }
    err = fpga_link_irq_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "irq init: %s", esp_err_to_name(err));
        return err;
    }

    s_ready = fpga_link_present();
    ESP_LOGI(TAG, "ready: fpga %s", s_ready ? "detected (PLL locked)" : "not responding");
    return ESP_OK;
}

esp_err_t scope_arm(const scope_acq_cfg_t *cfg) {
    if (cfg == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    const uint8_t mode = (cfg->mode & MODE_SEL_MASK)
                       | (cfg->peak_detect ? MODE_PEAK_EN : 0);
    const uint8_t trig = (cfg->trig_src & TRIGCFG_SRC_MASK)
                       | ((cfg->trig_edge << TRIGCFG_EDGE_SHIFT) & TRIGCFG_EDGE_MASK);
    const uint8_t lvl[2]  = { (uint8_t)cfg->trig_level, (uint8_t)(cfg->trig_level >> 8) };
    const uint8_t dec[2]  = { (uint8_t)cfg->dec_factor, (uint8_t)(cfg->dec_factor >> 8) };
    const uint8_t pre[2]  = { (uint8_t)cfg->pre_count,  (uint8_t)(cfg->pre_count >> 8) };
    const uint8_t post[2] = { (uint8_t)cfg->post_count, (uint8_t)(cfg->post_count >> 8) };
    const uint8_t tmo[4]  = { (uint8_t)cfg->auto_timeout,
                              (uint8_t)(cfg->auto_timeout >> 8),
                              (uint8_t)(cfg->auto_timeout >> 16),
                              (uint8_t)(cfg->auto_timeout >> 24) };
    const uint8_t control = (cfg->auto_rearm ? CTRL_AUTO_REARM : 0)
                          | (cfg->invert_en  ? CTRL_INVERT_EN  : 0);

    CHK(fpga_link_write8(REG_MODE, mode));
    CHK(fpga_link_write8(REG_TRIG_CFG, trig));
    CHK(fpga_link_write_reg(REG_TRIG_LEVEL_L, lvl, 2));
    CHK(fpga_link_write8(REG_TRIG_HYST, cfg->trig_hyst));
    CHK(fpga_link_write_reg(REG_DEC_FACTOR_L, dec, 2));
    CHK(fpga_link_write_reg(REG_PRE_COUNT_L, pre, 2));
    CHK(fpga_link_write_reg(REG_POST_COUNT_L, post, 2));
    CHK(fpga_link_write_reg(REG_AUTO_TMO_0, tmo, 4));
    CHK(fpga_link_write8(REG_CONTROL, control));            // level bits first
    CHK(fpga_link_write8(REG_CONTROL, control | CTRL_ARM)); // then the arm one-shot

    xSemaphoreTake(s_irq_sem, 0);   // drop any stale give
    return ESP_OK;
}

esp_err_t scope_wait_ready(uint32_t timeout_ms) {
    if (xSemaphoreTake(s_irq_sem, pdMS_TO_TICKS(timeout_ms)) != pdTRUE) {
        // Fall back to a status poll in case the edge was missed.
        uint8_t status = 0;
        if (fpga_link_read8(REG_STATUS, &status) == ESP_OK && (status & STAT_FROZEN)) {
            return ESP_OK;
        }
        return ESP_ERR_TIMEOUT;
    }
    return ESP_OK;
}

esp_err_t scope_read_record(scope_sample_t *out, size_t max_samples,
                            size_t *n_out, uint32_t *trig_off) {
    if (out == NULL || n_out == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    *n_out = 0;

    uint8_t cnt[4] = {0};
    esp_err_t err = fpga_link_read_reg(REG_SAMPLE_COUNT_0, cnt, 4);
    if (err != ESP_OK) {
        return err;
    }
    uint32_t n = (uint32_t)cnt[0] | ((uint32_t)cnt[1] << 8)
               | ((uint32_t)cnt[2] << 16) | ((uint32_t)cnt[3] << 24);
    if (n > max_samples) {
        n = max_samples;
    }

    if (trig_off != NULL) {
        uint8_t off[4] = {0};
        if (fpga_link_read_reg(REG_TRIG_PTR_0, off, 4) == ESP_OK) {
            *trig_off = (uint32_t)off[0] | ((uint32_t)off[1] << 8)
                      | ((uint32_t)off[2] << 16) | ((uint32_t)off[3] << 24);
        }
    }

    // Restart the FPGA-side stream, then read 2 * n bytes from REG_REC_DATA
    err = fpga_link_write8(REG_CONTROL, CTRL_REC_REWIND);
    if (err != ESP_OK) {
        return err;
    }

    uint8_t chunk[512];
    size_t got = 0;
    while (got < n) {
        size_t want = n - got;
        if (want > sizeof(chunk) / REC_BYTES_PER_SAMPLE) {
            want = sizeof(chunk) / REC_BYTES_PER_SAMPLE;
        }
        err = fpga_link_read_reg(REG_REC_DATA, chunk, want * REC_BYTES_PER_SAMPLE);
        if (err != ESP_OK) {
            return err;
        }
        for (size_t i = 0; i < want; i++) {
            out[got + i] = scope_decode_sample(chunk[2 * i], chunk[2 * i + 1]);
        }
        got += want;
    }
    *n_out = got;

    (void)fpga_link_write8(REG_CONTROL, CTRL_IRQ_CLR);
    return ESP_OK;
}
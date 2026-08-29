#include "lmh6518.h"
#include <string.h>

// Bus timing (tS/tH = 25 ns) leaves plenty of margin at 10 MHz
#define LMH6518_SPI_HZ (10 * 1000 * 1000)

// Write command byte: bit 7 = 0 (write), remaining bits don't-care
#define LMH6518_CMD_WRITE 0x00

uint16_t lmh6518_pack(const lmh6518_state_t *s) {
    uint16_t w = 0;
    w |= (uint16_t)(s->bw     & 0x7) << 6;  // D8..D6 
    w |= (uint16_t)(s->preamp & 0x1) << 4;  // D4     
    w |= (uint16_t)(s->atten  & 0xF);       // D3..D0 
    w |= (uint16_t)(s->aux    & 0x1) << 10; // D10    
    return w;
}

esp_err_t lmh6518_init(lmh6518_dev_t *dev, spi_host_device_t host, int cs_gpio) {
    if (dev == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    spi_device_interface_config_t devcfg = {
        .mode = 0, // CPOL = 0, CPHA = 0 
        .clock_speed_hz = LMH6518_SPI_HZ,
        .spics_io_num = cs_gpio, // driver drives CS, idle high
        .queue_size = 1,
        .command_bits = 0,
        .address_bits = 0,
    };

    return spi_bus_add_device(host, &devcfg, &dev->spi);
}

esp_err_t lmh6518_set_state(lmh6518_dev_t *dev, const lmh6518_state_t *s) {
    if (dev == NULL || s == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    if (s->atten > LMH6518_ATTEN_MAX || s->bw > LMH6518_BW_750M) {
        return ESP_ERR_INVALID_ARG;
    }

    uint16_t word = lmh6518_pack(s);
    uint8_t frame[3] = {
        LMH6518_CMD_WRITE,
        (uint8_t)(word >> 8),
        (uint8_t)(word & 0xFF),
    };

    spi_transaction_t t;
    memset(&t, 0, sizeof(t));
    t.length = 8 * sizeof(frame); // bits
    t.tx_buffer = frame;

    return spi_device_transmit(dev->spi, &t);
}

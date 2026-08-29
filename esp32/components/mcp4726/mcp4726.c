#include "mcp4726.h"

// Comfortably inside the MCP4726 400 kHz fast-mode ceiling.
#define MCP4726_I2C_HZ (400 * 1000)

// Command bits (byte 0, bits 7..5)
#define MCP4726_CMD_WRITE_VOLATILE_CFG 0x40 // 010xxxxx 

esp_err_t mcp4726_init(mcp4726_dev_t *dev, i2c_master_bus_handle_t bus,
                       uint8_t addr, bool write_config,
                       mcp4726_vref_t cfg_vref, mcp4726_gain_t cfg_gain) {
    if (dev == NULL || bus == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    i2c_device_config_t devcfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = addr,
        .scl_speed_hz = MCP4726_I2C_HZ,
    };

    esp_err_t err = i2c_master_bus_add_device(bus, &devcfg, &dev->dev);
    if (err != ESP_OK || !write_config) {
        return err;
    }

    // Write volatile config + DAC (mid-scale) in one 3-byte transaction.
    uint8_t b0 = MCP4726_CMD_WRITE_VOLATILE_CFG
               | (uint8_t)((cfg_vref & 0x3) << 3)
               | (uint8_t)(cfg_gain & 0x1); /* PD1:PD0 = 00 */
    uint8_t frame[3] = {
        b0,
        (uint8_t)(MCP4726_CODE_MID >> 4),
        (uint8_t)((MCP4726_CODE_MID & 0x0F) << 4),
    };
    return i2c_master_transmit(dev->dev, frame, sizeof(frame), -1);
}

esp_err_t mcp4726_set_code(mcp4726_dev_t *dev, uint16_t code12) {
    if (dev == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    if (code12 > MCP4726_CODE_MAX) {
        code12 = MCP4726_CODE_MAX;
    }

    // Fast write: byte0 = 0 0 PD1 PD0 D11..D8 (PD = 00), byte1 = D7..D0.
    uint8_t frame[2] = {
        (uint8_t)((code12 >> 8) & 0x0F),
        (uint8_t)(code12 & 0xFF),
    };
    return i2c_master_transmit(dev->dev, frame, sizeof(frame), -1);
}

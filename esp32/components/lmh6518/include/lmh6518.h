#ifndef LMH6518_H
#define LMH6518_H

/*
 * LMH6518 — 900 MHz digitally controlled variable gain amplifier (DVGA),
 * used as the oscilloscope vertical-path analog front end.
 *
 * Control is a write-only SPI-compatible bus (SPI mode 0, MSB first). One
 * access is 24 bits: an 8-bit command byte followed by a 16-bit data word.
 * Command bit 7 is R/W (0 = write); the other command bits are don't-care,
 * so every write we issue uses command byte 0x00. Readback (bit 7 = 1) needs
 * SDIO as an input and is not wired on this board, so it is not implemented.
 *
 * 16-bit data word (D15..D0), from the datasheet "Data Field" table:
 *   D15        don't care
 *   D14..D11   reserved, must be 0
 *   D10        aux output power   0 = full power, 1 = aux Hi-Z
 *   D9         reserved, must be 0
 *   D8..D6     bandwidth filter   (see lmh6518_bw_t)
 *   D5         reserved, must be 0
 *   D4         preamp             0 = LG, 1 = HG
 *   D3..D0     ladder attenuation 0..10 => 0 dB..-20 dB in 2 dB steps
 *
 * Power-on-reset word is 0x000A (LG, full bandwidth, full power, -20 dB).
 * Bus timing: tS/tH = 25 ns, so SCLK stays at/below ~20 MHz (we use 10 MHz),
 * with at least a 3 SCLK-cycle gap between accesses.
 */

#include <stdint.h>
#include "esp_err.h"
#include "driver/spi_master.h"

#ifdef __cplusplus
extern "C" {
#endif

// Highest ladder-attenuation code
#define LMH6518_ATTEN_MAX 10

// D4 — input preamplifier gain select.
typedef enum {
    LMH6518_PREAMP_LG = 0, // low gain,  ~18.8 dB at 0 dB ladder attenuation
    LMH6518_PREAMP_HG = 1, // high gain, ~38.8 dB at 0 dB ladder attenuation
} lmh6518_preamp_t;

/* D8..D6 — single-pole low-pass filter shared by main and aux outputs. */
typedef enum {
    LMH6518_BW_FULL = 0,
    LMH6518_BW_20M  = 1,
    LMH6518_BW_100M = 2,
    LMH6518_BW_200M = 3,
    LMH6518_BW_350M = 4,
    LMH6518_BW_650M = 5,
    LMH6518_BW_750M = 6,
    // 7 is unallowed
} lmh6518_bw_t;

// D10 — auxiliary (trigger) output power state.
typedef enum {
    LMH6518_AUX_ON  = 0, // full power 
    LMH6518_AUX_HIZ = 1, // auxiliary output high-impedance 
} lmh6518_aux_t;


typedef struct {
    lmh6518_preamp_t preamp;
    uint8_t          atten; // ladder attenuation code
    lmh6518_bw_t     bw;
    lmh6518_aux_t    aux;
} lmh6518_state_t;

typedef struct {
    spi_device_handle_t spi;
} lmh6518_dev_t;

/*
 * Attach the LMH6518 to an already-initialised SPI bus (see spi_bus_initialize
 * in the caller). Configures a mode-0, 10 MHz device with the driver owning the
 * chip-select line (idle high). Does not write any register.
 */
esp_err_t lmh6518_init(lmh6518_dev_t *dev, spi_host_device_t host, int cs_gpio);

/*
 * Pack a state into its 16-bit data word. Pure and side-effect free so it can
 * be unit-tested on the host. Fields are masked; reserved bits stay 0. Callers
 * that need range checking should use lmh6518_set_state.
 */
uint16_t lmh6518_pack(const lmh6518_state_t *s);

/*
 * Validate (atten <= LMH6518_ATTEN_MAX, bw <= LMH6518_BW_750M) and push the
 * state to the device as one 24-bit transaction {0x00, word_hi, word_lo}.
 * Returns ESP_ERR_INVALID_ARG on an out-of-range field.
 */
esp_err_t lmh6518_set_state(lmh6518_dev_t *dev, const lmh6518_state_t *s);

#ifdef __cplusplus
}
#endif

#endif /* LMH6518_H */

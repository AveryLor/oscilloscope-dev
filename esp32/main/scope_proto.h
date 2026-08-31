#pragma once

/*
 * Oscilloscope FPGA SPI protocol — ESP32 side.
 *
 * Hand-mirrored from fpga/rtl/scope_regs.svh; docs/PROTOCOL.md has the prose
 * description. The ESP32 is the VSPI master, the Tang Nano 20K is the slave.
 *
 * Frame: byte 0 is the header SCOPE_HDR(rw, addr). rw = 1 reads, rw = 0 writes.
 *   - Write: header, then data bytes land in reg[addr], reg[addr+1], ...
 *   - Read:  header, then one turnaround byte (0x00) from the FPGA, then
 *            reg[addr], reg[addr+1], ... stream out on MISO.
 * REG_REC_DATA is special: its address never auto-increments and every read pops
 * the next byte from the record FIFO. Multi-byte fields are little-endian.
 */

#include <stdint.h>

#define SCOPE_HDR_RW_BIT   7
#define SCOPE_HDR(rw, addr) ((uint8_t)(((rw) ? 0x80u : 0x00u) | ((addr) & 0x7Fu)))
#define SCOPE_HDR_WRITE(addr) SCOPE_HDR(0, (addr))
#define SCOPE_HDR_READ(addr)  SCOPE_HDR(1, (addr))

// Register addresses (7-bit).
#define REG_ID0             0x00u
#define REG_ID1             0x01u
#define REG_VER_MAJ         0x02u
#define REG_VER_MIN         0x03u
#define REG_CAPS            0x04u
#define REG_BUF_DEPTH_L     0x05u
#define REG_BUF_DEPTH_H     0x06u
#define REG_CONTROL         0x08u
#define REG_MODE            0x09u
#define REG_TRIG_CFG        0x0Au
#define REG_TRIG_LEVEL_L    0x0Cu
#define REG_TRIG_LEVEL_H    0x0Du
#define REG_TRIG_HYST       0x0Eu
#define REG_DEC_FACTOR_L    0x10u
#define REG_DEC_FACTOR_H    0x11u
#define REG_PRE_COUNT_L     0x14u
#define REG_PRE_COUNT_H     0x15u
#define REG_POST_COUNT_L    0x16u
#define REG_POST_COUNT_H    0x17u
#define REG_AUTO_TMO_0      0x18u
#define REG_AUTO_TMO_1      0x19u
#define REG_AUTO_TMO_2      0x1Au
#define REG_AUTO_TMO_3      0x1Bu
#define REG_PROBE_DIV_L     0x1Cu
#define REG_PROBE_DIV_H     0x1Du
#define REG_PROBE_CTL       0x1Eu
#define REG_STATUS          0x20u
#define REG_SAMPLE_COUNT_0  0x21u
#define REG_SAMPLE_COUNT_1  0x22u
#define REG_SAMPLE_COUNT_2  0x23u
#define REG_SAMPLE_COUNT_3  0x24u
#define REG_TRIG_PTR_0      0x25u
#define REG_TRIG_PTR_1      0x26u
#define REG_TRIG_PTR_2      0x27u
#define REG_TRIG_PTR_3      0x28u
#define REG_TRIG_PHASE_L    0x29u
#define REG_TRIG_PHASE_H    0x2Au
#define REG_OVERRANGE_CNT_L 0x2Bu
#define REG_OVERRANGE_CNT_H 0x2Cu
#define REG_ENC_HS_L        0x30u
#define REG_ENC_HS_H        0x31u
#define REG_ENC_HO_L        0x32u
#define REG_ENC_HO_H        0x33u
#define REG_ENC_TG_L        0x34u
#define REG_ENC_TG_H        0x35u
#define REG_ENC_BTN         0x36u
#define REG_REC_DATA        0x40u
#define REG_REC_STATUS      0x41u

// Identification.
#define SCOPE_ID0_VAL     0x53u // 'S'
#define SCOPE_ID1_VAL     0x43u // 'C'
#define SCOPE_VER_MAJ_VAL 0x01u
#define SCOPE_VER_MIN_VAL 0x00u

// CONTROL (0x08). W1 bits self-clear in the FPGA.
#define CTRL_ARM         (1u << 0) // W1
#define CTRL_ABORT       (1u << 1) // W1
#define CTRL_FORCE_TRIG  (1u << 2) // W1
#define CTRL_AUTO_REARM  (1u << 3)
#define CTRL_INVERT_EN   (1u << 4)
#define CTRL_IRQ_CLR     (1u << 5) // W1
#define CTRL_REC_REWIND  (1u << 6) // W1
#define CTRL_SOFT_RESET  (1u << 7) // W1

// MODE (0x09).
#define MODE_SEL_MASK  0x03u
#define MODE_NORMAL    0x00u
#define MODE_AUTO      0x01u
#define MODE_SINGLE    0x02u
#define MODE_PEAK_EN   (1u << 2)

// TRIG_CFG (0x0A).
#define TRIGCFG_SRC_MASK   0x03u
#define TRIGCFG_SRC_LEVEL  0x00u
#define TRIGCFG_SRC_EXT    0x01u
#define TRIGCFG_SRC_FORCE  0x02u
#define TRIGCFG_EDGE_SHIFT 2
#define TRIGCFG_EDGE_MASK  (0x03u << TRIGCFG_EDGE_SHIFT)
#define TRIGCFG_EDGE_RISING  (0x00u << TRIGCFG_EDGE_SHIFT)
#define TRIGCFG_EDGE_FALLING (0x01u << TRIGCFG_EDGE_SHIFT)
#define TRIGCFG_EDGE_EITHER  (0x02u << TRIGCFG_EDGE_SHIFT)

// PROBE_CTL (0x1E).
#define PROBE_EN (1u << 0)

// STATUS (0x20).
#define STAT_STATE_MASK  0x07u
#define STAT_FROZEN      (1u << 3)
#define STAT_PLL_LOCK    (1u << 4)
#define STAT_IRQ         (1u << 5)
#define STAT_TRIGD_AUTO  (1u << 6)
#define STAT_OVERRUN     (1u << 7)

// ENC_BTN (0x36). Event bits clear on read.
#define ENCBTN_HS_LVL (1u << 0)
#define ENCBTN_HS_EVT (1u << 1)
#define ENCBTN_HO_LVL (1u << 2)
#define ENCBTN_HO_EVT (1u << 3)
#define ENCBTN_TG_LVL (1u << 4)
#define ENCBTN_TG_EVT (1u << 5)

// REC_STATUS (0x41).
#define RECST_FIFO_EMPTY (1u << 0)
#define RECST_DONE       (1u << 1)
#define RECST_UNDERFLOW  (1u << 2)

// CAPS (0x04).
#define CAPS_PEAK     (1u << 0)
#define CAPS_EXTTRIG  (1u << 1)
#define CAPS_SDRAM    (1u << 2)
#define CAPS_32K      (1u << 3)

// A read past the end of the record returns this byte.
#define SCOPE_REC_PAD 0xFFu

/*
 * Record entry, as reassembled from two little-endian REC_DATA bytes:
 *   byte 0 = code[7:0]
 *   byte 1 = {is_max, over_range, 0,0,0,0, code[9:8]}
 */
typedef struct {
    uint16_t code;      // 10-bit ADC code, VIN+/VIN- corrected
    uint8_t  over_range; // 1 if the ADC flagged over-range for this sample
    uint8_t  is_max;     // peak mode: 1 = window maximum, 0 = window minimum
} scope_sample_t;

static inline scope_sample_t scope_decode_sample(uint8_t lo, uint8_t hi) {
    scope_sample_t s;
    s.code       = (uint16_t)(lo | ((hi & 0x03u) << 8));
    s.over_range = (hi >> 6) & 0x01u;
    s.is_max     = (hi >> 7) & 0x01u;
    return s;
}

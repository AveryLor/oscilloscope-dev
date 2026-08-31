/*
 * File: scope_regs.svh
 * Description: SPI register contract for the Tang Nano 20K oscilloscope. This
 *              file is `include`d at package scope by scope_pkg.sv and is the
 *              single source of truth for the register map. Keep it in step with
 *              esp32/main/scope_proto.h and docs/PROTOCOL.md by hand.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`ifndef SCOPE_REGS_SVH
`define SCOPE_REGS_SVH

// Frame: byte 0 is the header {RW[7], ADDR[6:0]}. RW = 1 reads, RW = 0 writes.
// Writes stream data bytes into reg[ADDR], reg[ADDR+1], ... Reads emit one
// turnaround byte (0x00) then stream reg[ADDR], reg[ADDR+1], ... REC_DATA is the
// one exception: its address never auto-increments, and every read pops the next
// byte from the record FIFO. Multi-byte fields are little-endian (low address =
// least-significant byte).
localparam logic [7:0] SCOPE_HDR_RW_BIT = 8'd7;

localparam logic [6:0]
    REG_ID0            = 7'h00,   // RO  magic 'S'
    REG_ID1            = 7'h01,   // RO  magic 'C'
    REG_VER_MAJ        = 7'h02,   // RO
    REG_VER_MIN        = 7'h03,   // RO
    REG_CAPS           = 7'h04,   // RO  build-time capability bits
    REG_BUF_DEPTH_L    = 7'h05,   // RO  sample capacity, 16-bit LE
    REG_BUF_DEPTH_H    = 7'h06,
    REG_CONTROL        = 7'h08,   // RW  action + mode bits
    REG_MODE           = 7'h09,   // RW  acquisition mode + peak enable
    REG_TRIG_CFG       = 7'h0A,   // RW  trigger source + edge
    REG_TRIG_LEVEL_L   = 7'h0C,   // RW  10-bit level, LE
    REG_TRIG_LEVEL_H   = 7'h0D,
    REG_TRIG_HYST      = 7'h0E,   // RW  hysteresis code
    REG_DEC_FACTOR_L   = 7'h10,   // RW  decimation - 1, 16-bit LE
    REG_DEC_FACTOR_H   = 7'h11,
    REG_PRE_COUNT_L    = 7'h14,   // RW  pre-trigger sample count, 16-bit LE
    REG_PRE_COUNT_H    = 7'h15,
    REG_POST_COUNT_L   = 7'h16,   // RW  post-trigger sample count, 16-bit LE
    REG_POST_COUNT_H   = 7'h17,
    REG_AUTO_TMO_0     = 7'h18,   // RW  auto-trigger timeout, 32-bit LE
    REG_AUTO_TMO_1     = 7'h19,
    REG_AUTO_TMO_2     = 7'h1A,
    REG_AUTO_TMO_3     = 7'h1B,
    REG_PROBE_DIV_L    = 7'h1C,   // RW  probe-comp half period, 16-bit LE
    REG_PROBE_DIV_H    = 7'h1D,
    REG_PROBE_CTL      = 7'h1E,   // RW  probe-comp enable
    REG_STATUS         = 7'h20,   // RO  live acquisition status
    REG_SAMPLE_COUNT_0 = 7'h21,   // RO  entries in the frozen record, 32-bit LE
    REG_SAMPLE_COUNT_1 = 7'h22,
    REG_SAMPLE_COUNT_2 = 7'h23,
    REG_SAMPLE_COUNT_3 = 7'h24,
    REG_TRIG_PTR_0     = 7'h25,   // RO  trigger sample offset in record, 32-bit LE
    REG_TRIG_PTR_1     = 7'h26,
    REG_TRIG_PTR_2     = 7'h27,
    REG_TRIG_PTR_3     = 7'h28,
    REG_TRIG_PHASE_L   = 7'h29,   // RO  decimation phase at trigger, 16-bit LE
    REG_TRIG_PHASE_H   = 7'h2A,
    REG_OVERRANGE_CNT_L = 7'h2B,  // RO  over-range samples in record, 16-bit LE
    REG_OVERRANGE_CNT_H = 7'h2C,
    REG_ENC_HS_L       = 7'h30,   // RO  horizontal-scale encoder count, s16 LE
    REG_ENC_HS_H       = 7'h31,
    REG_ENC_HO_L       = 7'h32,   // RO  horizontal-offset encoder count, s16 LE
    REG_ENC_HO_H       = 7'h33,
    REG_ENC_TG_L       = 7'h34,   // RO  trigger-level encoder count, s16 LE
    REG_ENC_TG_H       = 7'h35,
    REG_ENC_BTN        = 7'h36,   // RO  encoder button levels + latched events
    REG_REC_DATA       = 7'h40,   // RO  record FIFO pop (no address increment)
    REG_REC_STATUS     = 7'h41;   // RO  record FIFO status

// Reset / identification values.
localparam logic [7:0] SCOPE_ID0_VAL     = 8'h53; // 'S'
localparam logic [7:0] SCOPE_ID1_VAL     = 8'h43; // 'C'
localparam logic [7:0] SCOPE_VER_MAJ_VAL = 8'h01;
localparam logic [7:0] SCOPE_VER_MIN_VAL = 8'h00;

// CONTROL (0x08). Bits marked W1 are write-1 one-shots that self-clear.
localparam int CTRL_ARM_BIT        = 0; // W1  arm the acquisition engine
localparam int CTRL_ABORT_BIT      = 1; // W1  abort back to IDLE
localparam int CTRL_FORCE_TRIG_BIT = 2; // W1  force an immediate trigger
localparam int CTRL_AUTO_REARM_BIT = 3; // level: re-arm automatically after dump
localparam int CTRL_INVERT_EN_BIT  = 4; // level: correct the swapped VIN+/VIN-
localparam int CTRL_IRQ_CLR_BIT    = 5; // W1  acknowledge / clear fpga_irq
localparam int CTRL_REC_REWIND_BIT = 6; // W1  restart the record readout
localparam int CTRL_SOFT_RESET_BIT = 7; // W1  soft-reset the datapath

// MODE (0x09).
localparam int MODE_SEL_LSB  = 0;       // [1:0] acq_mode_e
localparam int MODE_PEAK_BIT = 2;       // enable min/max peak-detect decimation

// TRIG_CFG (0x0A).
localparam int TRIGCFG_SRC_LSB  = 0;    // [1:0] trig_src_e
localparam int TRIGCFG_EDGE_LSB = 2;    // [3:2] trig_edge_e

// PROBE_CTL (0x1E).
localparam int PROBE_EN_BIT = 0;

// STATUS (0x20).
localparam int STAT_STATE_LSB      = 0; // [2:0] acq_state_e
localparam int STAT_FROZEN_BIT     = 3;
localparam int STAT_PLL_LOCK_BIT   = 4;
localparam int STAT_IRQ_BIT        = 5;
localparam int STAT_TRIGD_AUTO_BIT = 6;
localparam int STAT_OVERRUN_BIT    = 7;

// ENC_BTN (0x36). Each event bit latches on press and clears when this register
// is read.
localparam int ENCBTN_HS_LVL_BIT = 0;
localparam int ENCBTN_HS_EVT_BIT = 1;
localparam int ENCBTN_HO_LVL_BIT = 2;
localparam int ENCBTN_HO_EVT_BIT = 3;
localparam int ENCBTN_TG_LVL_BIT = 4;
localparam int ENCBTN_TG_EVT_BIT = 5;

// REC_STATUS (0x41).
localparam int RECST_FIFO_EMPTY_BIT = 0;
localparam int RECST_DONE_BIT       = 1;
localparam int RECST_UNDERFLOW_BIT  = 2;

// CAPS (0x04).
localparam int CAPS_PEAK_BIT    = 0;    // peak-detect decimation present
localparam int CAPS_EXTTRIG_BIT = 1;    // external hw_trigger present
localparam int CAPS_SDRAM_BIT   = 2;    // deep SDRAM buffer present (0 in v1)
localparam int CAPS_32K_BIT     = 3;    // built with SAMPLE_DEPTH = 32768

// Byte past the end of the record reads back as this value.
localparam logic [7:0] SCOPE_REC_PAD = 8'hFF;

`endif

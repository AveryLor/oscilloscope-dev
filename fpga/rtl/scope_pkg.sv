/*
 * File: scope_pkg.sv
 * Description: Shared parameters, enums and packed config/status structs for the
 *              Tang Nano 20K oscilloscope RTL. Includes the register map from
 *              scope_regs.svh so every module sees one contract.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

package scope_pkg;

    // Sample-buffer word layout, packed into SCOPE_DW bits:
    //   [SCOPE_CODE_W-1:0] ADC code (VIN+/VIN- corrected)
    //   [SCOPE_DW-2]       over_range flag for this entry
    //   [SCOPE_DW-1]       is_max flag (peak-detect: 1 = window max, 0 = window min)
    localparam int SCOPE_CODE_W = 10;
    localparam int SCOPE_DW     = 16;

    // SPI register address width (header byte carries ADDR[6:0]).
    localparam int SCOPE_ADDR_W = 7;

    // Width of the acquisition sample counters. 20 bits covers SAMPLE_DEPTH up to
    // 2**19 even in peak mode (two entries per decimation window).
    localparam int SCOPE_CNT_W = 20;

    typedef enum logic [1:0] {
        TRIG_SRC_LEVEL = 2'd0,
        TRIG_SRC_EXT   = 2'd1,
        TRIG_SRC_FORCE = 2'd2
    } trig_src_e;

    typedef enum logic [1:0] {
        TRIG_EDGE_RISING  = 2'd0,
        TRIG_EDGE_FALLING = 2'd1,
        TRIG_EDGE_EITHER  = 2'd2
    } trig_edge_e;

    typedef enum logic [1:0] {
        ACQ_MODE_NORMAL = 2'd0,
        ACQ_MODE_AUTO   = 2'd1,
        ACQ_MODE_SINGLE = 2'd2
    } acq_mode_e;

    typedef enum logic [2:0] {
        ACQ_ST_IDLE      = 3'd0,
        ACQ_ST_ARMED     = 3'd1,
        ACQ_ST_PREFILL   = 3'd2,
        ACQ_ST_WAIT_TRIG = 3'd3,
        ACQ_ST_POST_TRIG = 3'd4,
        ACQ_ST_FROZEN    = 3'd5,
        ACQ_ST_DUMP      = 3'd6
    } acq_state_e;

    // Config committed from the SPI domain into the capture domain as one unit.
    // Fields are plain vectors (not enum-typed) so the struct stays a simple
    // packed bit bundle for CDC.
    typedef struct packed {
        logic [31:0]            auto_timeout; // capture-tick auto-trigger timeout
        logic [SCOPE_CNT_W-1:0] post_count;   // samples written after the trigger
        logic [SCOPE_CNT_W-1:0] pre_count;    // samples guaranteed before trigger
        logic [15:0]            dec_factor;   // decimation - 1 (0 => divide by 1)
        logic [7:0]             trig_hyst;    // level-trigger hysteresis code
        logic [SCOPE_CODE_W-1:0] trig_level;  // level-trigger threshold code
        logic [1:0]             trig_edge;    // trig_edge_e
        logic [1:0]             trig_src;     // trig_src_e
        logic                   auto_rearm;   // re-arm automatically after a dump
        logic                   invert_en;    // apply the VIN+/VIN- code inversion
        logic                   peak_en;      // min/max peak-detect decimation
        logic [1:0]             mode;         // acq_mode_e
    } scope_cfg_t;

    // Status published from the capture domain back to the SPI register file.
    typedef struct packed {
        logic [15:0] overrange_cnt;     // over-range samples in the frozen record
        logic [15:0] trig_phase;        // decimation phase counter at the trigger
        logic [31:0] trig_ptr;          // trigger sample offset within the record
        logic [31:0] sample_count;      // number of valid entries in the record
        logic        overrun;           // writer lapped an unread record
        logic        triggered_by_auto; // last freeze was an auto-trigger timeout
        logic        irq;               // fpga_irq line state
        logic        pll_lock;          // ADC sample-clock PLL locked
        logic        frozen;            // a record is frozen and ready to read
        logic [2:0]  state;             // acq_state_e
    } scope_sta_t;

    `include "scope_regs.svh"

endpackage

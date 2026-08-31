/*
 * File: trigger_engine.sv
 * Description: Produces a one-cycle trig_pulse in the capture clock domain.
 *              Sources: a level comparator on the full-rate corrected sample
 *              stream (edge select + hysteresis re-arm), the external
 *              hw_trigger line, or force-only. force_trig always fires the next
 *              cycle while armed. armed (from the acquisition FSM) qualifies
 *              every source.
 *
 * The level path runs on the undecimated stream so trig_pulse lands on the exact
 * sample that crossed the threshold.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module trigger_engine
    import scope_pkg::*;
#(
    parameter int WIDTH = SCOPE_CODE_W
) (
    input  logic             clk,
    input  logic             rst_n,

    input  logic [WIDTH-1:0] sample_in,
    input  logic             valid_in,
    input  logic             ext_trig_sync,

    input  logic [1:0]       cfg_src,   // trig_src_e
    input  logic [1:0]       cfg_edge,  // trig_edge_e
    input  logic [WIDTH-1:0] cfg_level,
    input  logic [7:0]       cfg_hyst,

    input  logic             armed,
    input  logic             force_trig,

    output logic             trig_pulse
);

    localparam int EW = WIDTH + 2;  // headroom for level +/- hyst

    logic [EW-1:0] level_ext, arm_lo, arm_hi;
    assign level_ext = {2'b00, cfg_level};
    assign arm_lo    = (level_ext > {4'b0, cfg_hyst}) ? (level_ext - {4'b0, cfg_hyst}) : '0;
    assign arm_hi    = level_ext + {4'b0, cfg_hyst};

    logic [WIDTH-1:0] prev_sample;
    logic             prev_ext;
    logic             primed_rise;  // saw the low re-arm band since the last fire
    logic             primed_fall;  // saw the high re-arm band since the last fire

    logic want_rise, want_fall;
    assign want_rise = (cfg_edge == 2'(TRIG_EDGE_RISING)) || (cfg_edge == 2'(TRIG_EDGE_EITHER));
    assign want_fall = (cfg_edge == 2'(TRIG_EDGE_FALLING)) || (cfg_edge == 2'(TRIG_EDGE_EITHER));

    logic lvl_rise_cross, lvl_fall_cross;
    assign lvl_rise_cross = (prev_sample <  cfg_level) && (sample_in >= cfg_level);
    assign lvl_fall_cross = (prev_sample >  cfg_level) && (sample_in <= cfg_level);

    logic ext_rise, ext_fall;
    assign ext_rise = ~prev_ext &  ext_trig_sync;
    assign ext_fall =  prev_ext & ~ext_trig_sync;

    logic level_fire, ext_fire;
    assign level_fire = valid_in &&
                        ((want_rise && primed_rise && lvl_rise_cross) ||
                         (want_fall && primed_fall && lvl_fall_cross));
    assign ext_fire   = (want_rise && ext_rise) || (want_fall && ext_fall);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_sample <= '0;
            prev_ext    <= 1'b0;
            primed_rise <= 1'b0;
            primed_fall <= 1'b0;
            trig_pulse  <= 1'b0;
        end else begin
            trig_pulse <= 1'b0;
            prev_ext   <= ext_trig_sync;
            if (valid_in) begin
                prev_sample <= sample_in;
                // Re-arm bands: entering them primes the matching edge.
                if ({2'b00, sample_in} <= arm_lo) primed_rise <= 1'b1;
                if ({2'b00, sample_in} >= arm_hi) primed_fall <= 1'b1;
            end

            if (!armed) begin
                primed_rise <= 1'b0;
                primed_fall <= 1'b0;
            end else if (force_trig) begin
                trig_pulse <= 1'b1;
            end else if (cfg_src == 2'(TRIG_SRC_LEVEL) && level_fire) begin
                trig_pulse  <= 1'b1;
                primed_rise <= 1'b0;
                primed_fall <= 1'b0;
            end else if (cfg_src == 2'(TRIG_SRC_EXT) && ext_fire) begin
                trig_pulse <= 1'b1;
            end
        end
    end

endmodule

/*
 * File: adc_deskew.sv
 * Description: ADC pad input path with per-lane deskew. Each of the 11 lanes
 *              (adc_d[9:0], adc_or) runs pad -> IODELAY -> IDDR, all inside the
 *              pad's IOLOGIC:
 *
 *                - IODELAY delays that one lane so every bit's eye can be lined
 *                  up with the others. Its tap is moved one step at a time by
 *                  iodelay_stepper in the housekeeping domain, chasing the
 *                  DLY_TAP_* register targets.
 *                - IDDR samples the lane on both edges of adc_sample_clk. The
 *                  rising-edge sample (Q0) is the real ADC data and replaces the
 *                  old plain IOLOGIC input flop. The falling-edge sample (Q1)
 *                  only feeds adc_eye_monitor, which measures where the lane's
 *                  edges sit relative to the rising sample.
 *
 * Nothing may sit between the pad and IODELAY / IDDR or they will not pack into
 * IOLOGIC. Moving a tap glitches that lane for the step, so taps should only
 * change while calibrating, never during a capture that matters.
 * Author: Avery Lor
 * Date: Oct 7 2026
 */

module adc_deskew
    import scope_pkg::*;
#(
    parameter int N  = DESKEW_LANES,
    parameter int TW = DESKEW_TAP_W
) (
    // Pads. Lane i < 10 is adc_d[i], lane 10 is adc_or.
    input  logic [N-1:0]    pad_in,

    // Capture domain.
    input  logic            cap_clk,
    output logic [N-1:0]    rise_q,   // rising-edge samples (the data)
    output logic [N-1:0]    fall_q,   // falling-edge samples (eye monitor only)

    // Housekeeping domain: per-lane tap targets, lane i at [i*TW +: TW].
    input  logic            hk_clk,
    input  logic            hk_rst_n,
    input  logic [N*TW-1:0] tap_tgt,
    output logic            busy
);

    logic [N-1:0] dly_sdtap, dly_setn, dly_value;
    logic [N-1:0] dly_out;

    iodelay_stepper #(.N(N), .TW(TW)) u_stepper (
        .clk     (hk_clk),
        .rst_n   (hk_rst_n),
        .tap_tgt (tap_tgt),
        .sdtap   (dly_sdtap),
        .setn    (dly_setn),
        .value   (dly_value),
        .busy    (busy)
    );

    for (genvar i = 0; i < N; i++) begin : g_lane
        IODELAY #(.C_STATIC_DLY(0)) u_dly (
            .DI    (pad_in[i]),
            .SDTAP (dly_sdtap[i]),
            .SETN  (dly_setn[i]),
            .VALUE (dly_value[i]),
            .DO    (dly_out[i]),
            .DF    ()
        );

        IDDR #(.Q0_INIT(1'b0), .Q1_INIT(1'b0)) u_iddr (
            .D   (dly_out[i]),
            .CLK (cap_clk),
            .Q0  (rise_q[i]),
            .Q1  (fall_q[i])
        );
    end

endmodule

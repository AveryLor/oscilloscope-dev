/*
 * File: cdc_pulse_toggle.sv
 * Description: Move a single-cycle strobe from the source clock domain to the
 *              destination clock domain. The source pulse flips a toggle flop;
 *              the destination synchronizes the toggle and edge-detects it,
 *              emitting exactly one destination-clock pulse per source pulse.
 *
 * Source pulses must be spaced at least a few destination-clock cycles apart or
 * they will be coalesced. There is no back-pressure.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module cdc_pulse_toggle #(
    parameter int STAGES = 3
) (
    input  logic src_clk,
    input  logic src_rst_n,
    input  logic src_pulse,

    input  logic dst_clk,
    input  logic dst_rst_n,
    output logic dst_pulse
);

    (* syn_keep = "true" *)
    logic toggle_q;

    always_ff @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            toggle_q <= 1'b0;
        end else if (src_pulse) begin
            toggle_q <= ~toggle_q;
        end
    end

    (* syn_keep = "true", syn_preserve = "true" *)
    logic [STAGES-1:0] sync_q;

    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            sync_q <= '0;
        end else begin
            sync_q <= {sync_q[STAGES-2:0], toggle_q};
        end
    end

    assign dst_pulse = sync_q[STAGES-1] ^ sync_q[STAGES-2];

endmodule

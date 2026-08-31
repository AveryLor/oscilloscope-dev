/*
 * File: irq_gen.sv
 * Description: Drives the fpga_irq line to the ESP32. A capture-domain toggle
 *              (irq_toggle_cap, flipped once per freeze) is synchronized and
 *              edge-detected here; its edge sets a level latch that stays high,
 *              active-high and idle-low, until the host acknowledges with
 *              irq_clr or the engine is re-armed. The ESP32 uses a rising-edge
 *              GPIO interrupt plus a level read, so the line must be held.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module irq_gen #(
    parameter int STAGES = 3
) (
    input  logic clk,
    input  logic rst_n,

    input  logic irq_toggle_cap, // toggles once per frozen record (capture domain)
    input  logic irq_clr,        // host acknowledge (this domain, pulse)
    input  logic arm_seen,       // engine re-armed (this domain, pulse)

    output logic irq_out,        // to the fpga_irq pad
    output logic irq_level       // same value, for the STATUS register
);

    (* syn_keep = "true", syn_preserve = "true" *)
    logic [STAGES-1:0] sync_q;
    logic              tog_edge;

    assign tog_edge = sync_q[STAGES-1] ^ sync_q[STAGES-2];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_q  <= '0;
            irq_out <= 1'b0;
        end else begin
            sync_q <= {sync_q[STAGES-2:0], irq_toggle_cap};
            if (tog_edge) begin
                irq_out <= 1'b1;
            end else if (irq_clr || arm_seen) begin
                irq_out <= 1'b0;
            end
        end
    end

    assign irq_level = irq_out;

endmodule

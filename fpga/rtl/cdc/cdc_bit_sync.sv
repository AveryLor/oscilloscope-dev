/*
 * File: cdc_bit_sync.sv
 * Description: Multi-flop synchronizer for one or more independent single-bit
 *              signals crossing into the clk domain. Use only for signals that
 *              are level-stable or Gray-coded (no more than one bit changing per
 *              source event) — a plain vector of unrelated toggling bits is not
 *              safe through this.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module cdc_bit_sync #(
    parameter int WIDTH  = 1,
    parameter int STAGES = 3
) (
    input  logic             clk,
    input  logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] q
);

    // sync[0] is the first capture flop; keep the whole chain from being merged
    // or retimed so the metastability-settling stages actually exist in silicon.
    (* syn_keep = "true", syn_preserve = "true" *)
    logic [WIDTH-1:0] sync [STAGES];

    always_ff @(posedge clk) begin
        sync[0] <= d;
        for (int s = 1; s < STAGES; s++) begin
            sync[s] <= sync[s-1];
        end
    end

    assign q = sync[STAGES-1];

endmodule

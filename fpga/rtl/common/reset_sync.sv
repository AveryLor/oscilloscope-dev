/*
 * File: reset_sync.sv
 * Description: Async-assert / sync-deassert reset bridge for one clock domain.
 *              arst_n may fall at any time (immediate reset); its rising edge is
 *              re-timed onto clk through STAGES flops so logic leaves reset
 *              synchronously.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module reset_sync #(
    parameter int STAGES = 3
) (
    input  logic clk,
    input  logic arst_n,
    output logic rst_n
);

    (* syn_keep = "true", syn_preserve = "true" *)
    logic [STAGES-1:0] chain;

    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            chain <= '0;
        end else begin
            chain <= {chain[STAGES-2:0], 1'b1};
        end
    end

    assign rst_n = chain[STAGES-1];

endmodule

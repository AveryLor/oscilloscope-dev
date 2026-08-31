/*
 * File: por_gen.sv
 * Description: Power-on reset generator. The board has no reset pin, so this
 *              rides the always-present 27 MHz crystal: por_n starts low
 *              (GW2AR registers power up to 0) and is released after RST_CYCLES
 *              edges, then stays high. Downstream domains take this through a
 *              reset_sync.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module por_gen #(
    parameter int RST_CYCLES = 135000  // ~5 ms at 27 MHz
) (
    input  logic clk,
    output logic por_n
);

    localparam int CW = $clog2(RST_CYCLES + 1);

    (* syn_keep = "true" *)
    logic [CW-1:0] cnt = '0;
    (* syn_keep = "true" *)
    logic          released = 1'b0;

    always_ff @(posedge clk) begin
        if (!released) begin
            if (cnt == CW'(RST_CYCLES)) begin
                released <= 1'b1;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

    assign por_n = released;

endmodule

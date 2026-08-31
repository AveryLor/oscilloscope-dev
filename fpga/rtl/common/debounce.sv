/*
 * File: debounce.sv
 * Description: Per-bit debouncer. Each output bit follows its input only after
 *              the input has held the new value for STABLE_CYC consecutive
 *              clocks; shorter glitches are ignored. Inputs are assumed to have
 *              already been through a synchronizer.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module debounce #(
    parameter int WIDTH      = 1,
    parameter int STABLE_CYC = 27000  // ~1 ms at 27 MHz
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] q
);

    localparam int CW = (STABLE_CYC <= 1) ? 1 : $clog2(STABLE_CYC);

    genvar b;
    generate
        for (b = 0; b < WIDTH; b++) begin : g_bit
            logic [CW-1:0] cnt;
            logic          sample;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    cnt    <= '0;
                    sample <= 1'b0;
                    q[b]   <= 1'b0;
                end else if (d[b] != sample) begin
                    // Input differs from the last accepted value: time it.
                    sample <= d[b];
                    cnt    <= '0;
                end else if (cnt == CW'(STABLE_CYC - 1)) begin
                    q[b] <= sample;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    endgenerate

endmodule

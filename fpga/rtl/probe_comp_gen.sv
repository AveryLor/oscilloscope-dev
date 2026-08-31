/*
 * File: probe_comp_gen.sv
 * Description: Probe-compensation square wave on the probe_comp pin. Toggles
 *              every half_period clocks; a cfg_div of 0 selects the DEFAULT_HALF
 *              divisor (1 kHz at 27 MHz). The divisor is reloaded only at the end
 *              of a half period so changing it never shortens the current level.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module probe_comp_gen #(
    parameter int DIV_W        = 16,
    parameter int DEFAULT_HALF = 13500  // 27e6 / (2 * 1000)
) (
    input  logic              clk,
    input  logic              rst_n,
    input  logic [DIV_W-1:0]  cfg_div,
    input  logic              cfg_en,
    output logic              sq_out
);

    logic [DIV_W-1:0] half_period;
    logic [DIV_W-1:0] cnt;

    assign half_period = (cfg_div == '0) ? DIV_W'(DEFAULT_HALF) : cfg_div;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt    <= '0;
            sq_out <= 1'b0;
        end else if (!cfg_en) begin
            cnt    <= '0;
            sq_out <= 1'b0;
        end else if (cnt >= (half_period - 1'b1)) begin
            cnt    <= '0;
            sq_out <= ~sq_out;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

endmodule

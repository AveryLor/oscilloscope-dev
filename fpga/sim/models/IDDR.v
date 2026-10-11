/*
 * File: IDDR.v
 * Description: Behavioral stand-in for the Gowin IDDR primitive. D is sampled on
 *              the rising edge and on the following falling edge; both samples
 *              are presented together on the next rising edge, Q0 = the rising
 *              sample (earlier) and Q1 = the falling sample (later). That pairing
 *              is what adc_eye_monitor assumes; VERIFY it against Gowin UG289.
 * Author: Avery Lor
 * Date: Oct 7 2026
 */

`timescale 1ns/1ps

module IDDR #(
    parameter Q0_INIT = 1'b0,
    parameter Q1_INIT = 1'b0
) (
    input      D,
    input      CLK,
    output reg Q0,
    output reg Q1
);

    reg r_s = Q0_INIT;
    reg f_s = Q1_INIT;

    initial begin
        Q0 = Q0_INIT;
        Q1 = Q1_INIT;
    end

    always @(posedge CLK) begin
        Q0  <= r_s;
        Q1  <= f_s;
        r_s <= D;
    end

    always @(negedge CLK) f_s <= D;

endmodule

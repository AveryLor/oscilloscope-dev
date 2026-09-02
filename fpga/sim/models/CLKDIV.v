/*
 * File: CLKDIV.v
 * Description: Behavioral stand-in for the Gowin CLKDIV primitive, enough to
 *              simulate video_clkgen / top under Icarus. CLKOUT is HCLKIN divided
 *              by the integer named in DIV_MODE ("2", "4" or "5"); the real
 *              primitive also supports "3.5" which this project does not use.
 *              Frequency-accurate, not phase-accurate.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

`timescale 1ns/1ps

module CLKDIV #(
    parameter DIV_MODE = "2",
    parameter GSREN     = "false"
) (
    output CLKOUT,
    input  HCLKIN,
    input  RESETN,
    input  CALIB
);

    localparam integer DIV = (DIV_MODE == "5") ? 5 :
                             (DIV_MODE == "4") ? 4 : 2;

    integer cnt = 0;
    always @(posedge HCLKIN or negedge RESETN) begin
        if (!RESETN) cnt <= 0;
        else         cnt <= (cnt == DIV - 1) ? 0 : cnt + 1;
    end

    assign CLKOUT = (cnt < ((DIV + 1) / 2));

endmodule

/*
 * File: tb_adc_input_cond.sv
 * Description: adc_input_cond passes codes through unchanged with invert_en = 0
 *              and reflects them around mid-scale (1023 - code) with invert_en =
 *              1, and registers the over-range flag alongside.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_adc_input_cond;
    import scope_pkg::*;
    `include "tb_common.svh"

    logic       clk = 0, rst_n = 0;
    logic       invert_en = 0;
    logic [9:0] d_in = 0;
    logic       or_in = 0;
    logic [9:0] sample_out;
    logic       or_out, valid_out;
    always #5 clk = ~clk;

    adc_input_cond dut (
        .clk(clk), .rst_n(rst_n), .invert_en(invert_en),
        .d_in(d_in), .or_in(or_in),
        .sample_out(sample_out), .or_out(or_out), .valid_out(valid_out));

    integer i;
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;

        invert_en = 0;
        for (i = 0; i < 1024; i = i + 16) begin
            d_in <= i[9:0]; or_in <= (i > 900);
            @(posedge clk); #1;
            `EXPECT_EQ(sample_out, i[9:0], "passthrough code");
            `EXPECT_EQ(or_out, (i > 900), "passthrough over-range");
            `EXPECT_EQ(valid_out, 1'b1, "valid asserted");
        end

        invert_en = 1;
        for (i = 0; i < 1024; i = i + 16) begin
            d_in <= i[9:0];
            @(posedge clk); #1;
            `EXPECT_EQ(sample_out, 10'(1023 - i), "inverted code");
        end

        `TB_FINISH("tb_adc_input_cond");
    end
endmodule

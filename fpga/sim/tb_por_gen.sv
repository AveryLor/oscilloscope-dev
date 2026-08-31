/*
 * File: tb_por_gen.sv
 * Description: por_gen releases exactly RST_CYCLES edges after power-up and then
 *              stays released.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_por_gen;
    `include "tb_common.svh"

    localparam int RSTC = 20;

    logic clk = 0;
    logic por_n;
    always #5 clk = ~clk;

    por_gen #(.RST_CYCLES(RSTC)) dut (.clk(clk), .por_n(por_n));

    `TB_DUMP("build/tb_por_gen.vcd")

    integer i;
    initial begin
        `EXPECT_EQ(por_n, 1'b0, "por_n low at t0");
        // Count rising edges until release.
        for (i = 0; i < RSTC; i = i + 1) begin
            @(posedge clk); #1;
            `EXPECT_EQ(por_n, 1'b0, "por_n still low before RST_CYCLES");
        end
        @(posedge clk); #1;
        `EXPECT_EQ(por_n, 1'b1, "por_n released after RST_CYCLES");
        repeat (50) @(posedge clk); #1;
        `EXPECT_EQ(por_n, 1'b1, "por_n stays released");
        `TB_FINISH("tb_por_gen");
    end
endmodule

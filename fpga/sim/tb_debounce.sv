/*
 * File: tb_debounce.sv
 * Description: debounce rejects pulses shorter than STABLE_CYC and passes a
 *              level once it has held for STABLE_CYC clocks.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_debounce;
    `include "tb_common.svh"

    localparam int SC = 8;

    logic clk = 0;
    logic rst_n = 0;
    logic d = 0;
    logic q;
    always #5 clk = ~clk;

    debounce #(.WIDTH(1), .STABLE_CYC(SC)) dut (.clk(clk), .rst_n(rst_n), .d(d), .q(q));

    `TB_DUMP("build/tb_debounce.vcd")

    integer i;
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Short glitch: high for SC-2 cycles then back low -> q never moves.
        d = 1;
        repeat (SC-2) @(posedge clk);
        d = 0;
        repeat (SC+4) @(posedge clk);
        `EXPECT_EQ(q, 1'b0, "short glitch rejected");

        // Stable high for SC cycles -> q goes high.
        d = 1;
        for (i = 0; i < SC; i = i + 1) @(posedge clk);
        @(posedge clk); #1;
        `EXPECT_EQ(q, 1'b1, "stable high accepted");

        // Stable low again.
        d = 0;
        repeat (SC+2) @(posedge clk); #1;
        `EXPECT_EQ(q, 1'b0, "stable low accepted");

        `TB_FINISH("tb_debounce");
    end
endmodule

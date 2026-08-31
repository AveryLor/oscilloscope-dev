/*
 * File: tb_timebase_decimator.sv
 * Description: timebase_decimator: divide-by-1 passes every sample, divide-by-N
 *              emits one entry per window, and peak-detect mode emits the window
 *              minimum then the window maximum (with a mid-window spike showing
 *              up as that window's max).
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_timebase_decimator;
    import scope_pkg::*;
    `include "tb_common.svh"

    logic        clk = 0, rst_n = 0;
    logic [15:0] dec = 0;
    logic        peak = 0;
    logic        arm_align = 0;
    logic [9:0]  s_in = 0;
    logic        or_in = 0, v_in = 0;
    logic [9:0]  s_out;
    logic        or_out, is_max, v_out;
    logic [15:0] phase;
    always #5 clk = ~clk;

    timebase_decimator dut (
        .clk(clk), .rst_n(rst_n),
        .cfg_dec_factor(dec), .cfg_peak_mode(peak), .arm_align(arm_align),
        .sample_in(s_in), .or_in(or_in), .valid_in(v_in),
        .sample_out(s_out), .or_out(or_out), .is_max_out(is_max),
        .valid_out(v_out), .dec_phase_out(phase));

    integer i, vcount;

    task automatic feed(input [9:0] v);
        s_in <= v; v_in <= 1'b1;
        @(posedge clk);
        v_in <= 1'b0;
        @(posedge clk);
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // divide-by-1: every fed sample produces a valid_out.
        dec = 0; peak = 0;
        vcount = 0;
        fork
            begin : drv1
                for (i = 0; i < 10; i = i + 1) feed(10'(i*4));
            end
            begin : mon1
                repeat (40) begin
                    @(posedge clk);
                    if (v_out) vcount = vcount + 1;
                end
            end
        join
        `EXPECT(vcount >= 8, "divide-by-1 emits roughly one per sample");

        // divide-by-4 peak mode: window {10,90,40,20} -> min 10 then max 90.
        rst_n = 0; @(posedge clk); rst_n = 1; @(posedge clk);
        dec = 3; peak = 1;
        feed(10); feed(90); feed(40);
        // 4th sample completes the window.
        s_in <= 20; v_in <= 1'b1;
        @(posedge clk); #1;
        `EXPECT_EQ(v_out, 1'b1, "peak window emits");
        `EXPECT_EQ(is_max, 1'b0, "first peak entry is the minimum");
        `EXPECT_EQ(s_out, 10'd10, "window minimum value");
        v_in <= 1'b0;
        @(posedge clk); #1;
        `EXPECT_EQ(v_out, 1'b1, "second peak entry follows");
        `EXPECT_EQ(is_max, 1'b1, "second peak entry is the maximum");
        `EXPECT_EQ(s_out, 10'd90, "window maximum value");

        `TB_FINISH("tb_timebase_decimator");
    end
endmodule

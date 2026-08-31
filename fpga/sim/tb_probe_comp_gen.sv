/*
 * File: tb_probe_comp_gen.sv
 * Description: probe_comp_gen toggles every half_period clocks, uses DEFAULT_HALF
 *              when cfg_div is 0, follows a programmed divisor, and parks low
 *              when cfg_en is deasserted.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_probe_comp_gen;
    `include "tb_common.svh"

    logic        clk = 0, rst_n = 0;
    logic [15:0] div = 16'd0;
    logic        en = 1;
    logic        sq;
    always #5 clk = ~clk;

    probe_comp_gen #(.DIV_W(16), .DEFAULT_HALF(4)) dut (
        .clk(clk), .rst_n(rst_n), .cfg_div(div), .cfg_en(en), .sq_out(sq));

    integer t0, t1;

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;

        // Default divisor: half period = 4 clocks.
        @(posedge sq);
        t0 = $time;
        @(posedge sq);
        t1 = $time;
        `EXPECT_EQ((t1 - t0), 80, "default full period = 2 * 4 clocks (80 ns)");

        // Programmed divisor: half period = 6 clocks.
        div = 16'd6;
        repeat (24) @(posedge clk);   // let the new divisor settle
        @(posedge sq);
        t0 = $time;
        @(posedge sq);
        t1 = $time;
        `EXPECT_EQ((t1 - t0), 120, "programmed full period = 2 * 6 clocks");

        // Disable parks the output low.
        en = 0;
        repeat (20) @(posedge clk); #1;
        `EXPECT_EQ(sq, 1'b0, "output parked low when disabled");

        `TB_FINISH("tb_probe_comp_gen");
    end
endmodule

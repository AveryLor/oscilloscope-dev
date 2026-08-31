/*
 * File: tb_capture_buffer.sv
 * Description: capture_buffer with a small depth: free-running writes wrap the
 *              ring, trig_pulse latches the pointer, exactly cfg_post_count more
 *              entries are written, the record then freezes, and a logical-order
 *              read of the record returns the samples written in that window.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_capture_buffer;
    import scope_pkg::*;
    `include "tb_common.svh"

    localparam int DEPTH = 32;
    localparam int AW    = 5;
    localparam int CW    = SCOPE_CNT_W;

    logic              clk = 0, rst_n = 0;
    logic              start = 0, abort = 0, run = 0, wr_en = 0;
    logic [SCOPE_DW-1:0] wr_data = 0;
    logic              trig = 0;
    logic [CW-1:0]     pre = 8, post = 8;
    logic              frozen_w, triggered_w;
    logic [AW-1:0]     rec_start;
    logic [CW-1:0]     rec_count, rec_trig_off, valid_count;
    logic [15:0]       oravg;
    logic [AW-1:0]     rd_addr = 0;
    logic              rd_en = 0;
    logic [SCOPE_DW-1:0] rd_data;
    always #5 clk = ~clk;

    capture_buffer #(.DEPTH(DEPTH)) dut (
        .wr_clk(clk), .wr_rst_n(rst_n),
        .start(start), .abort(abort), .run(run),
        .wr_en(wr_en), .wr_data(wr_data), .trig_pulse(trig),
        .cfg_pre_count(pre), .cfg_post_count(post),
        .frozen_w(frozen_w), .triggered_w(triggered_w),
        .rec_start(rec_start), .rec_count(rec_count),
        .rec_trig_off(rec_trig_off), .valid_count(valid_count),
        .overrange_cnt(oravg),
        .rd_clk(clk), .rd_addr(rd_addr), .rd_en(rd_en), .rd_data(rd_data));

    integer k, a;
    logic [9:0] expv;

    task automatic wbeat(input integer val, input logic do_trig);
        wr_data = val[SCOPE_DW-1:0];
        wr_en   = 1'b1;
        trig    = do_trig;
        @(posedge clk); #1;
        wr_en = 1'b0;
        trig  = 1'b0;
        @(posedge clk); #1;
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        start = 1; @(posedge clk); #1; start = 0;
        run = 1;

        // 40 writes, trigger on the 41st (index 40 -> wr_ptr = 8).
        for (k = 0; k < 40; k = k + 1) wbeat(k, 1'b0);
        `EXPECT_EQ(frozen_w, 1'b0, "not frozen before trigger");
        wbeat(40, 1'b1);                       // trigger sample
        for (k = 41; k < 49; k = k + 1) wbeat(k, 1'b0);

        // Give the freeze a cycle to register.
        @(posedge clk); #1;
        `EXPECT_EQ(frozen_w, 1'b1, "frozen after post-trigger tail");
        `EXPECT_EQ(rec_count, CW'(16), "record length = pre + post");
        `EXPECT_EQ(rec_trig_off, CW'(8), "trigger offset = pre_used");
        `EXPECT_EQ(rec_start, AW'(0), "record start = trig_ptr - pre_used");

        // Logical-order read of the 16 entries: addresses 0..15 hold the last
        // writes to those slots, i.e. values 32..47.
        for (a = 0; a < 16; a = a + 1) begin
            rd_addr = rec_start + a[AW-1:0];
            rd_en   = 1'b1;
            @(posedge clk); #1;
            expv = (32 + a);
            `EXPECT_EQ(rd_data[9:0], expv, "record entry value");
        end
        rd_en = 1'b0;

        `TB_FINISH("tb_capture_buffer");
    end
endmodule

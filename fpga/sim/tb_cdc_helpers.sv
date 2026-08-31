/*
 * File: tb_cdc_helpers.sv
 * Description: Exercises cdc_pulse_toggle (one destination pulse per source
 *              pulse), cdc_gray_sync round-trip of an up/down counter, and
 *              async_fifo lossless first-word-fall-through transfer across a
 *              fast-write / slow-read clock ratio.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_cdc_helpers;
    `include "tb_common.svh"

    logic aclk = 0, bclk = 0;
    logic arst_n = 0, brst_n = 0;
    always #5  aclk = ~aclk;   // 100 MHz
    always #17 bclk = ~bclk;   // ~29 MHz

    initial begin
        repeat (4) @(posedge aclk);
        arst_n = 1;
        repeat (4) @(posedge bclk);
        brst_n = 1;
    end

    // ---- cdc_pulse_toggle -------------------------------------------------
    logic   src_pulse = 0;
    logic   dst_pulse;
    integer dst_count = 0;

    cdc_pulse_toggle u_pt (
        .src_clk(aclk), .src_rst_n(arst_n), .src_pulse(src_pulse),
        .dst_clk(bclk), .dst_rst_n(brst_n), .dst_pulse(dst_pulse));

    always @(posedge bclk) if (dst_pulse) dst_count <= dst_count + 1;

    // ---- cdc_gray_sync -------------------------------------------------
    logic [7:0] gsrc = 0;
    logic [7:0] gdst;
    cdc_gray_sync #(.WIDTH(8)) u_gs (
        .src_clk(aclk), .src_rst_n(arst_n), .src_bin(gsrc),
        .dst_clk(bclk), .dst_rst_n(brst_n), .dst_bin(gdst));

    // ---- async_fifo ---------------------------------------------------
    logic       f_wr = 0, f_rd = 0;
    logic [7:0] f_wdata = 0, f_rdata;
    logic       f_full, f_empty;
    async_fifo #(.DW(8), .DEPTH(8)) u_ff (
        .wr_clk(aclk), .wr_rst_n(arst_n), .wr_en(f_wr), .wr_data(f_wdata), .full(f_full),
        .rd_clk(bclk), .rd_rst_n(brst_n), .rd_en(f_rd), .rd_data(f_rdata), .empty(f_empty));

    integer i;
    initial begin
        wait (arst_n && brst_n);
        repeat (4) @(posedge aclk);

        // pulse_toggle: 5 well-spaced source pulses -> 5 dst pulses.
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge aclk); src_pulse <= 1;
            @(posedge aclk); src_pulse <= 0;
            repeat (8) @(posedge bclk);
        end
        `EXPECT_EQ(dst_count, 5, "one dst pulse per src pulse");

        // gray_sync: ramp up then down, check destination tracks after settling.
        for (i = 0; i < 20; i = i + 1) begin @(posedge aclk); gsrc <= gsrc + 1; end
        repeat (8) @(posedge bclk);
        `EXPECT_EQ(gdst, 8'd20, "gray sync tracked ramp up");
        for (i = 0; i < 8; i = i + 1) begin @(posedge aclk); gsrc <= gsrc - 1; end
        repeat (8) @(posedge bclk);
        `EXPECT_EQ(gdst, 8'd12, "gray sync tracked ramp down");

        // async_fifo: push 6 values fast, drain slow, first-word-fall-through.
        for (i = 0; i < 6; i = i + 1) begin
            @(posedge aclk); f_wr <= 1; f_wdata <= 8'hA0 + i;
        end
        @(posedge aclk); f_wr <= 0;

        for (i = 0; i < 6; i = i + 1) begin
            while (f_empty) @(posedge bclk);
            #1 `EXPECT_EQ(f_rdata, 8'hA0 + i, "fifo value in order");
            @(negedge bclk) f_rd = 1;
            @(negedge bclk) f_rd = 0;
        end
        `TB_FINISH("tb_cdc_helpers");
    end
endmodule

/*
 * File: tb_config_cdc.sv
 * Description: config_cdc delivers new data to the destination only after the
 *              commit toggle crosses, pulses dst_update exactly once per commit,
 *              and leaves dst_data unchanged when no commit occurs.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_config_cdc;
    `include "tb_common.svh"

    logic sclk = 0, dclk = 0;
    logic drst_n = 0;
    always #7  sclk = ~sclk;
    always #5  dclk = ~dclk;

    logic [15:0] sdata = 16'hBEEF;
    logic        scommit = 0;
    logic [15:0] ddata;
    logic        dupd;
    integer      upd_count = 0;

    config_cdc #(.WIDTH(16)) dut (
        .src_data(sdata), .src_commit(scommit),
        .dst_clk(dclk), .dst_rst_n(drst_n),
        .dst_data(ddata), .dst_update(dupd));

    always @(posedge dclk) if (dupd) upd_count <= upd_count + 1;

    initial begin
        repeat (4) @(posedge dclk);
        drst_n = 1;
        repeat (8) @(posedge dclk);
        `EXPECT_EQ(upd_count, 0, "no update before any commit");

        // First commit.
        @(posedge sclk) sdata <= 16'h1234;
        @(posedge sclk) scommit <= ~scommit;
        repeat (10) @(posedge dclk);
        `EXPECT_EQ(ddata, 16'h1234, "data crossed after commit");
        `EXPECT_EQ(upd_count, 1, "one update pulse");

        // No commit -> data holds even though src changes.
        @(posedge sclk) sdata <= 16'h5555;
        repeat (10) @(posedge dclk);
        `EXPECT_EQ(ddata, 16'h1234, "data unchanged without commit");
        `EXPECT_EQ(upd_count, 1, "still one update");

        // Second commit.
        @(posedge sclk) scommit <= ~scommit;
        repeat (10) @(posedge dclk);
        `EXPECT_EQ(ddata, 16'h5555, "second commit crossed");
        `EXPECT_EQ(upd_count, 2, "two updates");

        `TB_FINISH("tb_config_cdc");
    end
endmodule

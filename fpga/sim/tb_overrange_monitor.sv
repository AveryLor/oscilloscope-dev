/*
 * File: tb_overrange_monitor.sv
 * Description: overrange_monitor trips only when a window's over-range count
 *              reaches cfg_thr/256 of the window: a single over-range sample
 *              sets `active` but does not trip; a sustained burst does; a
 *              threshold of 0 disables tripping; a config update restarts the
 *              window.
 */

`timescale 1ns/1ps

module tb_overrange_monitor;
    import scope_pkg::*;
    `include "tb_common.svh"

    logic       clk = 0, rst_n = 0;
    logic       valid = 1, or_in = 0;
    logic [4:0] win = 5'd10;           // 1024-sample window (the minimum)
    logic [7:0] thr = 8'd16;           // 16/256 -> 64 samples
    logic       upd = 0;
    logic       trip, active;
    always #5 clk = ~clk;

    overrange_monitor dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid), .or_in(or_in),
        .cfg_win_log2(win), .cfg_thr(thr), .cfg_update(upd),
        .trip_pulse(trip), .active(active));

    integer trips = 0;
    always @(posedge clk) if (trip) trips = trips + 1;

    // Drive one full window: `n_or` over-range samples at the start.
    task automatic window(input integer n_or);
        integer i;
        for (i = 0; i < 1024; i = i + 1) begin
            or_in = (i < n_or);
            @(posedge clk); #1;
        end
        or_in = 0;
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk); #1;
        // Restart cleanly on a window boundary.
        upd = 1; @(posedge clk); #1; upd = 0;

        trips = 0;
        window(1);
        repeat (2) @(posedge clk); #1;
        `EXPECT_EQ(trips, 0, "single OR sample does not trip");
        `EXPECT_EQ(active, 1'b1, "single OR sample sets active");

        trips = 0;
        window(63);
        repeat (2) @(posedge clk); #1;
        `EXPECT_EQ(trips, 0, "63/1024 is below 16/256");

        trips = 0;
        window(64);
        repeat (2) @(posedge clk); #1;
        `EXPECT_EQ(trips, 1, "64/1024 reaches 16/256 and trips once");

        trips = 0;
        window(0);
        repeat (2) @(posedge clk); #1;
        `EXPECT_EQ(trips, 0, "clean window does not trip");
        `EXPECT_EQ(active, 1'b0, "clean window clears active");

        thr = 8'd0;
        upd = 1; @(posedge clk); #1; upd = 0;
        trips = 0;
        window(1024);
        repeat (2) @(posedge clk); #1;
        `EXPECT_EQ(trips, 0, "threshold 0 disables tripping");

        // A window value below the minimum clamps to 2**10.
        thr = 8'd16; win = 5'd3;
        upd = 1; @(posedge clk); #1; upd = 0;
        trips = 0;
        window(64);
        repeat (2) @(posedge clk); #1;
        `EXPECT_EQ(trips, 1, "window clamps to the 1024-sample minimum");

        `TB_FINISH("tb_overrange_monitor");
    end
endmodule

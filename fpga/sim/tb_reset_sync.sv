/*
 * File: tb_reset_sync.sv
 * Description: reset_sync asserts rst_n low immediately when arst_n falls and
 *              releases it exactly STAGES clocks after arst_n rises.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_reset_sync;
    `include "tb_common.svh"

    localparam int STAGES = 3;

    logic clk = 0;
    logic arst_n = 0;
    logic rst_n;
    always #5 clk = ~clk;

    reset_sync #(.STAGES(STAGES)) dut (.clk(clk), .arst_n(arst_n), .rst_n(rst_n));

    `TB_DUMP("build/tb_reset_sync.vcd")

    integer i;
    initial begin
        repeat (3) @(posedge clk);
        `EXPECT_EQ(rst_n, 1'b0, "held in reset while arst_n low");

        @(negedge clk);
        arst_n = 1'b1;
        for (i = 0; i < STAGES; i = i + 1) begin
            @(posedge clk); #1;
            if (i < STAGES-1)
                `EXPECT_EQ(rst_n, 1'b0, "not yet released");
        end
        `EXPECT_EQ(rst_n, 1'b1, "released after STAGES clocks");

        // Async assert is immediate.
        @(negedge clk);
        arst_n = 1'b0;
        #1;
        `EXPECT_EQ(rst_n, 1'b0, "async assert is immediate");

        `TB_FINISH("tb_reset_sync");
    end
endmodule

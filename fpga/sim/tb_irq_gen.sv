/*
 * File: tb_irq_gen.sv
 * Description: irq_gen sets and holds irq_out on an edge of the capture-domain
 *              toggle, clears it on irq_clr or arm_seen, and does not glitch high
 *              out of reset.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_irq_gen;
    `include "tb_common.svh"

    logic clk = 0, rst_n = 0;
    logic tog = 0, clr = 0, arm = 0;
    logic irq_out, irq_level;
    always #5 clk = ~clk;

    irq_gen dut (
        .clk(clk), .rst_n(rst_n),
        .irq_toggle_cap(tog), .irq_clr(clr), .arm_seen(arm),
        .irq_out(irq_out), .irq_level(irq_level));

    initial begin
        repeat (3) @(posedge clk);
        `EXPECT_EQ(irq_out, 1'b0, "no glitch out of reset");
        rst_n = 1;
        repeat (4) @(posedge clk); #1;
        `EXPECT_EQ(irq_out, 1'b0, "idle low");

        // Toggle edge raises and holds irq.
        tog = ~tog; @(posedge clk);
        repeat (6) @(posedge clk); #1;
        `EXPECT_EQ(irq_out, 1'b1, "irq raised on toggle edge");
        `EXPECT_EQ(irq_level, 1'b1, "irq_level mirrors irq_out");
        repeat (10) @(posedge clk); #1;
        `EXPECT_EQ(irq_out, 1'b1, "irq held until acknowledged");

        // Acknowledge clears it.
        clr = 1; @(posedge clk); #1; clr = 0;
        `EXPECT_EQ(irq_out, 1'b0, "irq cleared by irq_clr");

        // Another toggle, then clear via arm_seen.
        tog = ~tog; @(posedge clk);
        repeat (6) @(posedge clk); #1;
        `EXPECT_EQ(irq_out, 1'b1, "irq raised again");
        arm = 1; @(posedge clk); #1; arm = 0;
        `EXPECT_EQ(irq_out, 1'b0, "irq cleared by arm_seen");

        `TB_FINISH("tb_irq_gen");
    end
endmodule

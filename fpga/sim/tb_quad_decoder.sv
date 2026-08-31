/*
 * File: tb_quad_decoder.sv
 * Description: quad_decoder counts +1 per forward detent and -1 per reverse
 *              detent (one count per full A/B cycle back to the rest state), and
 *              turns a debounced button press into a single latched event that
 *              clears on btn_event_clr.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_quad_decoder;
    `include "tb_common.svh"

    logic clk = 0, rst_n = 0;
    logic a = 1, b = 1, btn = 1;
    logic signed [15:0] count;
    logic [15:0]        count_gray;
    logic               btn_level, btn_event;
    logic               btn_clr = 0;
    always #5 clk = ~clk;

    quad_decoder #(.CNT_W(16), .DEBOUNCE_CYC(2)) dut (
        .clk(clk), .rst_n(rst_n),
        .a_raw(a), .b_raw(b), .btn_raw(btn),
        .count(count), .count_gray(count_gray),
        .btn_level(btn_level), .btn_event(btn_event), .btn_event_clr(btn_clr));

    task automatic hold(input integer n);
        repeat (n) @(posedge clk);
    endtask

    // Forward detent: rest (a,b)=(1,1) -> (1,0) -> (0,0) -> (0,1) -> (1,1).
    // The step just before the rest return has {b,a} = 2'b10 -> +1.
    task automatic detent_fwd;
        a = 1; b = 0; hold(6);
        a = 0; b = 0; hold(6);
        a = 0; b = 1; hold(6);
        a = 1; b = 1; hold(6);
    endtask

    // Reverse detent: rest (1,1) -> (0,1) -> (0,0) -> (1,0) -> (1,1).
    // The step just before rest has {b,a} = 2'b01 -> -1.
    task automatic detent_rev;
        a = 0; b = 1; hold(6);
        a = 0; b = 0; hold(6);
        a = 1; b = 0; hold(6);
        a = 1; b = 1; hold(6);
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        hold(4);

        detent_fwd(); detent_fwd(); detent_fwd();
        `EXPECT_EQ(count, 16'sd3, "three forward detents = +3");

        detent_rev();
        `EXPECT_EQ(count, 16'sd2, "one reverse detent = +2");

        // Button press -> one event, held until cleared.
        btn = 0; hold(6);
        `EXPECT_EQ(btn_level, 1'b1, "button level asserted when pressed");
        `EXPECT_EQ(btn_event, 1'b1, "press event latched");
        btn = 1; hold(6);
        `EXPECT_EQ(btn_event, 1'b1, "event stays until cleared");
        btn_clr = 1; @(posedge clk); #1; btn_clr = 0;
        `EXPECT_EQ(btn_event, 1'b0, "event cleared");

        `TB_FINISH("tb_quad_decoder");
    end
endmodule

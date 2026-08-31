/*
 * File: tb_trigger_engine.sv
 * Description: trigger_engine: a rising-edge level trigger fires on the sample
 *              that crosses the threshold, only after re-arming below
 *              level - hyst; dithering near the threshold does not re-fire; the
 *              external and force paths work; armed = 0 inhibits all sources.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_trigger_engine;
    import scope_pkg::*;
    `include "tb_common.svh"

    logic        clk = 0, rst_n = 0;
    logic [9:0]  s_in = 0;
    logic        v_in = 1;
    logic        ext = 0;
    logic [1:0]  src = 2'd0;   // level
    logic [1:0]  edg = 2'd0;   // rising
    logic [9:0]  level = 10'd500;
    logic [7:0]  hyst = 8'd16;
    logic        armed = 1;
    logic        force_t = 0;
    logic        pulse;
    always #5 clk = ~clk;

    trigger_engine dut (
        .clk(clk), .rst_n(rst_n),
        .sample_in(s_in), .valid_in(v_in), .ext_trig_sync(ext),
        .cfg_src(src), .cfg_edge(edg), .cfg_level(level), .cfg_hyst(hyst),
        .armed(armed), .force_trig(force_t), .trig_pulse(pulse));

    integer fire_count = 0;
    always @(posedge clk) if (pulse) fire_count = fire_count + 1;

    // Apply one sample and settle so trig_pulse (registered) is countable.
    task automatic put(input [9:0] v);
        s_in = v;
        @(posedge clk);
        #1;
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #1;

        put(400); put(400); put(450);   // prime below level - hyst
        fire_count = 0;
        put(480); put(495);
        `EXPECT_EQ(fire_count, 0, "no trigger before crossing");
        put(505);                        // 495 -> 505 crosses 500
        put(505);                        // settle a cycle so the count lands
        `EXPECT_EQ(fire_count, 1, "fired on the crossing sample");

        // Dither above threshold without re-arming: no re-fire.
        put(520); put(498); put(512); put(505);
        `EXPECT_EQ(fire_count, 1, "no re-fire without re-arm");

        // Re-arm below level - hyst, then cross again.
        put(470); put(450); put(300);
        put(600); put(600);
        `EXPECT_EQ(fire_count, 2, "fired again after re-arm");

        // armed = 0 inhibits.
        armed = 0;
        put(300); put(700); put(700);
        `EXPECT_EQ(fire_count, 2, "armed=0 inhibits level trigger");
        armed = 1;

        // Force path fires next cycle regardless of level state.
        fire_count = 0;
        force_t = 1; @(posedge clk); #1; force_t = 0;
        @(posedge clk); #1;
        `EXPECT_EQ(fire_count, 1, "force_trig fired");

        // External rising-edge trigger.
        src = 2'd1;
        fire_count = 0;
        ext = 0; @(posedge clk); #1;
        ext = 1; @(posedge clk); #1;
        @(posedge clk); #1;
        `EXPECT_EQ(fire_count, 1, "external rising edge fired");

        `TB_FINISH("tb_trigger_engine");
    end
endmodule

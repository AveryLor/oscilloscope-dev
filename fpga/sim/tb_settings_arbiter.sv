/*
 * File: tb_settings_arbiter.sv
 * Description: settings_arbiter applies host register writes to the effective
 *              config, turns a CONTROL write-1 bit into a command pulse, applies
 *              a trigger-encoder detent as a LEVEL_STEP change to trig_level, and
 *              flips commit_tog on every change.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_settings_arbiter;
    import scope_pkg::*;
    `include "tb_common.svh"

    logic        clk = 0, rst_n = 0;
    logic        wr_pending = 0;
    logic [6:0]  wr_addr = 0;
    logic [7:0]  wr_data = 0;
    logic        wr_pop;
    logic        ta = 1, tb_ = 1, tbtn = 1;
    logic        ha = 1, hb = 1, hbtn = 1;
    logic        oa = 1, ob = 1, obtn = 1;
    logic        enc_btn_clr = 0;
    scope_cfg_t  cfg;
    logic [15:0] probe_div;
    logic        probe_en;
    logic        commit_tog;
    logic        cmd_arm, cmd_abort, cmd_force, cmd_irq_clr, cmd_soft_reset;
    logic [15:0] enc_hs, enc_ho, enc_tg;
    logic [5:0]  enc_btn;
    always #5 clk = ~clk;

    settings_arbiter #(.DEPTH(16384), .LEVEL_STEP(8), .ENC_DEBOUNCE(2)) dut (
        .clk(clk), .rst_n(rst_n),
        .wr_pending(wr_pending), .wr_addr(wr_addr), .wr_data(wr_data), .wr_pop(wr_pop),
        .dial_hs_a(ha), .dial_hs_b(hb), .dial_hs_btn(hbtn),
        .dial_ho_a(oa), .dial_ho_b(ob), .dial_ho_btn(obtn),
        .dial_tg_a(ta), .dial_tg_b(tb_), .dial_tg_btn(tbtn),
        .enc_btn_clr(enc_btn_clr),
        .cfg_o(cfg), .probe_div_o(probe_div), .probe_en_o(probe_en),
        .commit_tog(commit_tog),
        .cmd_arm(cmd_arm), .cmd_abort(cmd_abort), .cmd_force(cmd_force),
        .cmd_irq_clr(cmd_irq_clr), .cmd_soft_reset(cmd_soft_reset),
        .enc_hs_cnt(enc_hs), .enc_ho_cnt(enc_ho), .enc_tg_cnt(enc_tg),
        .enc_btn(enc_btn));

    task automatic host_write(input [6:0] a, input [7:0] d);
        wr_addr = a; wr_data = d; wr_pending = 1'b1;
        wait (wr_pop == 1'b1);
        @(posedge clk); #1;
        wr_pending = 1'b0;
        @(posedge clk); #1;
    endtask

    task automatic tg_detent_fwd;
        ta = 1; tb_ = 0; repeat (8) @(posedge clk);
        ta = 0; tb_ = 0; repeat (8) @(posedge clk);
        ta = 0; tb_ = 1; repeat (8) @(posedge clk);
        ta = 1; tb_ = 1; repeat (8) @(posedge clk);
    endtask

    integer arm_count = 0;
    always @(posedge clk) if (cmd_arm) arm_count = arm_count + 1;

    logic ct0;
    logic [9:0] lvl0;

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk); #1;
        `EXPECT_EQ(cfg.trig_level, 10'h200, "default trig_level");

        // Host write DEC_FACTOR = 0x1234 (LE). Each accepted write flips
        // commit_tog, so one write leaves it inverted.
        ct0 = commit_tog;
        host_write(7'h10, 8'h34);
        repeat (2) @(posedge clk); #1;
        `EXPECT(commit_tog !== ct0, "commit toggled after a write");
        host_write(7'h11, 8'h12);
        repeat (2) @(posedge clk); #1;
        `EXPECT_EQ(cfg.dec_factor, 16'h1234, "dec_factor written LE");

        // CONTROL write with ARM bit -> cmd_arm pulse.
        arm_count = 0;
        host_write(7'h08, 8'h01);
        repeat (2) @(posedge clk); #1;
        `EXPECT_EQ(arm_count, 1, "ARM bit produced one cmd_arm pulse");

        // Trigger encoder forward detent -> trig_level + LEVEL_STEP.
        lvl0 = cfg.trig_level;
        tg_detent_fwd();
        repeat (4) @(posedge clk); #1;
        `EXPECT_EQ(cfg.trig_level, lvl0 + 10'd8, "detent bumped trig_level by LEVEL_STEP");

        `TB_FINISH("tb_settings_arbiter");
    end
endmodule

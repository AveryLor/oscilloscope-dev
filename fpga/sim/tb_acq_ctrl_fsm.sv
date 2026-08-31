/*
 * File: tb_acq_ctrl_fsm.sv
 * Description: acq_ctrl_fsm sequencing: IDLE -> PREFILL (waits for pre_count) ->
 *              WAIT_TRIG -> POST_TRIG -> FROZEN, the re-arm handshake, an
 *              AUTO-mode timeout forcing a trigger, and abort from mid-capture.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_acq_ctrl_fsm;
    import scope_pkg::*;
    `include "tb_common.svh"

    localparam int CW = SCOPE_CNT_W;

    logic          clk = 0, rst_n = 0;
    logic [1:0]    mode = 2'(ACQ_MODE_NORMAL);
    logic [CW-1:0] pre = 20'd16;
    logic [31:0]   tmo = 32'd0;
    logic          auto_rearm = 0;
    logic          arm = 0, abrt = 0, force_s = 0;
    logic          trig = 0;
    logic [CW-1:0] vcount = 0;
    logic          frozen = 0;
    logic          rearm_req, rearm_ack = 0;
    logic          buf_start, buf_abort, run, arm_align, armed, force_trig;
    logic [2:0]    state;
    logic          trigd_auto, irq_tog;
    always #5 clk = ~clk;

    acq_ctrl_fsm dut (
        .clk(clk), .rst_n(rst_n),
        .cfg_mode(mode), .cfg_pre_count(pre), .cfg_auto_timeout(tmo),
        .cfg_auto_rearm(auto_rearm),
        .arm_stb(arm), .abort_stb(abrt), .force_trig_stb(force_s),
        .trig_pulse(trig), .valid_count(vcount), .frozen_w(frozen),
        .rearm_req(rearm_req), .rearm_ack(rearm_ack),
        .buf_start(buf_start), .buf_abort(buf_abort), .run(run),
        .arm_align(arm_align), .armed(armed), .force_trig(force_trig),
        .state_out(state), .triggered_by_auto(trigd_auto), .irq_toggle(irq_tog));

    `define PULSE(s) begin s = 1'b1; @(posedge clk); #1; s = 1'b0; end

    logic irq_prev;

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #1;
        `EXPECT_EQ(state, 3'(ACQ_ST_IDLE), "starts IDLE");

        // Arm -> PREFILL.
        `PULSE(arm)
        @(posedge clk); #1;
        `EXPECT_EQ(state, 3'(ACQ_ST_PREFILL), "armed -> PREFILL");
        `EXPECT_EQ(run, 1'b1, "run asserted while filling");

        // Not enough samples yet.
        vcount = 20'd10;
        repeat (4) @(posedge clk); #1;
        `EXPECT_EQ(state, 3'(ACQ_ST_PREFILL), "waits for pre_count");

        // Prefill satisfied -> WAIT_TRIG.
        vcount = 20'd16;
        @(posedge clk); #1;
        `EXPECT_EQ(state, 3'(ACQ_ST_WAIT_TRIG), "prefill done -> WAIT_TRIG");
        `EXPECT_EQ(armed, 1'b1, "armed in WAIT_TRIG");

        // Trigger -> POST_TRIG.
        irq_prev = irq_tog;
        `PULSE(trig)
        @(posedge clk); #1;
        `EXPECT_EQ(state, 3'(ACQ_ST_POST_TRIG), "trigger -> POST_TRIG");
        `EXPECT_EQ(armed, 1'b0, "not armed in POST_TRIG");

        // Buffer freezes -> FROZEN, irq toggles once.
        frozen = 1'b1;
        @(posedge clk); #1;
        `EXPECT_EQ(state, 3'(ACQ_ST_FROZEN), "frozen -> FROZEN");
        `EXPECT(irq_tog !== irq_prev, "irq_toggle flipped once at freeze");

        // Host re-arm -> handshake -> PREFILL. Drop the fill count so PREFILL
        // holds long enough to observe.
        vcount = 20'd0;
        `PULSE(arm)
        @(posedge clk); #1;
        `EXPECT(rearm_req === 1'b1 || state == 3'(ACQ_ST_ARMED),
                "rearm requested");
        `PULSE(rearm_ack)
        frozen = 1'b0;
        @(posedge clk); #1;
        `EXPECT_EQ(state, 3'(ACQ_ST_PREFILL), "rearm ack -> PREFILL");

        // Abort from mid-capture.
        `PULSE(abrt)
        @(posedge clk); #1;
        `EXPECT_EQ(state, 3'(ACQ_ST_IDLE), "abort -> IDLE");
        `EXPECT_EQ(buf_abort, 1'b0, "buf_abort is a one-shot");

        // AUTO mode: timeout forces a trigger.
        mode = 2'(ACQ_MODE_AUTO);
        tmo  = 32'd20;
        vcount = 20'd16;
        `PULSE(arm)
        // PREFILL passes immediately (vcount already >= pre), then WAIT_TRIG.
        repeat (3) @(posedge clk); #1;
        `EXPECT_EQ(state, 3'(ACQ_ST_WAIT_TRIG), "AUTO in WAIT_TRIG");
        // Wait out the timeout; expect force_trig, then feed the trig_pulse.
        repeat (25) @(posedge clk);
        @(posedge clk); trig = 1'b1; @(posedge clk); #1; trig = 1'b0;
        @(posedge clk); #1;
        `EXPECT_EQ(state, 3'(ACQ_ST_POST_TRIG), "AUTO timeout advanced");
        `EXPECT_EQ(trigd_auto, 1'b1, "triggered_by_auto set");

        `TB_FINISH("tb_acq_ctrl_fsm");
    end
endmodule

/*
 * File: tb_acq_rearm.sv
 * Description: acq_ctrl_fsm wired to a real capture_buffer, two captures back
 *              to back. Regression for the re-arm prefill skip: on a re-arm the
 *              FSM entered PREFILL one cycle before buf_start reset the
 *              buffer's valid_count, saw the previous capture's (full) count,
 *              and started accepting triggers with an empty pre-trigger window.
 *              The second record then came back short (pre_used < pre_count)
 *              and its trigger offset varied capture to capture.
 */

`timescale 1ns/1ps

module tb_acq_rearm;
    import scope_pkg::*;
    `include "tb_common.svh"

    localparam int CW    = SCOPE_CNT_W;
    localparam int DEPTH = 64;
    localparam int AW    = $clog2(DEPTH);
    localparam int PRE   = 16;
    localparam int POST  = 16;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic          arm = 0, rearm_ack = 0;
    logic          trig;
    logic          buf_start, buf_abort, run, arm_align, armed, force_trig;
    logic          rearm_req, frozen_w, triggered_w, trigd_auto, irq_tog;
    logic [2:0]    state;
    logic [CW-1:0] valid_count, rec_count, rec_trig_off;
    logic [AW-1:0] rec_start;
    logic [15:0]   overrange_cnt;
    logic [SCOPE_DW-1:0] rd_data;

    acq_ctrl_fsm fsm (
        .clk(clk), .rst_n(rst_n),
        .cfg_mode(2'(ACQ_MODE_NORMAL)), .cfg_pre_count(CW'(PRE)),
        .cfg_auto_timeout(32'd0), .cfg_auto_rearm(1'b0),
        .arm_stb(arm), .abort_stb(1'b0), .force_trig_stb(1'b0),
        .trig_pulse(trig), .valid_count(valid_count), .frozen_w(frozen_w),
        .rearm_req(rearm_req), .rearm_ack(rearm_ack),
        .buf_start(buf_start), .buf_abort(buf_abort), .run(run),
        .arm_align(arm_align), .armed(armed), .force_trig(force_trig),
        .state_out(state), .triggered_by_auto(trigd_auto), .irq_toggle(irq_tog));

    capture_buffer #(.DEPTH(DEPTH)) buffer (
        .wr_clk(clk), .wr_rst_n(rst_n),
        .start(buf_start), .abort(buf_abort), .run(run),
        .wr_en(1'b1), .wr_data('0), .trig_pulse(trig),
        .cfg_pre_count(CW'(PRE)), .cfg_post_count(CW'(POST)),
        .frozen_w(frozen_w), .triggered_w(triggered_w),
        .rec_start(rec_start), .rec_count(rec_count), .rec_trig_off(rec_trig_off),
        .valid_count(valid_count), .overrange_cnt(overrange_cnt),
        .rd_clk(clk), .rd_addr('0), .rd_en(1'b0), .rd_data(rd_data));

    // Stand-in for trigger_engine: like the real one it only fires while the
    // FSM says armed, here on the first armed cycle (an input that is already
    // crossing the level when the trigger opens).
    logic armed_q;
    always_ff @(posedge clk) armed_q <= armed;
    assign trig = armed && !armed_q;

    task automatic wait_frozen(input string what);
        int n = 0;
        while (!frozen_w && n < 1000) begin @(posedge clk); n++; end
        #1;
        `EXPECT_EQ(frozen_w, 1'b1, {what, ": record froze"});
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #1;

        // Capture 1 from IDLE.
        arm = 1; @(posedge clk); #1; arm = 0;
        wait_frozen("capture 1");
        `EXPECT_EQ(rec_count,    CW'(PRE + POST), "capture 1: full record");
        `EXPECT_EQ(rec_trig_off, CW'(PRE),        "capture 1: trigger after full prefill");

        // Capture 2 via the FROZEN -> REARM_WAIT -> PREFILL re-arm path.
        arm = 1; @(posedge clk); #1; arm = 0;
        while (!rearm_req) @(posedge clk);
        #1;
        rearm_ack = 1; @(posedge clk); #1; rearm_ack = 0;
        @(posedge clk); #1;
        `EXPECT_EQ(frozen_w, 1'b0, "capture 2: buffer restarted");
        wait_frozen("capture 2");
        `EXPECT_EQ(rec_count,    CW'(PRE + POST), "capture 2: full record after re-arm");
        `EXPECT_EQ(rec_trig_off, CW'(PRE),        "capture 2: trigger after full prefill");

        `TB_FINISH("tb_acq_rearm");
    end
endmodule

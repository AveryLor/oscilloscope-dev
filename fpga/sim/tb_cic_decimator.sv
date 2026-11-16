/*
 * File: tb_cic_decimator.sv
 * Description: cic_decimator against an independent reference. The reference
 *              is the textbook definition, not a copy of the RTL structure: the
 *              impulse response is a length-R boxcar convolved with itself
 *              STAGES times, the output is that response sampled once per
 *              window and divided by R**STAGES, rounded to nearest. Every
 *              emitted sample must match it bit for bit, for power-of-two and
 *              non-power-of-two rates up to the 65536 maximum.
 *
 *              Also checked: unity DC gain at every rate, the per-window
 *              over-range flag, the fixed pipeline latency top.sv compensates
 *              for, and that arm_align / disable / a rate change flush the
 *              filter so no output blends in samples from before the flush.
 * Author: Avery Lor
 * Date: Nov 15 2026
 */

`timescale 1ns/1ps

module tb_cic_decimator;
    import scope_pkg::*;
    `include "tb_common.svh"

    localparam int N     = 2;                    // STAGES
    localparam int W     = SCOPE_CODE_W;
    localparam int LAT   = N + W + 1;            // must equal top.sv CIC_LAT
    localparam int XMAX  = 1 << 20;
    localparam int HMAX  = 1 << 18;

    logic        clk = 0, rst_n = 0;
    logic        enable = 1;
    logic [15:0] dec = 0;
    logic        arm_align = 0;
    logic [9:0]  s_in = 0;
    logic        or_in = 0, v_in = 1;
    logic [9:0]  s_out;
    logic        or_out, v_out;
    always #5 clk = ~clk;

    cic_decimator #(.STAGES(N)) dut (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .cfg_dec_factor(dec), .arm_align(arm_align),
        .sample_in(s_in), .or_in(or_in), .valid_in(v_in),
        .sample_out(s_out), .or_out(or_out), .valid_out(v_out));

    `TB_DUMP("build/tb_cic_decimator.vcd")

    // ---- Reference model -------------------------------------------------
    integer R = 1;                 // decimation rate under test
    longint G = 1;                 // R**N
    integer L = 1;                 // impulse response length
    longint h [0:HMAX-1];          // boxcar(R) convolved N times
    longint t [0:HMAX-1];

    task automatic build_model(input integer r);
        longint acc;
        integer len, nl;
        R = r;
        G = 1;
        for (int s = 0; s < N; s++) G = G * r;
        h[0] = 1;
        len  = 1;
        for (int s = 0; s < N; s++) begin
            nl  = len + r - 1;
            acc = 0;
            for (int i = 0; i < nl; i++) begin
                if (i < len)                    acc += h[i];
                if (i - r >= 0 && i - r < len)  acc -= h[i - r];
                t[i] = acc;
            end
            for (int i = 0; i < nl; i++) h[i] = t[i];
            len = nl;
        end
        L = len;
    endtask

    // ---- Stimulus ---------------------------------------------------------
    logic       rand_mode = 0;
    logic [9:0] dc_val    = 0;

    always @(negedge clk) begin
        if (rand_mode) begin
            s_in  <= 10'($urandom);
            or_in <= (($urandom % (2 * R + 1)) == 0);
        end else begin
            s_in  <= dc_val;
            or_in <= 1'b0;
        end
    end

    // ---- Monitor: log accepted inputs, check every output -----------------
    logic [9:0] x  [0:XMAX-1];     // inputs accepted since the last flush
    logic       xo [0:XMAX-1];
    integer     xc [0:XMAX-1];     // clock index each one was accepted on
    integer     n_in = 0, m_out = N, cyc = 0;
    integer     n_checked = 0, n_outputs = 0;
    integer     off_dc = 0;        // outputs that differed from expect_dc
    logic       dc_watch = 0;
    logic [9:0] expect_dc = 0;

    task automatic check_output;
        longint y;
        integer n, idx, k;
        logic   eor;
        logic [9:0] exp;
        // Output m closes window m: its last input is n. The pipelined
        // integrators add N-1 samples of delay ahead of the response.
        n   = (m_out + 1) * R - 1;
        y   = 0;
        k   = 0;
        idx = n - (N - 1);
        while (k < L && idx >= 0) begin
            y   += h[k] * longint'(x[idx]);
            k   += 1;
            idx -= 1;
        end
        exp = 10'((y + G / 2) / G);
        eor = 1'b0;
        for (int i = m_out * R; i <= n; i++) eor |= xo[i];

        `EXPECT_EQ(s_out, exp, "sample matches boxcar**N reference");
        `EXPECT_EQ(or_out, eor, "over-range flag = OR over the window");
        `EXPECT_EQ(cyc, xc[n] + 1 + LAT, "pipeline latency is PIPE_LATENCY");
        if (dc_watch && s_out !== expect_dc) off_dc = off_dc + 1;
    endtask

    always @(posedge clk) begin
        // An output in the clock a flush is requested was computed before it
        // (old rate or old window alignment), so it is not checked against
        // the new model. After that clock valid_out is masked until the
        // filter restarts.
        if (v_out && !dut.hold_c) begin
            check_output();
            m_out     = m_out + 1;
            n_checked = n_checked + 1;
            n_outputs = n_outputs + 1;
        end
        if (dut.hold) begin
            n_in  = 0;
            m_out = N;             // the first N outputs after a flush are dropped
        end else if (v_in) begin
            x[n_in]  = s_in;
            xo[n_in] = or_in;
            xc[n_in] = cyc;
            n_in     = n_in + 1;
        end
        cyc = cyc + 1;
    end

    // Wait until k more outputs have been checked.
    task automatic run_outputs(input integer k);
        integer target, guard, limit;
        target = n_checked + k;
        guard  = 0;
        limit  = (k + N + 4) * R + 400;
        while (n_checked < target && guard < limit) begin
            @(posedge clk);
            guard = guard + 1;
        end
        `EXPECT(n_checked >= target, "filter produced the expected number of outputs");
    endtask

    task automatic set_rate(input integer r);
        @(negedge clk);
        build_model(r);
        dec = 16'(r - 1);
    endtask

    // Hold the input at one level, let every sample taken before the change
    // leave the filter (N windows) and the pipeline (LAT clocks), then require
    // k outputs in a row to equal that level exactly: unity DC gain.
    task automatic test_dc(input logic [9:0] level, input integer k);
        @(negedge clk);
        rand_mode = 0;
        dc_val    = level;
        repeat ((N + 1) * R + LAT + 4) @(posedge clk);
        off_dc = 0; expect_dc = level; dc_watch = 1;
        run_outputs(k);
        dc_watch = 0;
        `EXPECT_EQ(off_dc, 0, "DC in gives the same DC out");
    endtask

    // quick: one DC level only (used at the maximum rate, where each output
    // costs 65536 clocks).
    task automatic test_rate(input integer r, input integer k_rand, input integer k_dc,
                             input logic quick);
        set_rate(r);
        rand_mode = 1;
        run_outputs(k_rand);
        test_dc(10'd1023, k_dc);
        if (!quick) begin
            test_dc(10'd0,   k_dc);
            test_dc(10'd513, k_dc);
        end
        $display("  rate %0d ok (gain %0d)", r, G);
    endtask

    integer n_before;

    initial begin
        build_model(1);
        repeat (3) @(posedge clk);
        rst_n = 1;

        test_rate(1,     60, 8, 0);
        test_rate(2,     60, 8, 0);
        test_rate(3,     60, 8, 0);    // not a power of two: needs the divider
        test_rate(8,     60, 8, 0);
        test_rate(10,    60, 8, 0);
        test_rate(100,   30, 4, 0);
        test_rate(1000,  10, 3, 0);
        test_rate(4096,  8,  3, 0);
        test_rate(65536, 3,  2, 1);    // maximum rate: full 42-bit growth

        // ---- arm_align flushes: nothing from before it leaks through --------
        set_rate(7);
        test_dc(10'd300, 6);
        // Level and arm_align change together. Apart from an output already
        // on the pins in the arm clock itself (skipped by the monitor),
        // everything emitted from here on must be 900 straight away.
        @(negedge clk);
        dc_val = 10'd900; arm_align = 1;
        off_dc = 0; expect_dc = 10'd900; dc_watch = 1;
        @(negedge clk);
        arm_align = 0;
        run_outputs(6);
        dc_watch = 0;
        `EXPECT_EQ(off_dc, 0, "after arm_align every output is the new level, no ramp");

        // ---- A rate change flushes too ------------------------------------
        set_rate(5);
        off_dc = 0; expect_dc = 10'd900; dc_watch = 1;
        run_outputs(6);
        dc_watch = 0;
        `EXPECT_EQ(off_dc, 0, "after a rate change every output is still exact");

        // ---- Disabled: silent. Re-enabled: clean restart --------------------
        @(negedge clk);
        enable = 0;
        repeat (4) @(posedge clk);
        n_before = n_outputs;
        repeat (200) @(posedge clk);
        `EXPECT_EQ(n_outputs, n_before, "no outputs while disabled");
        @(negedge clk);
        dc_val = 10'd42; enable = 1;
        off_dc = 0; expect_dc = 10'd42; dc_watch = 1;
        run_outputs(6);
        dc_watch = 0;
        `EXPECT_EQ(off_dc, 0, "re-enable restarts from a flushed filter");

        `TB_FINISH("tb_cic_decimator");
    end
endmodule

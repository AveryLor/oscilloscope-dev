/*
 * File: tb_adc_deskew.sv
 * Description: adc_deskew + adc_eye_monitor against a skewed 11-lane bus.
 *              Checks that:
 *                - iodelay_stepper walks every IODELAY to its target tap and
 *                  back down again;
 *                - with the lanes skewed across the rising sample edge and all
 *                  taps at 0, the captured words are torn (lanes from different
 *                  ADC samples);
 *                - sweeping each lane's tap and taking the eye monitor's B->A
 *                  crossover (the calibration the ESP32 runs) lands every lane
 *                  within a couple of taps of its ideal delay;
 *                - with those taps applied every captured word is whole.
 *              The model's tap is set to 0.1 ns here so the 128 taps cover a
 *              full period; on silicon the PLL phase covers the coarse part.
 * Author: Avery Lor
 * Date: Oct 7 2026
 */

`timescale 1ns/1ps

module tb_adc_deskew;
    import scope_pkg::*;
    `include "tb_common.svh"

    localparam int    N       = DESKEW_LANES;
    localparam int    TW      = DESKEW_TAP_W;
    localparam real   PER     = 10.0;   // capture / launch period
    localparam real   CAP_OFS = 3.0;    // rising sample edge, ns after launch
    localparam real   STEP    = 0.1;    // IODELAY tap in this bench
    localparam int    WIN_W   = 10;     // 1024-cycle eye windows

    // Lane skews straddle the rising sample at 3 ns, so with no deskew some
    // lanes catch the new word and some the old one.
    real skew [N];
    initial for (int k = 0; k < N; k++) skew[k] = 1.0 + 0.3 * k;

    // ---- Clocks -------------------------------------------------------------
    logic launch_clk = 0, cap_clk = 0, hk_clk = 0, hk_rst_n = 0, cap_rst_n = 0;
    always #(PER/2) launch_clk = ~launch_clk;
    initial begin
        #(CAP_OFS);
        forever #(PER/2) cap_clk = ~cap_clk;
    end
    always #18.5 hk_clk = ~hk_clk;

    // ---- Skewed bus: a fresh LFSR word every launch edge -------------------
    logic [N-1:0] word = '0;
    logic [15:0]  lfsr = 16'hACE1;
    logic [N-1:0] pad;
    logic [N-1:0] hist [8];   // hist[0] = latest launched word

    always @(posedge launch_clk) begin
        lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        word = lfsr[N-1:0];
        for (int h = 7; h > 0; h--) hist[h] = hist[h-1];
        hist[0] = word;
    end

    for (genvar k = 0; k < N; k++) begin : g_skew
        always @(word[k]) pad[k] <= #(skew[k]) word[k];
    end

    // ---- DUT ----------------------------------------------------------------
    logic [N*TW-1:0] tap_tgt = '0;
    logic [N-1:0]    rise_q, fall_q;
    logic            busy;

    adc_deskew dut (
        .pad_in(pad), .cap_clk(cap_clk), .rise_q(rise_q), .fall_q(fall_q),
        .hk_clk(hk_clk), .hk_rst_n(hk_rst_n), .tap_tgt(tap_tgt), .busy(busy));

    defparam dut.g_lane[0].u_dly.STEP_NS  = STEP;
    defparam dut.g_lane[1].u_dly.STEP_NS  = STEP;
    defparam dut.g_lane[2].u_dly.STEP_NS  = STEP;
    defparam dut.g_lane[3].u_dly.STEP_NS  = STEP;
    defparam dut.g_lane[4].u_dly.STEP_NS  = STEP;
    defparam dut.g_lane[5].u_dly.STEP_NS  = STEP;
    defparam dut.g_lane[6].u_dly.STEP_NS  = STEP;
    defparam dut.g_lane[7].u_dly.STEP_NS  = STEP;
    defparam dut.g_lane[8].u_dly.STEP_NS  = STEP;
    defparam dut.g_lane[9].u_dly.STEP_NS  = STEP;
    defparam dut.g_lane[10].u_dly.STEP_NS = STEP;

    logic        eye_start = 0;
    logic [3:0]  eye_sel = 0;
    logic        eye_done;
    logic [15:0] eye_a, eye_b;

    adc_eye_monitor #(.N(N), .WIN_W(WIN_W)) u_eye (
        .clk(cap_clk), .rst_n(cap_rst_n), .start(eye_start), .sel(eye_sel),
        .rise_q(rise_q), .fall_q(fall_q),
        .done(eye_done), .a_cnt(eye_a), .b_cnt(eye_b));

    // ---- Helpers ------------------------------------------------------------
    function automatic int model_tap(input int k);
        case (k)
            0: return dut.g_lane[0].u_dly.tap;
            1: return dut.g_lane[1].u_dly.tap;
            2: return dut.g_lane[2].u_dly.tap;
            3: return dut.g_lane[3].u_dly.tap;
            4: return dut.g_lane[4].u_dly.tap;
            5: return dut.g_lane[5].u_dly.tap;
            6: return dut.g_lane[6].u_dly.tap;
            7: return dut.g_lane[7].u_dly.tap;
            8: return dut.g_lane[8].u_dly.tap;
            9: return dut.g_lane[9].u_dly.tap;
            default: return dut.g_lane[10].u_dly.tap;
        endcase
    endfunction

    task automatic set_tap(input int k, input int t);
        tap_tgt[k*TW +: TW] = TW'(t);
    endtask

    task automatic wait_taps;
        repeat (4) @(posedge hk_clk);
        while (busy) @(posedge hk_clk);
        // A few periods for in-flight transport delays to drain.
        repeat (4) @(posedge cap_clk);
    endtask

    task automatic run_eye(input int k, output int a, output int b);
        @(negedge cap_clk);
        eye_sel   = 4'(k);
        eye_start = 1'b1;
        @(negedge cap_clk);
        eye_start = 1'b0;
        @(posedge eye_done);
        a = eye_a;
        b = eye_b;
    endtask

    // Words that do not match any recently launched word are torn.
    task automatic count_torn(input int samples, output int torn);
        logic hit;
        torn = 0;
        repeat (samples) begin
            @(posedge cap_clk); #0.1;
            hit = 1'b0;
            for (int h = 0; h < 8; h++) if (rise_q === hist[h]) hit = 1'b1;
            if (!hit) torn++;
        end
    endtask

    int a, b, prev_a, prev_b, found, ideal, torn, mism;
    int cal_tap [N];

    initial begin
        repeat (4) @(posedge hk_clk);
        hk_rst_n  = 1;
        cap_rst_n = 1;
        wait_taps();

        // ---- Stepper: up to targets, then back down ----------------------
        for (int k = 0; k < N; k++) set_tap(k, (k * 13 + 5) % 128);
        wait_taps();
        mism = 0;
        for (int k = 0; k < N; k++) if (model_tap(k) != (k * 13 + 5) % 128) mism++;
        `EXPECT_EQ(mism, 0, "every IODELAY reached its target tap");

        for (int k = 0; k < N; k++) set_tap(k, 0);
        wait_taps();
        mism = 0;
        for (int k = 0; k < N; k++) if (model_tap(k) != 0) mism++;
        `EXPECT_EQ(mism, 0, "every IODELAY stepped back down to tap 0");

        // ---- Skewed bus with no deskew tears words -----------------------
        count_torn(200, torn);
        `EXPECT(torn > 50, "skew across the sample edge tears captured words");

        // ---- Calibrate: per lane, sweep taps, take the B->A crossover ----
        for (int k = 0; k < N; k++) begin
            found = -1;
            prev_a = 0; prev_b = 0;
            for (int t = 0; t < 128; t += 2) begin
                set_tap(k, t);
                wait_taps();
                run_eye(k, a, b);
                if (t > 0 && found < 0 && prev_b > prev_a && a > b) found = t - 1;
                prev_a = a; prev_b = b;
            end
            // Ideal: edge on the falling sample, CAP_OFS + PER/2 after launch.
            ideal = $rtoi((CAP_OFS + PER/2 - skew[k]) / STEP + 0.5);
            `EXPECT(found >= 0, "eye sweep found a B->A crossover");
            `EXPECT(found >= ideal - 3 && found <= ideal + 3,
                    "crossover tap within 3 taps of ideal");
            if (found < 0 || found > ideal + 3 || found < ideal - 3)
                $display("    lane %0d: found %0d, ideal %0d", k, found, ideal);
            cal_tap[k] = (found < 0) ? 0 : found;
            set_tap(k, 0);
        end

        // ---- Apply and check every word is whole -------------------------
        for (int k = 0; k < N; k++) set_tap(k, cal_tap[k]);
        wait_taps();
        count_torn(500, torn);
        `EXPECT_EQ(torn, 0, "deskewed bus captures whole words");

        `TB_FINISH("tb_adc_deskew");
    end

    initial begin
        #50_000_000;
        `EXPECT(1'b0, "tb_adc_deskew timed out");
        `TB_FINISH("tb_adc_deskew");
    end

    `TB_DUMP("build/tb_adc_deskew.vcd")
endmodule

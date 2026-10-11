/*
 * File: adc_eye_monitor.sv
 * Description: Measures where one ADC lane's data edges fall relative to the
 *              rising (data) sample edge, so the ESP32 can deskew the lanes.
 *              Each cycle the IDDR gives a rising sample r[n] and the falling
 *              sample f[n] half a period after it. Over a window of 2^WIN_W
 *              cycles this counts, for the selected lane:
 *
 *                A = #(f[n-1] != r[n])  edge in the half period BEFORE r[n]
 *                B = #(r[n]   != f[n])  edge in the half period AFTER  r[n]
 *
 *              Delaying the lane moves its edges later. Where the counts swing
 *              from B to A the edge sits on the falling sample, so the rising
 *              sample is mid-eye: that is the tap calibration wants. Where they
 *              swing from A to B the edge sits on the rising sample, the worst
 *              place. The lane needs to toggle for any of this to work, so feed
 *              the input a busy full-scale signal (e.g. the probe-comp square).
 *
 * The first SETTLE cycles after start are discarded so a lane-select change
 * arriving through its own synchroniser has landed. done stays high and the
 * counts stay static until the next start, which is what lets status_cdc carry
 * them with a plain synchroniser.
 * Author: Avery Lor
 * Date: Oct 7 2026
 */

module adc_eye_monitor #(
    parameter int N      = 11,
    parameter int WIN_W  = 16,
    parameter int SETTLE = 8
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,     // pulse
    input  logic [3:0]   sel,       // lane, held stable through a window
    input  logic [N-1:0] rise_q,
    input  logic [N-1:0] fall_q,
    output logic         done,
    output logic [15:0]  a_cnt,
    output logic [15:0]  b_cnt
);

    // Register the selected lane first to keep the 11:1 mux off the counters.
    logic r_q, f_q, f_prev;
    always_ff @(posedge clk) begin
        r_q    <= (sel < N) ? rise_q[sel] : 1'b0;
        f_q    <= (sel < N) ? fall_q[sel] : 1'b0;
        f_prev <= f_q;
    end

    logic             running;
    logic [WIN_W-1:0] win;
    logic [$clog2(SETTLE+1)-1:0] settle;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running <= 1'b0;
            done    <= 1'b0;
            win     <= '0;
            settle  <= '0;
            a_cnt   <= '0;
            b_cnt   <= '0;
        end else if (start) begin
            running <= 1'b1;
            done    <= 1'b0;
            win     <= '0;
            settle  <= '0;
            a_cnt   <= '0;
            b_cnt   <= '0;
        end else if (running) begin
            if (settle != SETTLE) begin
                settle <= settle + 1'b1;
            end else begin
                if ((f_prev != r_q) && (a_cnt != 16'hFFFF)) a_cnt <= a_cnt + 16'd1;
                if ((r_q != f_q)    && (b_cnt != 16'hFFFF)) b_cnt <= b_cnt + 16'd1;
                win <= win + 1'b1;
                if (win == {WIN_W{1'b1}}) begin
                    running <= 1'b0;
                    done    <= 1'b1;
                end
            end
        end
    end

endmodule

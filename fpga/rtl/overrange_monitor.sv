/*
 * File: overrange_monitor.sv
 * Description: Over-range protection detector in the capture clock domain.
 *              Counts how many samples in a fixed window of 2**cfg_win_log2
 *              raw ADC samples had the AD9215 OR flag set. At the end of each
 *              window it fires trip_pulse if that count reached the threshold
 *              cfg_thr/256 of the window, and updates `active` to show whether
 *              the window saw any over-range at all.
 *
 *              A single glitch or a brief transient never trips it; only a
 *              signal that sits outside full scale for a meaningful fraction
 *              of the window does. The ESP32 reacts to the (sticky, HK-domain)
 *              alarm by stepping the front-end gain down.
 *
 *              Runs on the raw corrected stream, independent of decimation,
 *              triggering and acquisition state, so it also protects while
 *              the record is frozen or the engine is idle.
 * Author: (added) over-range protection
 */

module overrange_monitor
    import scope_pkg::*;
#(
    parameter int CNT_W = OR_WIN_MAX + 1
) (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       valid_in,
    input  logic       or_in,

    input  logic [4:0] cfg_win_log2,   // window = 2**cfg_win_log2 samples
    input  logic [7:0] cfg_thr,        // trip at cfg_thr/256 of the window; 0 = off
    input  logic       cfg_update,     // config just changed: restart the window

    output logic       trip_pulse,     // one cycle, at a window end that tripped
    output logic       active          // last completed window saw any over-range
);

    // Clamp the window to a sane range so a bad register value can neither
    // make the window absurdly short (tripping on every transient) nor
    // overflow the counters.
    logic [4:0] win;
    always_comb begin
        if (cfg_win_log2 < 5'(OR_WIN_MIN))      win = 5'(OR_WIN_MIN);
        else if (cfg_win_log2 > 5'(OR_WIN_MAX)) win = 5'(OR_WIN_MAX);
        else                                    win = cfg_win_log2;
    end

    // Window length and trip count are static between config commits, so
    // register them once rather than shifting in the per-sample path.
    logic [CNT_W-1:0] len_m1, thr_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            len_m1  <= '0;
            thr_cnt <= '0;
        end else begin
            len_m1  <= (CNT_W'(1) << win) - CNT_W'(1);
            thr_cnt <= CNT_W'(cfg_thr) << (win - 5'd8);
        end
    end

    logic [CNT_W-1:0] smp_cnt, or_cnt, or_total;
    assign or_total = or_cnt + CNT_W'(or_in);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            smp_cnt    <= '0;
            or_cnt     <= '0;
            trip_pulse <= 1'b0;
            active     <= 1'b0;
        end else begin
            trip_pulse <= 1'b0;
            if (cfg_update) begin
                smp_cnt <= '0;
                or_cnt  <= '0;
            end else if (valid_in) begin
                if (smp_cnt == len_m1) begin
                    trip_pulse <= (cfg_thr != 8'd0) && (or_total >= thr_cnt);
                    active     <= (or_total != '0);
                    smp_cnt    <= '0;
                    or_cnt     <= '0;
                end else begin
                    smp_cnt <= smp_cnt + CNT_W'(1);
                    or_cnt  <= or_total;
                end
            end
        end
    end

endmodule

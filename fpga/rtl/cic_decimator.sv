/*
 * File: cic_decimator.sv
 * Description: High-res acquisition path: a CIC (cascaded integrator-comb)
 *              decimating low-pass filter. Reduces the 100 MSPS corrected
 *              sample stream by R = cfg_dec_factor + 1, the same window length
 *              the timebase_decimator uses (its start is one input sample
 *              later after an ARM), but each output is a weighted average
 *              of the input instead of one picked sample, so wideband noise
 *              falls as the timebase slows.
 *
 *              Structure (Hogenauer): STAGES integrators at the input rate, a
 *              rate change by R, STAGES combs at the output rate. The DC gain
 *              of that chain is G = R**STAGES, which is not a power of two for
 *              most R, so the comb output is divided by G in a pipelined
 *              restoring divider (one quotient bit per stage, rounded to
 *              nearest). Unity gain is therefore exact for every R, and the
 *              impulse response is non-negative, so the filter never rings or
 *              overshoots on an edge.
 *
 *              Registers are the full WIDTH + STAGES*RW bits: the rate is a
 *              run-time setting, so the usual LSB pruning (which is designed
 *              for one fixed R) is not applied.
 *
 *              The filter is flushed (state cleared, first STAGES outputs
 *              dropped) at reset, while disabled, at arm_align and whenever the
 *              rate changes, so a record never contains start-up samples.
 *
 *              Latency: valid_out lags the timebase_decimator's valid_out for
 *              the same window by PIPE_LATENCY = STAGES + WIDTH + 1 clocks.
 *              top.sv delays the trigger marker by the same amount.
 * Author: Avery Lor
 * Date: Nov 15 2026
 */

module cic_decimator
    import scope_pkg::*;
#(
    parameter int WIDTH  = SCOPE_CODE_W,
    parameter int STAGES = 2,
    parameter int RW     = 16            // width of cfg_dec_factor
) (
    input  logic             clk,
    input  logic             rst_n,

    input  logic             enable,         // 0: hold the filter flushed
    input  logic [RW-1:0]    cfg_dec_factor, // window length - 1 (0 => /1)
    input  logic             arm_align,      // realign the window at ARM

    input  logic [WIDTH-1:0] sample_in,
    input  logic             or_in,
    input  logic             valid_in,

    output logic [WIDTH-1:0] sample_out,
    output logic             or_out,
    output logic             valid_out
);

    localparam int GW    = STAGES * RW + 1;      // holds R**STAGES, R <= 2**RW
    localparam int ACC_W = WIDTH + STAGES * RW;  // full CIC bit growth
    localparam int BW    = $clog2(RW + 2);
    localparam int SW    = $clog2(STAGES + 1);

    // ---- Rate tracking and gain G = R**STAGES ---------------------------------
    // The rate is latched here; any difference from the live setting restarts
    // the gain computation and flushes the filter. G is built by a shift-add
    // multiplier (one bit per clock), which costs no DSP block and has no long
    // combinational path; a rate change is rare and takes ~STAGES*(RW+2) clocks.
    logic [RW-1:0] r_lat;
    logic          rate_chg;
    logic          g_start, g_busy, gain_ok;
    logic [GW-1:0] gain, g_acc, g_mcand;
    logic [RW:0]   g_mplier;
    logic [BW-1:0] g_bit;
    logic [SW-1:0] g_stage;

    assign rate_chg = (cfg_dec_factor != r_lat);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_lat    <= '0;
            g_start  <= 1'b1;
            g_busy   <= 1'b0;
            gain_ok  <= 1'b0;
            gain     <= GW'(1);
            g_acc    <= '0;
            g_mcand  <= '0;
            g_mplier <= '0;
            g_bit    <= '0;
            g_stage  <= '0;
        end else begin
            g_start <= 1'b0;

            if (g_start) begin
                // Begin G = 1 * R.
                g_busy   <= 1'b1;
                g_stage  <= '0;
                g_bit    <= '0;
                g_acc    <= '0;
                g_mcand  <= GW'(1);
                g_mplier <= {1'b0, r_lat} + 1'b1;
            end else if (g_busy) begin
                if (g_bit == BW'(RW + 1)) begin
                    // Every multiplier bit consumed: g_acc is the product.
                    if (g_stage == SW'(STAGES - 1)) begin
                        gain    <= g_acc;
                        g_busy  <= 1'b0;
                        gain_ok <= 1'b1;
                    end else begin
                        g_stage  <= g_stage + 1'b1;
                        g_mcand  <= g_acc;
                        g_acc    <= '0;
                        g_mplier <= {1'b0, r_lat} + 1'b1;
                        g_bit    <= '0;
                    end
                end else begin
                    if (g_mplier[0]) begin
                        g_acc <= g_acc + g_mcand;
                    end
                    g_mcand  <= g_mcand << 1;
                    g_mplier <= g_mplier >> 1;
                    g_bit    <= g_bit + 1'b1;
                end
            end

            // A new rate wins over anything in progress above.
            if (rate_chg) begin
                r_lat   <= cfg_dec_factor;
                g_start <= 1'b1;
                g_busy  <= 1'b0;
                gain_ok <= 1'b0;
            end
            if (g_start) begin
                gain_ok <= 1'b0;
            end
        end
    end

    // Filter held in its flushed state. Registered: the flush reaches every
    // filter register, and deriving it in the same clock as the 16-bit rate
    // compare was the slowest path in the capture domain. The one-clock delay
    // only means the flush lands one input sample later; valid_out is masked
    // below so nothing computed before the flush escapes in that clock.
    logic hold_c, hold;
    assign hold_c = !enable || arm_align || rate_chg || g_start || !gain_ok;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) hold <= 1'b1;
        else        hold <= hold_c;
    end

    // ---- Integrators, rate change, combs --------------------------------------
    logic [ACC_W-1:0] integ [STAGES];
    logic [ACC_W-1:0] comb  [STAGES];   // comb outputs
    logic [ACC_W-1:0] cdly  [STAGES];   // comb one-output delays
    logic [STAGES-1:0] comb_v, comb_or;

    logic [RW-1:0] phase;
    logic          win_or;
    logic          dump_v, dump_or;

    // Outputs still to drop after a flush.
    logic [SW-1:0] settle;

    // Divider valid / over-range flags, one bit per stage ([0] = divider entry).
    (* syn_srlstyle = "registers" *) logic [WIDTH:0] div_v, div_or;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < STAGES; k++) begin
                integ[k] <= '0;
                comb[k]  <= '0;
                cdly[k]  <= '0;
            end
            comb_v  <= '0;
            comb_or <= '0;
            phase   <= '0;
            win_or  <= 1'b0;
            dump_v  <= 1'b0;
            dump_or <= 1'b0;
            settle  <= SW'(STAGES);
            div_v   <= '0;
            div_or  <= '0;
        end else if (hold) begin
            for (int k = 0; k < STAGES; k++) begin
                integ[k] <= '0;
                comb[k]  <= '0;
                cdly[k]  <= '0;
            end
            comb_v  <= '0;
            comb_or <= '0;
            phase   <= '0;
            win_or  <= 1'b0;
            dump_v  <= 1'b0;
            dump_or <= 1'b0;
            settle  <= SW'(STAGES);
            div_v   <= '0;
            div_or  <= '0;
        end else begin
            // Integrators, pipelined: each stage adds the previous stage's
            // registered value, so no two adders are chained in one clock.
            dump_v <= 1'b0;
            if (valid_in) begin
                integ[0] <= integ[0] + ACC_W'(sample_in);
                for (int k = 1; k < STAGES; k++) begin
                    integ[k] <= integ[k] + integ[k-1];
                end
                if (phase == r_lat) begin
                    // Last sample of the window: hand the integrator output to
                    // the combs on the next clock.
                    phase   <= '0;
                    dump_v  <= 1'b1;
                    dump_or <= win_or | or_in;
                    win_or  <= 1'b0;
                end else begin
                    phase  <= phase + 1'b1;
                    win_or <= win_or | or_in;
                end
            end

            // Combs, one output-rate difference per stage.
            comb_v[0] <= dump_v;
            if (dump_v) begin
                comb[0]    <= integ[STAGES-1] - cdly[0];
                cdly[0]    <= integ[STAGES-1];
                comb_or[0] <= dump_or;
            end
            for (int k = 1; k < STAGES; k++) begin
                comb_v[k] <= comb_v[k-1];
                if (comb_v[k-1]) begin
                    comb[k]    <= comb[k-1] - cdly[k];
                    cdly[k]    <= comb[k-1];
                    comb_or[k] <= comb_or[k-1];
                end
            end

            // Drop the start-up outputs, then feed the divider.
            div_v  <= {div_v[WIDTH-1:0], 1'b0};
            div_or <= {div_or[WIDTH-1:0], comb_or[STAGES-1]};
            if (comb_v[STAGES-1]) begin
                if (settle != '0) begin
                    settle <= settle - 1'b1;
                end else begin
                    div_v[0] <= 1'b1;
                end
            end
        end
    end

    // ---- Normalise: out = round(comb / G) --------------------------------------
    // Long division, one quotient bit per pipeline stage, MSB first. The comb
    // output plus G/2 is below 2**WIDTH * G, so its top bits (everything above
    // the low WIDTH) already form a partial remainder smaller than G and the
    // quotient fits in WIDTH bits. Each stage shifts in the next dividend bit
    // and subtracts G if it fits. Working on the shifted partial remainder
    // keeps every stage to one GW+1 bit subtractor, whose borrow is the
    // compare.
    //
    // Data registers only: validity travels in div_v, so these need no reset
    // or flush.
    //
    // syn_srlstyle: the dividend and quotient bits here are plain delays. Left
    // alone, Gowin packs such chains into RAM16 shift registers, whose read
    // delay then sits directly in front of a stage's carry chain; that cost
    // ~8 MHz of Fmax on the 100 MHz capture clock. Keep them as flip-flops.
    logic [ACC_W-1:0] div_in;                                       // comb + G/2
    (* syn_srlstyle = "registers" *) logic [GW-1:0]    prem [WIDTH+1]; // partial remainder, < G
    (* syn_srlstyle = "registers" *) logic [WIDTH-1:0] dlow [WIDTH+1]; // dividend bits not yet used
    (* syn_srlstyle = "registers" *) logic [WIDTH-1:0] quo  [WIDTH+1];

    assign div_in = comb[STAGES-1] + ACC_W'(gain >> 1);             // + G/2: round to nearest

    // {partial remainder, next dividend bit} - G, with the borrow on top.
    logic [GW+1:0] trial [WIDTH+1];
    always_comb begin
        trial[0] = '0;
        for (int j = 1; j <= WIDTH; j++) begin
            trial[j] = {1'b0, prem[j-1], dlow[j-1][WIDTH-1]} - {2'b00, gain};
        end
    end

    always_ff @(posedge clk) begin
        prem[0] <= GW'(div_in >> WIDTH);
        dlow[0] <= div_in[WIDTH-1:0];
        quo[0]  <= '0;
        for (int j = 1; j <= WIDTH; j++) begin
            if (!trial[j][GW+1]) begin
                // G fits: take the difference, quotient bit = 1.
                prem[j] <= trial[j][GW-1:0];
                quo[j]  <= {quo[j-1][WIDTH-2:0], 1'b1};
            end else begin
                prem[j] <= {prem[j-1][GW-2:0], dlow[j-1][WIDTH-1]};
                quo[j]  <= {quo[j-1][WIDTH-2:0], 1'b0};
            end
            dlow[j] <= {dlow[j-1][WIDTH-2:0], 1'b0};
        end
    end

    assign sample_out = quo[WIDTH];
    assign or_out     = div_or[WIDTH];
    assign valid_out  = div_v[WIDTH] && !hold;

endmodule

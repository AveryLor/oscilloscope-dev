/*
 * File: timebase_decimator.sv
 * Description: Horizontal timebase. Reduces the 105 MSPS corrected sample stream
 *              by an integer factor (cfg_dec_factor + 1). In plain mode it emits
 *              the last sample of each window. In peak-detect mode it emits two
 *              entries per window — the window minimum then the window maximum —
 *              so a narrow transient survives a slow timebase. The live window
 *              phase is exported so the trigger engine can tag a sub-sample
 *              position.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module timebase_decimator
    import scope_pkg::*;
#(
    parameter int WIDTH = SCOPE_CODE_W
) (
    input  logic              clk,
    input  logic              rst_n,

    input  logic [15:0]       cfg_dec_factor, // window length - 1 (0 => /1)
    input  logic              cfg_peak_mode,
    input  logic              arm_align,      // realign the window at ARM

    input  logic [WIDTH-1:0]  sample_in,
    input  logic              or_in,
    input  logic              valid_in,

    output logic [WIDTH-1:0]  sample_out,
    output logic              or_out,
    output logic              is_max_out,
    output logic              valid_out,
    output logic [15:0]       dec_phase_out
);

    // Peak mode needs a window of at least two samples; below that it degrades
    // to plain sub-sampling.
    logic peak_active;
    assign peak_active = cfg_peak_mode && (cfg_dec_factor != 16'd0);

    logic [15:0]      phase;
    logic [WIDTH-1:0] win_min, win_max;
    logic             win_or;
    logic             window_done;

    // Running window min/max including the current input sample.
    logic [WIDTH-1:0] nmin, nmax;
    logic             nor_acc;

    assign window_done  = valid_in && (phase == cfg_dec_factor);
    assign dec_phase_out = phase;
    assign nmin    = (sample_in < win_min) ? sample_in : win_min;
    assign nmax    = (sample_in > win_max) ? sample_in : win_max;
    assign nor_acc = win_or | or_in;

    // Second beat of a peak-mode window: emit the maximum.
    logic             emit_max_pend;
    logic [WIDTH-1:0] hold_max;
    logic             hold_max_or;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase         <= '0;
            win_min       <= '1;
            win_max       <= '0;
            win_or        <= 1'b0;
            sample_out    <= '0;
            or_out        <= 1'b0;
            is_max_out    <= 1'b0;
            valid_out     <= 1'b0;
            emit_max_pend <= 1'b0;
            hold_max      <= '0;
            hold_max_or   <= 1'b0;
        end else begin
            valid_out  <= 1'b0;
            is_max_out <= 1'b0;

            if (emit_max_pend) begin
                // Deliver the max beat queued last cycle.
                sample_out    <= hold_max;
                or_out        <= hold_max_or;
                is_max_out    <= 1'b1;
                valid_out     <= 1'b1;
                emit_max_pend <= 1'b0;
            end

            if (arm_align) begin
                phase   <= '0;
                win_min <= '1;
                win_max <= '0;
                win_or  <= 1'b0;
            end else if (valid_in) begin
                if (window_done) begin
                    if (peak_active) begin
                        sample_out    <= nmin;
                        or_out        <= nor_acc;
                        is_max_out    <= 1'b0;
                        valid_out     <= 1'b1;
                        hold_max      <= nmax;
                        hold_max_or   <= nor_acc;
                        emit_max_pend <= 1'b1;
                    end else begin
                        sample_out <= sample_in;  // plain sub-sample
                        or_out     <= nor_acc;
                        is_max_out <= 1'b0;
                        valid_out  <= 1'b1;
                    end
                    // Start the next window with this sample already counted.
                    phase   <= '0;
                    win_min <= sample_in;
                    win_max <= sample_in;
                    win_or  <= or_in;
                end else begin
                    phase   <= phase + 1'b1;
                    win_min <= nmin;
                    win_max <= nmax;
                    win_or  <= nor_acc;
                end
            end
        end
    end

endmodule

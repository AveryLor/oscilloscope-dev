/*
 * File: adc_waveform_src.sv
 * Description: Behavioral ADC stimulus for simulation. Produces a deterministic
 *              triangle wave on adc_d each encode clock so a bench can recompute
 *              the expected samples. A one-cycle spike can be injected to test
 *              peak-detect, and adc_or is asserted whenever the code saturates.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module adc_waveform_src #(
    parameter int PERIOD = 400,  // encode clocks per triangle period
    parameter int LOW    = 64,
    parameter int HIGH   = 960
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        en,
    input  logic        inject_spike,   // pulse: next sample forced to HIGH
    output logic [9:0]  adc_d,
    output logic        adc_or
);

    localparam int HALF = PERIOD / 2;
    localparam int SPAN = HIGH - LOW;

    integer phase = 0;
    integer level = LOW;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase  <= 0;
            adc_d  <= LOW;
            adc_or <= 1'b0;
        end else if (en) begin
            phase <= (phase == PERIOD - 1) ? 0 : phase + 1;
            if (inject_spike) begin
                adc_d  <= HIGH;
                adc_or <= 1'b0;
            end else begin
                level = (phase < HALF)
                        ? (LOW + (SPAN * phase) / HALF)
                        : (HIGH - (SPAN * (phase - HALF)) / HALF);
                adc_d  <= level[9:0];
                adc_or <= (level >= 1023) || (level <= 0);
            end
        end
    end

endmodule

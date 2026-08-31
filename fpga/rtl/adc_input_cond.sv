/*
 * File: adc_input_cond.sv
 * Description: First fabric stage after the ADC IOLOGIC pad registers. Optionally
 *              corrects the swapped VIN+ / VIN- on the analog front end by
 *              reflecting each code around mid-scale (code -> ~code, i.e.
 *              1023 - code for 10 bits), then registers the corrected sample and
 *              the over-range flag. Every downstream block sees corrected codes.
 *
 * The inversion must live here in fabric, never in the IOLOGIC pad flops, so the
 * pad flops stay packed with no logic in front of them.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module adc_input_cond
    import scope_pkg::*;
#(
    parameter int WIDTH = SCOPE_CODE_W
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             invert_en,
    input  logic [WIDTH-1:0] d_in,     // from the adc_d pad registers
    input  logic             or_in,    // from the adc_or pad register
    output logic [WIDTH-1:0] sample_out,
    output logic             or_out,
    output logic             valid_out
);

    logic [WIDTH-1:0] corrected;

    always_comb begin
        corrected = invert_en ? (~d_in) : d_in;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_out <= '0;
            or_out     <= 1'b0;
            valid_out  <= 1'b0;
        end else begin
            sample_out <= corrected;
            or_out     <= or_in;
            valid_out  <= 1'b1;  // ADC delivers a fresh sample every clock
        end
    end

endmodule

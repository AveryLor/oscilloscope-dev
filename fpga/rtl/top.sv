/*
 * File: top.sv
 * Description: Top-level RTL for the Tang Nano 20K oscilloscope FPGA design.
 * Author: Avery Lor
 * Date: Aug 3 2026
 */

module top (
    input  logic       clk,
    output logic       led,
    input  logic       adc_enc_clk,
    input  logic [9:0] adc_d,
    input  logic       adc_or,
    input  logic       ext_trig
);

    logic adc_sample_clk;
    logic pll_lock;

    adc_pll u_adc_pll (
        .clkin(adc_enc_clk),
        .clkoutp(adc_sample_clk),
        .lock(pll_lock)
    );

    (* syn_useioff = 1, syn_keep = "true" *) logic [9:0] adc_d_q;
    (* syn_useioff = 1, syn_keep = "true" *) logic       adc_or_q;
    (* syn_useioff = 1, syn_keep = "true" *) logic       ext_trig_q;

    always_ff @(posedge adc_sample_clk) begin
        if (pll_lock) begin
            adc_d_q    <= adc_d;
            adc_or_q   <= adc_or;
            ext_trig_q <= ext_trig;
        end
    end

    assign led = pll_lock;

endmodule

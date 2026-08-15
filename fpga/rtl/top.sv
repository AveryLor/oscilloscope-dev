/*
 * File: top.sv
 * Description: Top-level RTL for the Tang Nano 20K oscilloscope FPGA design.
 * Author: Avery Lor
 * Date: Aug 3 2026
 */

module top (
    input  logic       clk,
    input  logic       fpga_clk,
    input  logic [9:0] adc_d,
    input  logic       adc_or,
    input  logic       hw_trigger,
    input  logic       spi_sclk,
    input  logic       spi_cs,
    input  logic       spi_mosi,
    output logic       spi_miso,
    input  logic       dial_hs_a,
    input  logic       dial_hs_b,
    input  logic       dial_hs_btn,
    input  logic       dial_ho_a,
    input  logic       dial_ho_b,
    input  logic       dial_ho_btn,
    input  logic       dial_tg_a,
    input  logic       dial_tg_b,
    input  logic       dial_tg_btn,
    output logic       probe_comp,
    input  logic [2:0] fpga_flex
);

    logic adc_sample_clk;
    logic pll_lock;

    adc_pll u_adc_pll (
        .clkin(fpga_clk),
        .clkoutp(adc_sample_clk),
        .lock(pll_lock)
    );

    // VIN+ / VIN- are swapped on the analog front end; codes are inverted
    // around mid-scale. RTL does not correct this yet.
    (* syn_useioff = 1, syn_keep = "true" *) logic [9:0] adc_d_q;
    (* syn_useioff = 1, syn_keep = "true" *) logic       adc_or_q;
    (* syn_useioff = 1, syn_keep = "true" *) logic       hw_trigger_q;

    always_ff @(posedge adc_sample_clk) begin
        if (pll_lock) begin
            adc_d_q      <= adc_d;
            adc_or_q     <= adc_or;
            hw_trigger_q <= hw_trigger;
        end
    end

    // Declared for pinout only; no SPI / encoder / probe-comp logic yet.
    assign spi_miso   = 1'b0;
    assign probe_comp = 1'b0;

endmodule

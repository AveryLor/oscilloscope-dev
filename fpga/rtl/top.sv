/*
 * File: top.sv
 * Description: Top-level RTL for the Tang Nano 20K oscilloscope FPGA design.
 * Author: Avery Lor
 * Date: Aug 3 2026
 */

module top (
    input  logic       clk,
    output logic       led,
    (* syn_keep = "true" *) input  logic       adc_enc_clk,
    (* syn_keep = "true" *) input  logic [9:0] adc_d,
    (* syn_keep = "true" *) input  logic       adc_or,
    (* syn_keep = "true" *) input  logic       ext_trig
);

    // Keep unused ADC/trigger inputs in the netlist so IO constraints apply.
    // Replace with real capture / buffer logic.
    (* syn_keep = "true" *) logic adc_keep;
    assign adc_keep = ^{adc_enc_clk, adc_d, adc_or, ext_trig};

    assign led = 1'b0;

endmodule

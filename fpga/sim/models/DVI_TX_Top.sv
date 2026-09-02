/*
 * File: DVI_TX_Top.sv
 * Description: Simulation shim for the Gowin DVI_TX IP core. The real IP does
 *              TMDS 8b/10b encoding, an OSER10 10:1 gearbox and TLVDS output
 *              buffers, none of which Icarus can model. Benches only need the
 *              RGB / sync / de inputs to remain observable and the TMDS outputs
 *              driven to a known value, so that video_top and tb_top elaborate.
 *              Port list must track the generated wrapper in
 *              rtl/video/gowin_dvi_tx/.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

`timescale 1ns/1ps

module DVI_TX_Top (
    input        I_rst_n,
    input        I_serial_clk,
    input        I_rgb_clk,
    input        I_rgb_vs,
    input        I_rgb_hs,
    input        I_rgb_de,
    input  [7:0] I_rgb_r,
    input  [7:0] I_rgb_g,
    input  [7:0] I_rgb_b,
    output       O_tmds_clk_p,
    output       O_tmds_clk_n,
    output [2:0] O_tmds_data_p,
    output [2:0] O_tmds_data_n
);

    assign O_tmds_clk_p  = I_rgb_clk;
    assign O_tmds_clk_n  = ~I_rgb_clk;
    assign O_tmds_data_p = 3'b000;
    assign O_tmds_data_n = 3'b111;

endmodule

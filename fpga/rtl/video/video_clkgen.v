/*
 * File: video_clkgen.v
 * Description: Pixel-clock generator for the 720p HDMI output. An rPLL turns the
 *              27 MHz crystal into the 371.25 MHz TMDS serial clock (x55 / 4,
 *              VCO 742.5 MHz), then a CLKDIV /5 produces the 74.25 MHz pixel
 *              clock. Mirrors the adc_pll.v wrapper style; the Gowin DVI_TX IP
 *              consumes serial_clk and pix_clk directly.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

module video_clkgen (
    input  clk27,
    input  arst_n,
    output serial_clk,
    output pix_clk,
    output pix_lock
);

    wire gw_gnd    = 1'b0;
    wire pll_reset = ~arst_n;

    wire clkoutp_unused;
    wire clkoutd_unused;
    wire clkoutd3_unused;

    rPLL rpll_inst (
        .CLKOUT   (serial_clk),
        .LOCK     (pix_lock),
        .CLKOUTP  (clkoutp_unused),
        .CLKOUTD  (clkoutd_unused),
        .CLKOUTD3 (clkoutd3_unused),
        .RESET    (pll_reset),
        .RESET_P  (gw_gnd),
        .CLKIN    (clk27),
        .CLKFB    (gw_gnd),
        .FBDSEL   ({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
        .IDSEL    ({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
        .ODSEL    ({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
        .PSDA     ({gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
        .DUTYDA   ({gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
        .FDLY     ({gw_gnd, gw_gnd, gw_gnd, gw_gnd})
    );

    defparam rpll_inst.FCLKIN = "27";
    defparam rpll_inst.DYN_IDIV_SEL = "false";
    defparam rpll_inst.IDIV_SEL = 3;        // / 4  -> PFD 6.75 MHz
    defparam rpll_inst.DYN_FBDIV_SEL = "false";
    defparam rpll_inst.FBDIV_SEL = 54;      // x55 -> 371.25 MHz CLKOUT
    defparam rpll_inst.DYN_ODIV_SEL = "false";
    defparam rpll_inst.ODIV_SEL = 2;        // VCO 742.5 MHz (400-1200 MHz range)
    defparam rpll_inst.PSDA_SEL = "0000";
    defparam rpll_inst.DYN_DA_EN = "false";
    defparam rpll_inst.DUTYDA_SEL = "1000";
    defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
    defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
    defparam rpll_inst.CLKOUT_DLY_STEP = 0;
    defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
    defparam rpll_inst.CLKFB_SEL = "internal";
    defparam rpll_inst.CLKOUT_BYPASS = "false";
    defparam rpll_inst.CLKOUTP_BYPASS = "false";
    defparam rpll_inst.CLKOUTD_BYPASS = "false";
    defparam rpll_inst.DYN_SDIV_SEL = 2;
    defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
    defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
    defparam rpll_inst.DEVICE = "GW2AR-18C";

    CLKDIV clkdiv_inst (
        .CLKOUT (pix_clk),
        .HCLKIN (serial_clk),
        .RESETN (pix_lock),
        .CALIB  (gw_gnd)
    );
    defparam clkdiv_inst.DIV_MODE = "5";
    defparam clkdiv_inst.GSREN = "false";

endmodule

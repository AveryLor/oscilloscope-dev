/*
 * File: adc_pll.v
 * Description: rPLL locked 1:1 to the 105 MHz ADC encode clock, CLKOUTP phase
 *              shifted to sample the AD9215 bus mid-eye rather than at its
 *              transition edge. The shift is dynamic (DYN_DA_EN): psda selects
 *              it at runtime in 22.5 deg steps (595 ps at 105 MHz) so the ESP32
 *              can sweep it during deskew calibration. psda comes from the
 *              PLL_PHASE register; top holds the capture domain in reset across
 *              every change since CLKOUTP may glitch while it moves.
 * Author: Avery Lor
 * Date: Aug 14 2026
 */

module adc_pll (
    input  clkin,
    input  [3:0] psda,
    output clkoutp,
    output lock
);

    wire clkout_unused;
    wire clkoutd_unused;
    wire clkoutd3_unused;
    wire gw_gnd;

    assign gw_gnd = 1'b0;

    // With DYN_DA_EN the DUTYDA port sets the falling-edge position on the same
    // 16-step scale as PSDA, so PSDA + 8 keeps CLKOUTP at 50% duty. VERIFY
    // against Gowin UG286 (rPLL dynamic phase / duty) on the first bring-up.
    wire [3:0] dutyda = psda + 4'd8;

    rPLL rpll_inst (
        .CLKOUT(clkout_unused),
        .LOCK(lock),
        .CLKOUTP(clkoutp),
        .CLKOUTD(clkoutd_unused),
        .CLKOUTD3(clkoutd3_unused),
        .RESET(gw_gnd),
        .RESET_P(gw_gnd),
        .CLKIN(clkin),
        .CLKFB(gw_gnd),
        .FBDSEL({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
        .IDSEL({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
        .ODSEL({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
        .PSDA(psda),
        .DUTYDA(dutyda),
        .FDLY({gw_gnd, gw_gnd, gw_gnd, gw_gnd})
    );

    defparam rpll_inst.FCLKIN = "105";
    defparam rpll_inst.DYN_IDIV_SEL = "false";
    defparam rpll_inst.IDIV_SEL = 0;
    defparam rpll_inst.DYN_FBDIV_SEL = "false";
    defparam rpll_inst.FBDIV_SEL = 0;
    defparam rpll_inst.DYN_ODIV_SEL = "false";
    defparam rpll_inst.ODIV_SEL = 8;
    // Static PSDA_SEL / DUTYDA_SEL are ignored with DYN_DA_EN = "true"; kept at
    // the 180 deg power-up value that PLL_PHASE also resets to. The eye opens at
    // t_PD_max and closes at period + t_PD_min (AD9215 datasheet, plus
    // ADC->FPGA trace delay); deskew calibration finds the real centre.
    defparam rpll_inst.PSDA_SEL = "1000";
    defparam rpll_inst.DYN_DA_EN = "true";
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

endmodule

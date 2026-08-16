/*
 * File: adc_pll.v
 * Description: rPLL locked 1:1 to the 105 MHz ADC encode clock, CLKOUTP phase
 *              shifted to sample the AD9215 bus mid-eye rather than at its
 *              transition edge. See PSDA_SEL below.
 * Author: Avery Lor
 * Date: Aug 14 2026
 */

module adc_pll (
    input  clkin,
    output clkoutp,
    output lock
);

    wire clkout_unused;
    wire clkoutd_unused;
    wire clkoutd3_unused;
    wire gw_gnd;

    assign gw_gnd = 1'b0;

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
        .PSDA({gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
        .DUTYDA({gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
        .FDLY({gw_gnd, gw_gnd, gw_gnd, gw_gnd})
    );

    defparam rpll_inst.FCLKIN = "105";
    defparam rpll_inst.DYN_IDIV_SEL = "false";
    defparam rpll_inst.IDIV_SEL = 0;
    defparam rpll_inst.DYN_FBDIV_SEL = "false";
    defparam rpll_inst.FBDIV_SEL = 0;
    defparam rpll_inst.DYN_ODIV_SEL = "false";
    defparam rpll_inst.ODIV_SEL = 8;
    // Sample-phase shift, 4 bits of 22.5 deg steps. "1000" = 180 deg = 4.76 ns
    // at 9.524 ns. PROVISIONAL: this is the conventional source-synchronous
    // starting point, not a derived value. Centre it properly before trusting
    // captured data — the eye opens at t_PD_max and closes at period+t_PD_min
    // (AD9215 datasheet, plus ADC->FPGA trace delay); target the midpoint, and
    // on a tie take the step with more margin against t_PD_max.
    defparam rpll_inst.PSDA_SEL = "1000";
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

endmodule

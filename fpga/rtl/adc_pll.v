/*
 * File: adc_pll.v
 * Description: rPLL locked 1:1 to the 100 MHz ADC encode clock, CLKOUTP phase
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

    defparam rpll_inst.FCLKIN = "100";
    defparam rpll_inst.DYN_IDIV_SEL = "false";
    defparam rpll_inst.IDIV_SEL = 0;
    defparam rpll_inst.DYN_FBDIV_SEL = "false";
    defparam rpll_inst.FBDIV_SEL = 0;
    defparam rpll_inst.DYN_ODIV_SEL = "false";
    defparam rpll_inst.ODIV_SEL = 8;
    // Sample-phase shift, 4 bits of 22.5 deg steps (0.625 ns at 10 ns).
    // All times below are from the fpga_clk rising edge at the FPGA pin.
    //   Data at the pad flop D (AD9215BCP-105 Table 4 tOD, timing.sdc
    //   input delays, + 0.675 ns input buffer from the Gowin timing report):
    //     word N settled   at 7.0 + 0.675       =  7.68 ns
    //     word N+1 starts  at 10 + 2.5 + 0.675  = 13.18 ns
    //   Eye midpoint 10.43 ns.
    //   CLKOUTP reaches the pad flops 5.16 ns after fpga_clk at 0 deg
    //   (3.65 ns PLL + 1.51 ns route, Gowin timing report). So the phase
    //   that centres the edge is 10.43 - 5.16 = 5.27 ns = ~190 deg.
    //     "1000" (180 deg)   edge at 10.16 ns: 2.49 ns setup, 3.01 ns hold margin
    //     "1001" (202.5 deg) edge at 10.79 ns: 3.11 ns setup, 2.39 ns hold margin
    // "1000" has the larger worst-case margin. Re-check against the timing
    // report after any change to placement, and with a bench phase sweep.
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

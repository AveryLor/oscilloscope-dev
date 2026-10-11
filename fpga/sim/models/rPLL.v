/*
 * File: rPLL.v
 * Description: Behavioral stand-in for the Gowin rPLL primitive, enough for
 *              simulating adc_pll / top under Icarus. CLKOUTP follows CLKIN 1:1
 *              with a fixed phase offset; LOCK asserts after a short delay. Not
 *              cycle-accurate to the real PLL and only models the ports adc_pll
 *              actually uses.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module rPLL #(
    parameter FCLKIN            = "105",
    parameter DYN_IDIV_SEL      = "false",
    parameter IDIV_SEL          = 0,
    parameter DYN_FBDIV_SEL     = "false",
    parameter FBDIV_SEL         = 0,
    parameter DYN_ODIV_SEL      = "false",
    parameter ODIV_SEL          = 8,
    parameter PSDA_SEL          = "0000",
    parameter DYN_DA_EN         = "false",
    parameter DUTYDA_SEL        = "1000",
    parameter CLKOUT_FT_DIR     = 1'b1,
    parameter CLKOUTP_FT_DIR    = 1'b1,
    parameter CLKOUT_DLY_STEP   = 0,
    parameter CLKOUTP_DLY_STEP  = 0,
    parameter CLKFB_SEL         = "internal",
    parameter CLKOUT_BYPASS     = "false",
    parameter CLKOUTP_BYPASS    = "false",
    parameter CLKOUTD_BYPASS    = "false",
    parameter DYN_SDIV_SEL      = 2,
    parameter CLKOUTD_SRC       = "CLKOUT",
    parameter CLKOUTD3_SRC      = "CLKOUT",
    parameter DEVICE            = "GW2AR-18C"
) (
    output CLKOUT,
    output LOCK,
    output CLKOUTP,
    output CLKOUTD,
    output CLKOUTD3,
    input  RESET,
    input  RESET_P,
    input  CLKIN,
    input  CLKFB,
    input  [5:0] FBDSEL,
    input  [5:0] IDSEL,
    input  [5:0] ODSEL,
    input  [3:0] PSDA,
    input  [3:0] DUTYDA,
    input  [3:0] FDLY
);

    // One 105 MHz period is ~9.524 ns, split into 16 PSDA steps of 22.5 deg.
    // With DYN_DA_EN the shift follows the PSDA port; otherwise PSDA_SEL's
    // "1000" (180 deg, ~4.76 ns) default. Model just enough delay for a
    // phase-shifted capture edge; duty and glitches on a change are not modelled.
    localparam real STEP_NS = 9.524 / 16.0;
    localparam      DYN     = (DYN_DA_EN == "true");

    real phase_ns = 8 * STEP_NS;
    always @(*) phase_ns = (DYN ? PSDA : 4'd8) * STEP_NS;

    reg clkoutp_r = 1'b0;
    always @(CLKIN) clkoutp_r <= #(phase_ns) CLKIN;

    assign CLKOUT   = CLKIN;
    assign CLKOUTP  = clkoutp_r;
    assign CLKOUTD   = 1'b0;
    assign CLKOUTD3  = 1'b0;

    reg locked = 1'b0;
    initial begin
        #200 locked = 1'b1;
    end
    assign LOCK = locked & ~RESET & ~RESET_P;

endmodule

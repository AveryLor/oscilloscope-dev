/*
 * File: IODELAY.v
 * Description: Behavioral stand-in for the Gowin GW2A IODELAY primitive, enough
 *              for iodelay_stepper / adc_deskew under Icarus. SDTAP = 0 reloads
 *              C_STATIC_DLY; with SDTAP = 1 each falling edge of VALUE moves the
 *              tap one step, up when SETN = 0 and down when SETN = 1, saturating
 *              at 0 / 127 and raising DF there. DO is DI delayed by tap * STEP_NS
 *              (transport delay). STEP_NS is a sim-only parameter; the real tap
 *              size is in Gowin UG289. Polarities here match iodelay_stepper's
 *              defaults; the real silicon is the thing to verify.
 * Author: Avery Lor
 * Date: Oct 7 2026
 */

`timescale 1ns/1ps

module IODELAY #(
    parameter integer C_STATIC_DLY = 0,
    parameter real    STEP_NS      = 0.025
) (
    input  DI,
    input  SDTAP,
    input  SETN,
    input  VALUE,
    output DO,
    output DF
);

    integer tap = C_STATIC_DLY;
    reg     df  = 1'b0;
    reg     do_r = 1'b0;

    always @(SDTAP) if (SDTAP === 1'b0) begin
        tap = C_STATIC_DLY;
        df  = 1'b0;
    end

    always @(negedge VALUE) if (SDTAP === 1'b1) begin
        if (SETN === 1'b0) begin
            if (tap < 127) tap = tap + 1; else df = 1'b1;
        end else begin
            if (tap > 0)   tap = tap - 1; else df = 1'b1;
        end
    end

    always @(DI) do_r <= #(tap * STEP_NS) DI;

    assign DO = do_r;
    assign DF = df;

endmodule

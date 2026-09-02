/*
 * File: tb_graticule_gen.sv
 * Description: Spot-checks the graticule generator: the four plot-box border
 *              pixels are lit and bright, the centre cross is lit, a plain
 *              interior pixel between grid lines is dark, and everything outside
 *              the plot box is dark.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

`timescale 1ns/1ps

module tb_graticule_gen;
    import video_pkg::*;
    `include "tb_common.svh"

    logic [11:0] x, y;
    logic        dots_en = 1'b0;
    logic        grat_on, grat_bright;

    graticule_gen dut (
        .x(x), .y(y), .dots_en(dots_en),
        .grat_on(grat_on), .grat_bright(grat_bright));

    task automatic probe(input [11:0] xx, input [11:0] yy);
        x = xx; y = yy; #1;
    endtask

    initial begin
        // Top-left corner of the plot box: border, bright.
        probe(PLOT_X0, PLOT_Y0);
        `EXPECT(grat_on && grat_bright, "top-left border pixel lit and bright");

        // Bottom-right corner.
        probe(PLOT_X1, PLOT_Y1);
        `EXPECT(grat_on && grat_bright, "bottom-right border pixel lit and bright");

        // Centre of the cross.
        probe(PLOT_XC, PLOT_YC);
        `EXPECT(grat_on, "centre cross pixel lit");

        // Interior pixel offset from every grid line and axis.
        probe(PLOT_X0 + 37, PLOT_Y0 + 31);
        `EXPECT(!grat_on, "plain interior pixel is dark");

        // Just outside the plot box.
        probe(PLOT_X0 - 1, PLOT_Y0 + 40);
        `EXPECT(!grat_on, "pixel left of the plot box is dark");
        probe(PLOT_X1 + 1, PLOT_Y0 + 40);
        `EXPECT(!grat_on, "pixel right of the plot box is dark");
        probe(PLOT_X0 + 40, PLOT_Y1 + 1);
        `EXPECT(!grat_on, "pixel below the plot box is dark");

        `TB_FINISH("tb_graticule_gen");
    end
endmodule

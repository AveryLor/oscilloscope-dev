/*
 * File: graticule_gen.sv
 * Description: Oscilloscope graticule as a pure function of the pixel coordinate.
 *              Draws a solid bright border around the 10x8 division plot box,
 *              dotted division grid lines, a solid centre cross, and bright
 *              per-fifth minor ticks along the centre axes. Output is combinational
 *              at pixel-pipeline stage 0; video_top delays it to meet the trace
 *              and text layers.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

module graticule_gen
    import video_pkg::*;
(
    input  logic [11:0] x,
    input  logic [11:0] y,
    input  logic        dots_en,     // 1 = dotted grid + axes, 0 = solid
    output logic        grat_on,
    output logic        grat_bright
);

    logic        in_plot;
    logic [11:0] px, py;

    assign in_plot = (x >= PLOT_X0) && (x <= PLOT_X1) &&
                     (y >= PLOT_Y0) && (y <= PLOT_Y1);
    assign px = x - PLOT_X0;
    assign py = y - PLOT_Y0;

    logic on_border, on_div_x, on_div_y, on_xaxis, on_yaxis, on_minor;

    assign on_border = in_plot &&
                       (px == 0 || px == PLOT_W - 1 ||
                        py == 0 || py == PLOT_H - 1);

    // Constant-modulus grid: DIV_W = 100, DIV_H = 72.
    assign on_div_x = in_plot && ((px % DIV_W) == 0);
    assign on_div_y = in_plot && ((py % DIV_H) == 0);

    assign on_xaxis = in_plot && (py == PLOT_H / 2);
    assign on_yaxis = in_plot && (px == PLOT_W / 2);

    // Minor ticks every fifth of a division along the centre axes.
    assign on_minor = (on_xaxis && ((px % (DIV_W / 5)) == 0)) ||
                      (on_yaxis && ((py % (DIV_H / 4)) == 0));

    always_comb begin
        grat_on     = 1'b0;
        grat_bright = 1'b0;

        if (in_plot) begin
            if (on_border || on_minor) begin
                grat_on     = 1'b1;
                grat_bright = 1'b1;
            end else if (on_xaxis || on_yaxis) begin
                grat_on     = dots_en ? ((on_xaxis && px[1:0] == 2'b00) ||
                                         (on_yaxis && py[1:0] == 2'b00))
                                      : 1'b1;
                grat_bright = grat_on;
            end else if (on_div_x || on_div_y) begin
                // Division lines are always dotted so they read as a grid.
                grat_on = (on_div_x && py[1:0] == 2'b00) ||
                          (on_div_y && px[1:0] == 2'b00);
            end
        end
    end

endmodule

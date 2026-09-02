/*
 * File: video_pkg.sv
 * Description: Display-only constants for the 720p HDMI oscilloscope screen:
 *              1280x720p60 CEA-861 timing numbers, the graticule/plot geometry,
 *              text region coordinates, the pixel-pipeline latency, and the
 *              24-bit colour palette. Everything the video RTL shares lives here
 *              so the timing generator, renderers and compositor agree on one
 *              layout.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

package video_pkg;

    // ---- 1280x720p60 timing, 74.25 MHz pixel clock, positive H and V sync ----
    localparam int H_ACTIVE = 1280;
    localparam int H_FRONT  = 110;
    localparam int H_SYNC   = 40;
    localparam int H_BACK   = 220;
    localparam int H_TOTAL  = 1650;

    localparam int V_ACTIVE = 720;
    localparam int V_FRONT  = 5;
    localparam int V_SYNC   = 5;
    localparam int V_BACK   = 20;
    localparam int V_TOTAL  = 750;

    // ---- Graticule (waveform plot) box, screen pixels. 10 x 8 divisions. -----
    localparam int PLOT_X0 = 48;
    localparam int PLOT_Y0 = 48;
    localparam int PLOT_W  = 1000;
    localparam int PLOT_H  = 576;
    localparam int DIV_W   = 100;   // PLOT_W / 10
    localparam int DIV_H   = 72;    // PLOT_H / 8

    localparam int PLOT_X1 = PLOT_X0 + PLOT_W - 1;
    localparam int PLOT_Y1 = PLOT_Y0 + PLOT_H - 1;
    localparam int PLOT_XC = PLOT_X0 + PLOT_W / 2;
    localparam int PLOT_YC = PLOT_Y0 + PLOT_H / 2;

    // ---- Text regions -------------------------------------------------------
    localparam int BAR_Y0   = 6;      // top status bar
    localparam int BAR_H    = 32;
    localparam int PANEL_X0 = 1060;   // right-hand readout panel
    localparam int PANEL_W  = 212;

    // ---- Column-reduced trace display memory ------------------------------
    // One {y_min, y_max} entry per plot column, in screen-y space.
    localparam int COL_N  = PLOT_W;
    localparam int COL_YW = 11;       // screen-y (0..719) fits in 11 bits

    // Pixel-pipeline latency from video_timing_gen outputs to the compositor.
    localparam int PIX_PIPE = 3;

    // ---- 24-bit RGB palette (0xRRGGBB) ----------------------------------
    localparam logic [23:0] COL_BG          = 24'h0A0E14;
    localparam logic [23:0] COL_GRAT        = 24'h2A3340;
    localparam logic [23:0] COL_GRAT_BRIGHT = 24'h55606E;
    localparam logic [23:0] COL_TRACE       = 24'h33FF66;
    localparam logic [23:0] COL_TRIG_LEVEL  = 24'hFF9020;
    localparam logic [23:0] COL_TRIG_POS    = 24'h20A0FF;
    localparam logic [23:0] COL_TEXT        = 24'hE8ECF0;
    localparam logic [23:0] COL_WARN        = 24'hFF3B30;

endpackage

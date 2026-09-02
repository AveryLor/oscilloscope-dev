/*
 * File: video_top.sv
 * Description: HDMI 720p display subsystem container. Runs the video timing
 *              generator, builds the column-reduced waveform display memory from
 *              the frozen capture record, composites the oscilloscope screen
 *              layers into 24-bit RGB and hands it to the Gowin DVI_TX IP which
 *              drives the board's onboard HDMI connector.
 *
 *              The pixel / TMDS-serial clocks and the pixel-domain reset are
 *              generated in top.sv and passed in. Current scope: timing,
 *              graticule, column reducer + display RAM, compositor. The trace
 *              renderer, readout panel and measurement wiring are added in later
 *              chunks; those layers are tied off for now. TEST_PATTERN=1 replaces
 *              the UI with a ramp for first bring-up.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

module video_top
    import scope_pkg::*;
    import video_pkg::*;
#(
    parameter bit TEST_PATTERN = 1'b0,
    parameter int DEPTH        = 16384,
    parameter int AW           = $clog2(DEPTH),
    parameter int CW           = SCOPE_CNT_W
) (
    input  logic              pix_clk,
    input  logic              serial_clk,
    input  logic              rst_pix_n,

    // Capture domain, synced into the pixel clock. Static while frozen_pix high.
    input  logic              frozen_pix,
    input  logic [AW-1:0]     rec_start_pix,
    input  logic [CW-1:0]     rec_count_pix,

    // capture_buffer read port (registered read, 1-cycle latency).
    output logic [AW-1:0]     buf_rd_addr,
    output logic              buf_rd_en,
    input  logic [SCOPE_DW-1:0] buf_rd_data,

    output logic              tmds_clk_p,
    output logic              tmds_clk_n,
    output logic [2:0]        tmds_data_p,
    output logic [2:0]        tmds_data_n
);

    // ---- Video timing (pipeline stage 0) ------------------------------
    logic [11:0] x, y;
    logic        de, hsync, vsync, line_start, frame_start;

    video_timing_gen u_timing (
        .pix_clk     (pix_clk),
        .rst_n       (rst_pix_n),
        .x           (x),
        .y           (y),
        .de          (de),
        .hsync       (hsync),
        .vsync       (vsync),
        .line_start  (line_start),
        .frame_start (frame_start)
    );

    // ---- Waveform display memory (column reducer + double-buffered RAM) ---
    // Fixed full-range vertical map for now; chunk 5 drives these from the
    // ESP32 annotation registers.
    localparam logic [17:0]        VSCALE_FULL  = 18'd576;
    localparam logic signed [11:0] VOFFSET_ZERO = 12'sd0;

    logic                 col_wr_en;
    logic [$clog2(COL_N)-1:0] col_wr_col;
    logic [COL_YW-1:0]    col_wr_ymin, col_wr_ymax;
    logic                 wr_bank, disp_bank, reducer_busy;

    column_reducer #(.DEPTH(DEPTH)) u_reducer (
        .pix_clk       (pix_clk),
        .rst_n         (rst_pix_n),
        .frozen_pix    (frozen_pix),
        .rec_start_pix (rec_start_pix),
        .rec_count_pix (rec_count_pix),
        .frame_start   (frame_start),
        .vscale        (VSCALE_FULL),
        .voffset       (VOFFSET_ZERO),
        .buf_rd_addr   (buf_rd_addr),
        .buf_rd_en     (buf_rd_en),
        .buf_rd_data   (buf_rd_data),
        .col_wr_en     (col_wr_en),
        .col_wr_col    (col_wr_col),
        .col_wr_ymin   (col_wr_ymin),
        .col_wr_ymax   (col_wr_ymax),
        .wr_bank       (wr_bank),
        .disp_bank     (disp_bank),
        .busy          (reducer_busy)
    );

    logic [$clog2(COL_N)-1:0] col_rd_col;
    logic [COL_YW-1:0]        col_rd_ymin, col_rd_ymax;

    waveform_col_ram u_colram (
        .clk       (pix_clk),
        .wr_bank   (wr_bank),
        .wr_col    (col_wr_col),
        .wr_en     (col_wr_en),
        .wr_ymin   (col_wr_ymin),
        .wr_ymax   (col_wr_ymax),
        .disp_bank (disp_bank),
        .rd_col    (col_rd_col),
        .rd_ymin   (col_rd_ymin),
        .rd_ymax   (col_rd_ymax)
    );

    // trace_render (chunk 4) will drive col_rd_col from x and use col_rd_*.
    assign col_rd_col = '0;

    // ---- Graticule (combinational, stage 0) --------------------------
    logic grat_on_0, grat_bright_0;
    graticule_gen u_grat (
        .x           (x),
        .y           (y),
        .dots_en     (1'b0),
        .grat_on     (grat_on_0),
        .grat_bright (grat_bright_0)
    );

    // ---- Align every layer + sync stream to stage PIX_PIPE ----------
    logic [2:0] syn_d, syn_q;   // {de, hsync, vsync}
    assign syn_d = {de, hsync, vsync};
    pixel_delay #(.W(3), .N(PIX_PIPE)) u_syn_dly (
        .clk(pix_clk), .d(syn_d), .q(syn_q));
    wire de_p    = syn_q[2];
    wire hsync_p = syn_q[1];
    wire vsync_p = syn_q[0];

    logic [1:0] grat_d, grat_q;
    assign grat_d = {grat_on_0, grat_bright_0};
    pixel_delay #(.W(2), .N(PIX_PIPE)) u_grat_dly (
        .clk(pix_clk), .d(grat_d), .q(grat_q));
    wire grat_on_p     = grat_q[1];
    wire grat_bright_p = grat_q[0];

    // Layers not yet built.
    wire        text_on_p       = 1'b0;
    wire [23:0] text_color_p    = COL_TEXT;
    wire        trig_level_on_p = 1'b0;
    wire        trig_pos_on_p   = 1'b0;
    wire        trace_on_p      = 1'b0;

    // ---- Composite -------------------------------------------------
    logic [23:0] rgb;
    compositor u_comp (
        .de            (de_p),
        .text_on       (text_on_p),
        .text_color    (text_color_p),
        .trig_level_on (trig_level_on_p),
        .trig_pos_on   (trig_pos_on_p),
        .trace_on      (trace_on_p),
        .grat_on       (grat_on_p),
        .grat_bright   (grat_bright_p),
        .rgb           (rgb)
    );

    // ---- Bring-up ramp option ------------------------------------
    logic [7:0] rgb_r, rgb_g, rgb_b;
    always_comb begin
        if (TEST_PATTERN) begin
            rgb_r = de_p ? x[7:0]           : 8'h00;
            rgb_g = de_p ? y[7:0]           : 8'h00;
            rgb_b = de_p ? {8{x[6] ^ y[6]}} : 8'h00;
        end else begin
            rgb_r = rgb[23:16];
            rgb_g = rgb[15:8];
            rgb_b = rgb[7:0];
        end
    end

    // ---- Gowin DVI_TX IP ---------------------------------------
    // Real IP netlist under rtl/video/gowin_dvi_tx/ in synthesis (generate once
    // in Gowin EDA, see docs/DISPLAY.md); fpga/sim/models/DVI_TX_Top.sv shim in
    // simulation. Port names must match the generated wrapper exactly.
    DVI_TX_Top u_dvi (
        .I_rst_n       (rst_pix_n),
        .I_serial_clk  (serial_clk),
        .I_rgb_clk     (pix_clk),
        .I_rgb_vs      (vsync_p),
        .I_rgb_hs      (hsync_p),
        .I_rgb_de      (de_p),
        .I_rgb_r       (rgb_r),
        .I_rgb_g       (rgb_g),
        .I_rgb_b       (rgb_b),
        .O_tmds_clk_p  (tmds_clk_p),
        .O_tmds_clk_n  (tmds_clk_n),
        .O_tmds_data_p (tmds_data_p),
        .O_tmds_data_n (tmds_data_n)
    );

endmodule

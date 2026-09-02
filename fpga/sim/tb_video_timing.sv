/*
 * File: tb_video_timing.sv
 * Description: Checks video_timing_gen produces exact 1280x720p60 timing:
 *              H_TOTAL pixels per line, V_TOTAL lines per frame, H_ACTIVE
 *              data-enable pixels on an active line, the hsync/vsync pulse
 *              widths, the H front porch, positive sync polarity, and
 *              line_start / frame_start alignment to x==0 / y==0.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

`timescale 1ns/1ps

module tb_video_timing;
    import video_pkg::*;
    `include "tb_common.svh"

    logic pix_clk = 0, rst_n = 0;
    always #5 pix_clk = ~pix_clk;

    logic [11:0] x, y;
    logic        de, hsync, vsync, line_start, frame_start;

    video_timing_gen dut (
        .pix_clk     (pix_clk),
        .rst_n       (rst_n),
        .x           (x),
        .y           (y),
        .de          (de),
        .hsync       (hsync),
        .vsync       (vsync),
        .line_start  (line_start),
        .frame_start (frame_start)
    );

    `TB_DUMP("build/tb_video_timing.vcd")

    integer n, lines, hi, porch, i;

    initial begin
        repeat (4) @(posedge pix_clk);
        rst_n = 1;

        // ---- pixels per line: gap between two line_start strobes ----
        @(posedge pix_clk); while (!line_start) @(posedge pix_clk);
        `EXPECT_EQ(x, 12'd0, "x == 0 on a line_start cycle");
        n = 1;
        @(posedge pix_clk);
        while (!line_start) begin n = n + 1; @(posedge pix_clk); end
        `EXPECT_EQ(n, H_TOTAL, "pixels per line = H_TOTAL");

        // ---- lines per frame: line_start strobes across one frame ----
        @(posedge pix_clk); while (!frame_start) @(posedge pix_clk);
        `EXPECT_EQ(y, 12'd0, "y == 0 on a frame_start cycle");
        lines = 1;                       // the frame_start line itself
        @(posedge pix_clk);
        while (!frame_start) begin
            if (line_start) lines = lines + 1;
            @(posedge pix_clk);
        end
        `EXPECT_EQ(lines, V_TOTAL, "lines per frame = V_TOTAL");

        // ---- data-enable width on a mid-screen active line ----
        @(posedge pix_clk);
        while (!(line_start && y >= 12'd100 && y < 12'd200)) @(posedge pix_clk);
        n = 0;
        for (i = 0; i < H_TOTAL; i = i + 1) begin
            if (de) n = n + 1;
            @(posedge pix_clk);
        end
        `EXPECT_EQ(n, H_ACTIVE, "de high pixels on an active line = H_ACTIVE");

        // ---- sync polarity: both sync low during an active pixel ----
        @(posedge pix_clk);
        while (!(de && x == 12'd640 && y == 12'd360)) @(posedge pix_clk);
        `EXPECT(hsync === 1'b0 && vsync === 1'b0,
                "hsync/vsync low during active video (positive polarity)");

        // ---- hsync pulse width ----
        @(posedge pix_clk); while (!hsync) @(posedge pix_clk);
        hi = 0;
        while (hsync) begin hi = hi + 1; @(posedge pix_clk); end
        `EXPECT_EQ(hi, H_SYNC, "hsync width = H_SYNC");

        // ---- H front porch: last active pixel -> hsync rising ----
        @(posedge pix_clk);
        while (!(de && x == 12'(H_ACTIVE - 1))) @(posedge pix_clk);
        @(posedge pix_clk);
        `EXPECT(!de, "de low immediately after the last active pixel");
        porch = 0;
        while (!hsync) begin porch = porch + 1; @(posedge pix_clk); end
        `EXPECT_EQ(porch, H_FRONT, "H front porch = H_FRONT");

        // ---- vsync pulse width in whole lines ----
        @(posedge pix_clk); while (!vsync) @(posedge pix_clk);
        lines = 0;
        while (vsync) begin
            @(posedge pix_clk);
            if (line_start) lines = lines + 1;
        end
        `EXPECT_EQ(lines, V_SYNC, "vsync width = V_SYNC lines");

        `TB_FINISH("tb_video_timing");
    end
endmodule

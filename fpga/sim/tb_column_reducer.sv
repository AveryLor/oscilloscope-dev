/*
 * File: tb_column_reducer.sv
 * Description: Feeds column_reducer a synthetic frozen record through a stub read
 *              port that mimics the capture_buffer 1-cycle registered read, then
 *              reads back every column of waveform_col_ram and checks the
 *              per-column {y_min, y_max} against an independent reference model of
 *              the entry-window DDA and the code->screen-y map. Covers a record
 *              shorter than the plot width (nearest-sample repeat), one longer
 *              than it (many entries per column), and a wrapped ring start.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

`timescale 1ns/1ps

module tb_column_reducer;
    import scope_pkg::*;
    import video_pkg::*;
    `include "tb_common.svh"

    localparam int DEPTH = 2048;
    localparam int AW    = $clog2(DEPTH);
    localparam int CW    = SCOPE_CNT_W;

    localparam logic [17:0]        VSCALE  = 18'd576;
    localparam logic signed [11:0] VOFFSET = 12'sd0;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic              frozen_pix = 0;
    logic [AW-1:0]     rec_start_pix = 0;
    logic [CW-1:0]     rec_count_pix = 0;
    logic              frame_start = 0;

    logic [AW-1:0]        buf_rd_addr;
    logic                 buf_rd_en;
    logic [SCOPE_DW-1:0]  buf_rd_data;

    logic                 col_wr_en;
    logic [$clog2(COL_N)-1:0] col_wr_col;
    logic [COL_YW-1:0]    col_wr_ymin, col_wr_ymax;
    logic                 wr_bank, disp_bank, busy;

    column_reducer #(.DEPTH(DEPTH)) dut (
        .pix_clk       (clk),
        .rst_n         (rst_n),
        .frozen_pix    (frozen_pix),
        .rec_start_pix (rec_start_pix),
        .rec_count_pix (rec_count_pix),
        .frame_start   (frame_start),
        .vscale        (VSCALE),
        .voffset       (VOFFSET),
        .buf_rd_addr   (buf_rd_addr),
        .buf_rd_en     (buf_rd_en),
        .buf_rd_data   (buf_rd_data),
        .col_wr_en     (col_wr_en),
        .col_wr_col    (col_wr_col),
        .col_wr_ymin   (col_wr_ymin),
        .col_wr_ymax   (col_wr_ymax),
        .wr_bank       (wr_bank),
        .disp_bank     (disp_bank),
        .busy          (busy)
    );

    logic [COL_YW-1:0] rd_ymin, rd_ymax;
    logic [$clog2(COL_N)-1:0] rd_col = 0;

    waveform_col_ram u_ram (
        .clk       (clk),
        .wr_bank   (wr_bank),
        .wr_col    (col_wr_col),
        .wr_en     (col_wr_en),
        .wr_ymin   (col_wr_ymin),
        .wr_ymax   (col_wr_ymax),
        .disp_bank (disp_bank),
        .rd_col    (rd_col),
        .rd_ymin   (rd_ymin),
        .rd_ymax   (rd_ymax)
    );

    // ---- Stub capture buffer: 1-cycle registered read, like capture_buffer ----
    logic [15:0] fake_mem [0:DEPTH-1];
    always_ff @(posedge clk) begin
        if (buf_rd_en) buf_rd_data <= fake_mem[buf_rd_addr];
    end

    // ---- Free-running frame_start so R_SWAP_WAIT always completes ----
    integer fs_cnt = 0;
    always_ff @(posedge clk) begin
        fs_cnt      <= (fs_cnt == 63) ? 0 : fs_cnt + 1;
        frame_start <= (fs_cnt == 63);
    end

    // ---- Reference model ----
    function automatic logic [9:0] code_of(input integer addr);
        integer p, trv;
        p = addr % 200;
        trv = (p < 100) ? (p * 8) : ((200 - p) * 8);   // 0..792
        code_of = 10'(112 + trv);                       // 112..912
    endfunction

    function automatic integer ref_y(input logic [9:0] code);
        integer cr, pr, dyf, yc;
        cr  = code - 512;
        pr  = cr * 576;
        dyf = pr >>> 10;
        yc  = PLOT_YC - dyf + 0;
        if (yc < PLOT_Y0)      ref_y = PLOT_Y0;
        else if (yc > PLOT_Y1) ref_y = PLOT_Y1;
        else                   ref_y = yc;
    endfunction

    // Expected column {min,max} for the current rec_start/rec_count.
    task automatic expect_col(input integer c, output integer emin, output integer emax);
        integer e0, e1, e, a, yy, rc, rs;
        rc = rec_count_pix;
        rs = rec_start_pix;
        e0 = (c * rc) / COL_N;
        e1 = ((c + 1) * rc) / COL_N;
        emin = PLOT_Y1;
        emax = PLOT_Y0;
        if (e0 == e1) begin
            e  = (e0 < rc) ? e0 : (rc - 1);
            a  = (rs + e) % DEPTH;
            yy = ref_y(code_of(a));
            emin = yy; emax = yy;
        end else begin
            for (e = e0; e < e1; e = e + 1) begin
                a  = (rs + e) % DEPTH;
                yy = ref_y(code_of(a));
                if (yy < emin) emin = yy;
                if (yy > emax) emax = yy;
            end
        end
    endtask

    integer k, c, exp_min, exp_max, mism;

    task automatic run_case(input [AW-1:0] rs, input [CW-1:0] rc, input string tag);
        // fill the whole stub memory
        for (k = 0; k < DEPTH; k = k + 1) fake_mem[k] = {6'b0, code_of(k)};

        rec_start_pix = rs;
        rec_count_pix = rc;
        @(posedge clk);
        frozen_pix = 1'b1;                 // rising edge kicks the reducer
        @(posedge clk);
        // wait for the reduction + bank swap to finish
        wait (busy == 1'b1);
        wait (busy == 1'b0);
        repeat (4) @(posedge clk);

        mism = 0;
        for (c = 0; c < COL_N; c = c + 1) begin
            rd_col = c[$clog2(COL_N)-1:0];
            @(posedge clk); @(posedge clk);   // 1-cycle registered read + margin
            expect_col(c, exp_min, exp_max);
            if (rd_ymin !== COL_YW'(exp_min) || rd_ymax !== COL_YW'(exp_max)) begin
                mism = mism + 1;
                if (mism <= 4)
                    $display("  [%s] col %0d: got {%0d,%0d} exp {%0d,%0d}",
                             tag, c, rd_ymin, rd_ymax, exp_min, exp_max);
            end
        end
        `EXPECT_EQ(mism, 0, $sformatf("%s: all %0d columns match reference", tag, COL_N));

        frozen_pix = 1'b0;
        repeat (4) @(posedge clk);
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        run_case(11'd0,   16'd512,  "short");   // rec_count < COL_N
        run_case(11'd0,   16'd1536, "long");    // rec_count > COL_N
        run_case(11'd1717, 16'd900, "wrapped"); // ring start near the top

        // Bank ping-pong: disp_bank must be the opposite of the write bank.
        `EXPECT_EQ(disp_bank, ~wr_bank, "disp_bank is the non-write bank");

        `TB_FINISH("tb_column_reducer");
    end
endmodule

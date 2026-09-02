/*
 * File: column_reducer.sv
 * Description: Turns a frozen capture record into a per-column {y_min, y_max}
 *              trace for the display. On each new freeze it walks every plot
 *              column, maps the record-entry window for that column through the
 *              capture-buffer read port, converts each 10-bit code to a screen-y
 *              with the vertical scale/offset, keeps the column min and max, and
 *              writes the inactive bank of waveform_col_ram. The write/display
 *              bank swap happens on the next frame_start so the scan-out side
 *              never sees a half-built trace. Everything is in the pixel-clock
 *              domain: the ~1.24 M cycles per frame dwarf the <=DEPTH+COL_N
 *              cycles this needs.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

module column_reducer
    import scope_pkg::*;
    import video_pkg::*;
#(
    parameter int DEPTH = 16384,
    parameter int AW    = $clog2(DEPTH),
    parameter int CW    = SCOPE_CNT_W,
    parameter int CA    = $clog2(COL_N)
) (
    input  logic                 pix_clk,
    input  logic                 rst_n,

    // Capture domain, synced. Static while frozen_pix is high.
    input  logic                 frozen_pix,
    input  logic [AW-1:0]        rec_start_pix,
    input  logic [CW-1:0]        rec_count_pix,
    input  logic                 frame_start,

    // Vertical map: y = PLOT_YC - ((code-512)*vscale >>> 10) + voffset.
    input  logic [17:0]          vscale,
    input  logic signed [11:0]   voffset,

    // capture_buffer read port (registered read, 1-cycle latency).
    output logic [AW-1:0]        buf_rd_addr,
    output logic                 buf_rd_en,
    input  logic [SCOPE_DW-1:0]  buf_rd_data,

    // waveform_col_ram write port.
    output logic                 col_wr_en,
    output logic [CA-1:0]        col_wr_col,
    output logic [COL_YW-1:0]    col_wr_ymin,
    output logic [COL_YW-1:0]    col_wr_ymax,
    output logic                 wr_bank,
    output logic                 disp_bank,
    output logic                 busy
);

    assign disp_bank = ~wr_bank;

    typedef enum logic [3:0] {
        R_IDLE,
        R_COL_BEGIN,
        R_COL_DDA,
        R_COL_PREP,
        R_FETCH_WAIT,
        R_FETCH_ACC,
        R_COL_WRITE,
        R_SWAP_WAIT
    } r_state_e;

    r_state_e      state;
    logic          frozen_d;

    logic [CW-1:0] rec_count_l;
    logic [AW-1:0] rec_start_l;
    logic [CW:0]   acc;
    logic [CW-1:0] e_start, e_end, fetch_idx;
    logic [CA:0]   col;
    logic [COL_YW-1:0] y_min, y_max;
    logic          single;

    // Entry -> buffer address. DEPTH is a power of two and the ring is exactly
    // DEPTH deep, so truncation to AW bits is the modulo.
    function automatic logic [AW-1:0] rec_addr(input logic [CW-1:0] ent);
        rec_addr = rec_start_l + ent[AW-1:0];
    endfunction

    // Code -> screen y with clamp to the plot box.
    function automatic logic [COL_YW-1:0] map_y(input logic [9:0] code);
        logic signed [15:0] cr, dyf, yc;
        logic signed [31:0] pr;
        cr  = $signed({6'b0, code}) - 16'sd512;
        pr  = cr * $signed({14'b0, vscale});
        dyf = 16'(pr >>> 10);
        yc  = $signed(16'(PLOT_YC)) - dyf + $signed(16'(voffset));
        if (yc < $signed(16'(PLOT_Y0)))      map_y = COL_YW'(PLOT_Y0);
        else if (yc > $signed(16'(PLOT_Y1))) map_y = COL_YW'(PLOT_Y1);
        else                                 map_y = yc[COL_YW-1:0];
    endfunction

    wire [CW-1:0] clamp_last = (rec_count_l == 0) ? '0 : (rec_count_l - 1'b1);
    wire [CW-1:0] idx0 = (e_start == e_end)
                         ? ((e_start < rec_count_l) ? e_start : clamp_last)
                         : e_start;
    wire [COL_YW-1:0] y_sample = map_y(buf_rd_data[9:0]);

    always_ff @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= R_IDLE;
            frozen_d    <= 1'b0;
            wr_bank     <= 1'b0;
            busy        <= 1'b0;
            buf_rd_en   <= 1'b0;
            buf_rd_addr <= '0;
            col_wr_en   <= 1'b0;
        end else begin
            frozen_d  <= frozen_pix;
            buf_rd_en <= 1'b0;
            col_wr_en <= 1'b0;

            unique case (state)
                R_IDLE: begin
                    busy <= 1'b0;
                    if (frozen_pix && !frozen_d) begin
                        rec_count_l <= (rec_count_pix > CW'(DEPTH)) ? CW'(DEPTH)
                                                                   : rec_count_pix;
                        rec_start_l <= rec_start_pix;
                        acc         <= '0;
                        e_end       <= '0;
                        col         <= '0;
                        busy        <= 1'b1;
                        state       <= R_COL_BEGIN;
                    end
                end

                R_COL_BEGIN: begin
                    e_start <= e_end;
                    acc     <= acc + {1'b0, rec_count_l};
                    state   <= R_COL_DDA;
                end

                R_COL_DDA: begin
                    if (acc >= {1'b0, CW'(COL_N)}) begin
                        acc   <= acc - {1'b0, CW'(COL_N)};
                        e_end <= e_end + 1'b1;
                    end else begin
                        state <= R_COL_PREP;
                    end
                end

                R_COL_PREP: begin
                    single <= (e_start == e_end);
                    if (rec_count_l == 0) begin
                        y_min <= COL_YW'(PLOT_YC);
                        y_max <= COL_YW'(PLOT_YC);
                        state <= R_COL_WRITE;
                    end else begin
                        y_min       <= COL_YW'(PLOT_Y1);
                        y_max       <= COL_YW'(PLOT_Y0);
                        fetch_idx   <= idx0;
                        buf_rd_addr <= rec_addr(idx0);
                        buf_rd_en   <= 1'b1;
                        state       <= R_FETCH_WAIT;
                    end
                end

                R_FETCH_WAIT: state <= R_FETCH_ACC;

                R_FETCH_ACC: begin
                    if (y_sample < y_min) y_min <= y_sample;
                    if (y_sample > y_max) y_max <= y_sample;
                    if (single || (fetch_idx + 1'b1 >= e_end)) begin
                        state <= R_COL_WRITE;
                    end else begin
                        fetch_idx   <= fetch_idx + 1'b1;
                        buf_rd_addr <= rec_addr(fetch_idx + 1'b1);
                        buf_rd_en   <= 1'b1;
                        state       <= R_FETCH_WAIT;
                    end
                end

                R_COL_WRITE: begin
                    col_wr_en   <= 1'b1;
                    col_wr_col  <= col[CA-1:0];
                    col_wr_ymin <= y_min;
                    col_wr_ymax <= y_max;
                    col         <= col + 1'b1;
                    if ((col + 1'b1) == COL_N) state <= R_SWAP_WAIT;
                    else                       state <= R_COL_BEGIN;
                end

                R_SWAP_WAIT: begin
                    if (frame_start) begin
                        wr_bank <= ~wr_bank;
                        busy    <= 1'b0;
                        state   <= R_IDLE;
                    end
                end

                default: state <= R_IDLE;
            endcase
        end
    end

endmodule

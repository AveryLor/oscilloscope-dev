/*
 * File: waveform_col_ram.sv
 * Description: Double-buffered per-column trace display memory. One {y_min, y_max}
 *              entry per plot column, in screen-y space. column_reducer fills the
 *              inactive bank while trace_render scans the active bank; both ports
 *              are in the pixel-clock domain so the ping-pong needs no CDC. Two
 *              separate memory arrays so place-and-route maps them cleanly to
 *              independent BSRAM.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

module waveform_col_ram
    import video_pkg::*;
#(
    parameter int N  = COL_N,
    parameter int YW = COL_YW,
    parameter int CA = $clog2(COL_N)
) (
    input  logic          clk,

    // Write port (column_reducer).
    input  logic          wr_bank,
    input  logic [CA-1:0] wr_col,
    input  logic          wr_en,
    input  logic [YW-1:0] wr_ymin,
    input  logic [YW-1:0] wr_ymax,

    // Read port (trace_render); disp_bank is the bank NOT being written.
    input  logic          disp_bank,
    input  logic [CA-1:0] rd_col,
    output logic [YW-1:0] rd_ymin,
    output logic [YW-1:0] rd_ymax
);

    localparam int EW = 2 * YW;

    (* ram_style = "block" *) logic [EW-1:0] mem0 [N];
    (* ram_style = "block" *) logic [EW-1:0] mem1 [N];

    always_ff @(posedge clk) begin
        if (wr_en && wr_bank == 1'b0) mem0[wr_col] <= {wr_ymax, wr_ymin};
        if (wr_en && wr_bank == 1'b1) mem1[wr_col] <= {wr_ymax, wr_ymin};
    end

    logic [EW-1:0] rd0, rd1;
    always_ff @(posedge clk) begin
        rd0 <= mem0[rd_col];
        rd1 <= mem1[rd_col];
    end

    assign {rd_ymax, rd_ymin} = disp_bank ? rd1 : rd0;

endmodule

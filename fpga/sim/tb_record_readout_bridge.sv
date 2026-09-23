/*
 * File: tb_record_readout_bridge.sv
 * Description: record_readout_bridge walks a stubbed frozen buffer from rec_start
 *              for rec_count entries and serializes each 16-bit word into two
 *              little-endian bytes, advancing one entry per two pops. Reading
 *              past the record returns the pad byte and flags underflow.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_record_readout_bridge;
    import scope_pkg::*;
    `include "tb_common.svh"

    localparam int DEPTH = 64;
    localparam int AW    = 6;
    localparam int CW    = SCOPE_CNT_W;

    logic          clk = 0, rst_n = 0;
    logic          frozen = 0, rewind = 0;
    logic [AW-1:0] rec_start = 0;
    logic [CW-1:0] rec_count = 0;
    logic [AW-1:0] rd_addr;
    logic          rd_en;
    logic [SCOPE_DW-1:0] rd_data;
    logic [7:0]    rec_byte;
    logic          rec_advance = 0, rec_done, rec_underflow;
    always #5 clk = ~clk;

    // Stub frozen buffer: entry i holds {is_max=0, or=0, code=i}.
    logic [SCOPE_DW-1:0] mem [DEPTH];
    integer j;
    initial for (j = 0; j < DEPTH; j = j + 1) mem[j] = j[SCOPE_DW-1:0];
    always @(posedge clk) if (rd_en) rd_data <= mem[rd_addr];

    record_readout_bridge #(.DEPTH(DEPTH)) dut (
        .clk(clk), .rst_n(rst_n),
        .frozen(frozen), .rec_start(rec_start), .rec_count(rec_count), .rewind(rewind),
        .buf_rd_addr(rd_addr), .buf_rd_en(rd_en), .buf_rd_data(rd_data),
        .rec_byte(rec_byte), .rec_advance(rec_advance), .rec_done(rec_done),
        .rec_underflow(rec_underflow));

    logic [7:0] got;
    integer     i;

    task automatic pop_byte(output logic [7:0] b);
        b = rec_byte;                 // FWFT: current head
        rec_advance = 1'b1; @(posedge clk); #1;
        rec_advance = 1'b0; @(posedge clk); #1;
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        rec_start = 6'd4;
        rec_count = CW'(6);
        @(posedge clk);
        frozen = 1'b1;                // rising edge kicks the prefetch
        repeat (12) @(posedge clk); #1;

        // 6 entries * 2 bytes: entry (4+n) -> low = 4+n, high = 0.
        for (i = 0; i < 6; i = i + 1) begin
            pop_byte(got);
            `EXPECT_EQ(got, 8'(4 + i), "record low byte");
            pop_byte(got);
            `EXPECT_EQ(got, 8'h00, "record high byte");
        end

        `EXPECT_EQ(rec_done, 1'b1, "record done after last byte");
        pop_byte(got);
        `EXPECT_EQ(got, SCOPE_REC_PAD, "pad byte past the end");
        `EXPECT_EQ(rec_underflow, 1'b1, "underflow flagged");

        `TB_FINISH("tb_record_readout_bridge");
    end
endmodule

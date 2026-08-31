/*
 * File: async_fifo.sv
 * Description: Dual-clock FIFO with Gray-coded read/write pointers, after the
 *              classic Cummings design. Depth must be a power of two. Used to
 *              hand register writes from the SPI clock domain to the 27 MHz
 *              housekeeping domain; also handy anywhere a small elastic buffer is
 *              needed across clocks. First-word-fall-through: rd_data always
 *              shows the head, rd_en advances past it.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module async_fifo #(
    parameter int DW    = 8,
    parameter int DEPTH = 64,
    parameter int AW    = $clog2(DEPTH)
) (
    input  logic          wr_clk,
    input  logic          wr_rst_n,
    input  logic          wr_en,
    input  logic [DW-1:0] wr_data,
    output logic          full,

    input  logic          rd_clk,
    input  logic          rd_rst_n,
    input  logic          rd_en,
    output logic [DW-1:0] rd_data,
    output logic          empty
);

    function automatic logic [AW:0] bin2gray(input logic [AW:0] b);
        return b ^ (b >> 1);
    endfunction

    logic [DW-1:0] mem [DEPTH];

    // Pointers initialised to 0 so they are defined even if the reset never sees
    // a falling edge (GW2AR registers power up to 0, matching).
    logic [AW:0] wr_bin = '0, wr_bin_next;
    logic [AW:0] wr_gray = '0, wr_gray_next;
    (* syn_keep = "true", syn_preserve = "true" *)
    logic [AW:0] rd_gray_wsync [2];

    logic [AW:0] rd_bin = '0, rd_bin_next;
    logic [AW:0] rd_gray = '0, rd_gray_next;
    (* syn_keep = "true", syn_preserve = "true" *)
    logic [AW:0] wr_gray_rsync [2];

    initial begin
        rd_gray_wsync[0] = '0; rd_gray_wsync[1] = '0;
        wr_gray_rsync[0] = '0; wr_gray_rsync[1] = '0;
    end

    // ---- Write side --------------------------------------------------------
    assign wr_bin_next  = wr_bin + (wr_en & ~full);
    assign wr_gray_next = bin2gray(wr_bin_next);

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin  <= '0;
            wr_gray <= '0;
        end else begin
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
        end
    end

    always_ff @(posedge wr_clk) begin
        if (wr_en && !full) begin
            mem[wr_bin[AW-1:0]] <= wr_data;
        end
    end

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_wsync[0] <= '0;
            rd_gray_wsync[1] <= '0;
        end else begin
            rd_gray_wsync[0] <= rd_gray;
            rd_gray_wsync[1] <= rd_gray_wsync[0];
        end
    end

    // full when the next write pointer catches the read pointer one lap ahead
    // (top two Gray bits inverted).
    assign full = (wr_gray_next ==
                   {~rd_gray_wsync[1][AW:AW-1], rd_gray_wsync[1][AW-2:0]});

    // ---- Read side --------------------------------------------------------
    assign rd_bin_next  = rd_bin + (rd_en & ~empty);
    assign rd_gray_next = bin2gray(rd_bin_next);

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin  <= '0;
            rd_gray <= '0;
        end else begin
            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_rsync[0] <= '0;
            wr_gray_rsync[1] <= '0;
        end else begin
            wr_gray_rsync[0] <= wr_gray;
            wr_gray_rsync[1] <= wr_gray_rsync[0];
        end
    end

    assign empty   = (rd_gray == wr_gray_rsync[1]);
    assign rd_data = mem[rd_bin[AW-1:0]];

endmodule

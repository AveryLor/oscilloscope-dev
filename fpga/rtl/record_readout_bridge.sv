/*
 * File: record_readout_bridge.sv
 * Description: Serves the frozen capture record to the SPI protocol layer as a
 *              byte stream. Runs in the spi_sclk domain and reads the (static,
 *              frozen) capture buffer directly. Each 16-bit entry becomes two
 *              little-endian bytes: low = code[7:0], high = {is_max, over_range,
 *              4'b0, code[9:8]}.
 *
 * The capture-buffer read port takes two cycles from "address driven" to "data
 * readable here", so every fetch is issue -> wait -> latch. A two-word lookahead
 * (word_cur / word_nxt) covers the gap; the SPI side consumes at most one byte
 * per eight SCLK, far slower than the fetch, so the prefetch is always ready.
 * emit_idx restarts on rewind or when a new record freezes.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module record_readout_bridge
    import scope_pkg::*;
#(
    parameter int DEPTH = 16384,
    parameter int AW    = $clog2(DEPTH),
    parameter int CW    = SCOPE_CNT_W
) (
    input  logic          clk,        // spi_sclk
    input  logic          rst_n,

    input  logic          frozen,     // synced from the capture domain
    input  logic [AW-1:0] rec_start,  // synced, valid while frozen
    input  logic [CW-1:0] rec_count,  // synced, valid while frozen
    input  logic          rewind,     // pulse: restart from the first byte

    // Capture-buffer read port (registered read).
    output logic [AW-1:0] buf_rd_addr,
    output logic          buf_rd_en,
    input  logic [SCOPE_DW-1:0] buf_rd_data,

    // Byte stream to spi_protocol.
    output logic [7:0]    rec_byte,
    input  logic          rec_advance, // pulse at each REC_DATA byte boundary
    output logic          rec_done,
    output logic          rec_underflow
);

    localparam int TOTW = CW + 1;  // total bytes = 2 * rec_count

    typedef enum logic [3:0] {
        S_IDLE,
        S_ISSUE0, S_WAIT0, S_LATCH0,
        S_WAIT1,  S_LATCH1,
        S_RUN,
        S_PF_WAIT, S_PF_LATCH
    } state_e;

    // Initialised so they are defined before the first (gated) SCLK edge.
    state_e          state      = S_IDLE;
    logic [TOTW-1:0] total_bytes;
    logic [TOTW-1:0] emit_idx   = '0;
    logic [TOTW-1:0] next_entry = '0;
    logic            frozen_d   = 1'b0;

    logic [SCOPE_DW-1:0] word_cur, word_nxt;
    logic [7:0]          lo_byte, hi_byte;

    initial begin
        buf_rd_addr   = '0;
        buf_rd_en     = 1'b0;
        rec_underflow = 1'b0;
        word_cur      = '0;
        word_nxt      = '0;
    end

    assign total_bytes = {rec_count, 1'b0};
    assign rec_done    = (emit_idx >= total_bytes);
    assign lo_byte     = word_cur[7:0];
    assign hi_byte     = {word_cur[SCOPE_DW-1], word_cur[SCOPE_DW-2], 4'b0000,
                          word_cur[9:8]};
    assign rec_byte    = rec_done ? SCOPE_REC_PAD
                                  : (emit_idx[0] ? hi_byte : lo_byte);

    function automatic logic [AW-1:0] entry_addr(input logic [TOTW-1:0] ent);
        logic [CW:0] sum;
        sum = {1'b0, rec_start} + ent[CW:0];
        return AW'(sum % DEPTH);
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            emit_idx      <= '0;
            next_entry    <= '0;
            frozen_d      <= 1'b0;
            word_cur      <= '0;
            word_nxt      <= '0;
            buf_rd_addr   <= '0;
            buf_rd_en     <= 1'b0;
            rec_underflow <= 1'b0;
        end else begin
            frozen_d  <= frozen;
            buf_rd_en <= 1'b0;

            // A byte pulled past the end of the record is an underflow, whatever
            // the fetch state machine is doing.
            if (rec_advance && rec_done && state != S_IDLE) begin
                rec_underflow <= 1'b1;
            end

            if ((frozen && !frozen_d) || rewind) begin
                emit_idx      <= '0;
                rec_underflow <= 1'b0;
                next_entry    <= '0;
                state         <= S_ISSUE0;
            end else begin
                unique case (state)
                    S_IDLE: ;

                    S_ISSUE0: begin
                        buf_rd_addr <= entry_addr('0);
                        buf_rd_en   <= 1'b1;
                        next_entry  <= TOTW'(1);
                        state       <= S_WAIT0;
                    end
                    S_WAIT0:  state <= S_LATCH0;
                    S_LATCH0: begin
                        word_cur    <= buf_rd_data;
                        buf_rd_addr <= entry_addr(next_entry);  // entry 1
                        buf_rd_en   <= 1'b1;
                        next_entry  <= next_entry + 1'b1;        // -> entry 2
                        state       <= S_WAIT1;
                    end
                    S_WAIT1:  state <= S_LATCH1;
                    S_LATCH1: begin
                        word_nxt <= buf_rd_data;
                        state    <= S_RUN;
                    end

                    S_RUN: begin
                        if (rec_advance && !rec_done) begin
                            emit_idx <= emit_idx + 1'b1;
                            if (emit_idx[0]) begin
                                // Finished an entry: slide the window and start
                                // fetching the entry after word_nxt.
                                word_cur    <= word_nxt;
                                buf_rd_addr <= entry_addr(next_entry);
                                buf_rd_en   <= 1'b1;
                                state       <= S_PF_WAIT;
                            end
                        end
                    end

                    S_PF_WAIT: begin
                        state <= S_PF_LATCH;
                        if (rec_advance && !rec_done) emit_idx <= emit_idx + 1'b1;
                    end
                    S_PF_LATCH: begin
                        word_nxt   <= buf_rd_data;
                        next_entry <= next_entry + 1'b1;
                        state      <= S_RUN;
                        if (rec_advance && !rec_done) emit_idx <= emit_idx + 1'b1;
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule

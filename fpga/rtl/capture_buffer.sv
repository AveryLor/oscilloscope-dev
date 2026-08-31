/*
 * File: capture_buffer.sv
 * Description: Circular sample RAM with independent write (capture) and read
 *              (readout) clocks, mapped to BSRAM. Writes run free while the
 *              engine is running and not frozen. On trig_pulse the write pointer
 *              is latched; cfg_post_count more entries are written; then the
 *              record is frozen and the write side stops until the next start
 *              pulse. Record geometry (start address, entry count, trigger
 *              offset) is latched at the freeze cycle and stays static while
 *              frozen, so the read side can consume it through a plain
 *              synchronizer gated by a synced frozen flag.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module capture_buffer
    import scope_pkg::*;
#(
    parameter int DEPTH = 16384,
    parameter int DW    = SCOPE_DW,
    parameter int AW    = $clog2(DEPTH),
    parameter int CW    = SCOPE_CNT_W
) (
    // Write / capture domain.
    input  logic          wr_clk,
    input  logic          wr_rst_n,
    input  logic          start,          // pulse: begin a fresh fill (at ARM)
    input  logic          abort,          // pulse: drop everything, unfreeze
    input  logic          run,            // level: writes allowed (armed..post)
    input  logic          wr_en,          // a decimated entry is present
    input  logic [DW-1:0] wr_data,
    input  logic          trig_pulse,
    input  logic [CW-1:0] cfg_pre_count,
    input  logic [CW-1:0] cfg_post_count,
    output logic          frozen_w,
    output logic          triggered_w,
    output logic [AW-1:0] rec_start,
    output logic [CW-1:0] rec_count,
    output logic [CW-1:0] rec_trig_off,
    output logic [CW-1:0] valid_count,
    output logic [15:0]   overrange_cnt,

    // Read / readout domain.
    input  logic          rd_clk,
    input  logic [AW-1:0] rd_addr,
    input  logic          rd_en,
    output logic [DW-1:0] rd_data
);

    // Inferred BSRAM: one write port on wr_clk, one registered read port on
    // rd_clk. Reads only occur while frozen, so a read never races a write to
    // the same address.
    (* ram_style = "block" *)
    logic [DW-1:0] mem [DEPTH];

    logic [AW-1:0] wr_ptr;
    logic          triggered;
    logic [CW-1:0] post_written;
    logic [CW-1:0] vc_at_trig;
    logic [AW-1:0] trig_ptr;

    assign triggered_w = triggered;

    // Geometry helpers from values latched at the trigger.
    logic [CW-1:0] pre_used;
    logic [CW-1:0] geom_count;
    assign pre_used   = (vc_at_trig >= cfg_pre_count) ? cfg_pre_count : vc_at_trig;
    assign geom_count = ((pre_used + cfg_post_count) > CW'(DEPTH))
                        ? CW'(DEPTH)
                        : (pre_used + cfg_post_count);

    function automatic logic [AW-1:0] wrap_sub(input logic [AW-1:0] base,
                                               input logic [CW-1:0] off);
        logic [CW:0] tmp;
        tmp = ({1'b0, base} + CW'(DEPTH) - {1'b0, off});
        return AW'(tmp % DEPTH);
    endfunction

    wire do_write  = wr_en && run && !frozen_w && !start && !abort;
    wire do_freeze = triggered && !frozen_w && (post_written >= cfg_post_count);

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr       <= '0;
            triggered    <= 1'b0;
            post_written <= '0;
            vc_at_trig   <= '0;
            trig_ptr     <= '0;
            valid_count   <= '0;
            frozen_w      <= 1'b0;
            rec_start     <= '0;
            rec_count     <= '0;
            rec_trig_off  <= '0;
            overrange_cnt <= '0;
        end else if (start || abort) begin
            wr_ptr        <= '0;
            triggered     <= 1'b0;
            post_written  <= '0;
            valid_count   <= '0;
            frozen_w      <= 1'b0;
            overrange_cnt <= '0;
        end else begin
            if (do_write) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr      <= (wr_ptr == AW'(DEPTH-1)) ? '0 : (wr_ptr + 1'b1);
                if (valid_count != CW'(DEPTH)) begin
                    valid_count <= valid_count + 1'b1;
                end
                if (wr_data[DW-2] && (overrange_cnt != 16'hFFFF)) begin
                    overrange_cnt <= overrange_cnt + 16'd1;
                end
            end

            if (trig_pulse && !triggered && !frozen_w) begin
                triggered  <= 1'b1;
                vc_at_trig <= valid_count;
                trig_ptr   <= wr_ptr;
            end else if (triggered && do_write) begin
                post_written <= post_written + 1'b1;
            end

            if (do_freeze) begin
                frozen_w     <= 1'b1;
                rec_trig_off <= pre_used;
                rec_count    <= geom_count;
                rec_start    <= wrap_sub(trig_ptr, pre_used);
            end
        end
    end

    // Registered read port.
    always_ff @(posedge rd_clk) begin
        if (rd_en) begin
            rd_data <= mem[rd_addr];
        end
    end

endmodule

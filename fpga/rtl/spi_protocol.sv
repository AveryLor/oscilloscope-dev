/*
 * File: spi_protocol.sv
 * Description: SPI register-file protocol layer, in the spi_sclk domain. Decodes
 *              the {RW, ADDR[6:0]} header, streams writes out on a strobe bus
 *              (top pushes them into the SPI->housekeeping FIFO), and serves
 *              reads: one turnaround byte, then reg[addr], reg[addr+1], ...
 *              REG_REC_DATA is special — the address offset does not advance and
 *              each read pops the record FIFO.
 *
 * Read-only values come from the synced status bundle, the synced encoder
 * counts, and constants; read-back of the writable registers comes from the
 * synced effective-config bundle so a value set by a knob reads the same as one
 * set by a write.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module spi_protocol
    import scope_pkg::*;
(
    input  logic        spi_sclk,
    input  logic        spi_cs_n,

    // From spi_slave.
    input  logic [7:0]  rx_byte,
    input  logic        rx_stb,
    input  logic [2:0]  bit_pos,
    output logic [7:0]  tx_byte,

    // Synced status / config read-back.
    input  scope_sta_t  sta,
    input  logic        irq_level,
    input  scope_cfg_t  cfg_rb,
    input  logic [15:0] probe_div_rb,
    input  logic        probe_en_rb,
    input  logic [7:0]  caps,
    input  logic [15:0] buf_depth,

    // Synced encoder read-back.
    input  logic [15:0] enc_hs_cnt,
    input  logic [15:0] enc_ho_cnt,
    input  logic [15:0] enc_tg_cnt,
    input  logic [5:0]  enc_btn,        // {tg_evt,tg_lvl,ho_evt,ho_lvl,hs_evt,hs_lvl}
    output logic        enc_btn_rd,     // pulse: ENC_BTN was read, clear events

    // Record readout bridge (same domain).
    input  logic [7:0]  rec_byte,
    input  logic        rec_done,
    input  logic        rec_underflow,
    output logic        rec_advance,   // pulse at each REC_DATA byte boundary

    // Register writes to the housekeeping side.
    output logic        host_wr_stb,
    output logic [6:0]  host_wr_addr,
    output logic [7:0]  host_wr_data,

    // Locally decoded, SPI-domain command.
    output logic        rewind_stb
);

    // Frame state, async-cleared between frames by CS. Initialised so it is
    // defined before the first CS edge; GW2AR registers power up to 0, matching.
    logic       have_hdr = 1'b0;
    logic       is_read  = 1'b0;
    logic [6:0] addr     = 7'd0;
    logic [7:0] frm_ix   = 8'd0;   // 0 = header, 1 = turnaround, >=2 = data slots

    wire is_rec  = (addr == 7'(REG_REC_DATA));
    wire is_ebtn = (addr == 7'(REG_ENC_BTN));

    // Frame state only. rx_stb is high on a byte's 8th rising edge, so the byte
    // is consumed on the same edge it completes (no one-byte lag).
    always_ff @(posedge spi_sclk or posedge spi_cs_n) begin
        if (spi_cs_n) begin
            have_hdr <= 1'b0;
            is_read  <= 1'b0;
            addr     <= 7'd0;
            frm_ix   <= 8'd0;
        end else if (rx_stb) begin
            frm_ix <= frm_ix + 8'd1;
            if (!have_hdr) begin
                have_hdr <= 1'b1;
                is_read  <= rx_byte[7];
                addr     <= rx_byte[6:0];
            end
        end
    end

    // Writes and one-shot commands are combinational, valid on the completing
    // rising edge, so the last byte of a frame is not lost to CS deassert.
    wire is_write_byte = have_hdr && !is_read && rx_stb;
    assign host_wr_stb  = is_write_byte;
    assign host_wr_addr = is_rec ? addr : (addr + frm_ix[6:0] - 7'd1);
    assign host_wr_data = rx_byte;
    assign rewind_stb   = is_write_byte && (addr == 7'(REG_CONTROL))
                       && rx_byte[CTRL_REC_REWIND_BIT];
    assign enc_btn_rd   = have_hdr && is_read && is_ebtn && rx_stb
                       && (frm_ix >= 8'd2);

    // Combinational read of any address.
    function automatic logic [7:0] reg_rd(input logic [6:0] a);
        unique case (a)
            7'(REG_ID0):             reg_rd = SCOPE_ID0_VAL;
            7'(REG_ID1):             reg_rd = SCOPE_ID1_VAL;
            7'(REG_VER_MAJ):         reg_rd = SCOPE_VER_MAJ_VAL;
            7'(REG_VER_MIN):         reg_rd = SCOPE_VER_MIN_VAL;
            7'(REG_CAPS):            reg_rd = caps;
            7'(REG_BUF_DEPTH_L):     reg_rd = buf_depth[7:0];
            7'(REG_BUF_DEPTH_H):     reg_rd = buf_depth[15:8];
            7'(REG_CONTROL):         reg_rd = {5'b0, cfg_rb.invert_en, cfg_rb.auto_rearm, 1'b0};
            7'(REG_MODE):            reg_rd = {5'b0, cfg_rb.peak_en, cfg_rb.mode};
            7'(REG_TRIG_CFG):        reg_rd = {4'b0, cfg_rb.trig_edge, cfg_rb.trig_src};
            7'(REG_TRIG_LEVEL_L):    reg_rd = cfg_rb.trig_level[7:0];
            7'(REG_TRIG_LEVEL_H):    reg_rd = {6'b0, cfg_rb.trig_level[9:8]};
            7'(REG_TRIG_HYST):       reg_rd = cfg_rb.trig_hyst;
            7'(REG_DEC_FACTOR_L):    reg_rd = cfg_rb.dec_factor[7:0];
            7'(REG_DEC_FACTOR_H):    reg_rd = cfg_rb.dec_factor[15:8];
            7'(REG_PRE_COUNT_L):     reg_rd = cfg_rb.pre_count[7:0];
            7'(REG_PRE_COUNT_H):     reg_rd = cfg_rb.pre_count[15:8];
            7'(REG_POST_COUNT_L):    reg_rd = cfg_rb.post_count[7:0];
            7'(REG_POST_COUNT_H):    reg_rd = cfg_rb.post_count[15:8];
            7'(REG_AUTO_TMO_0):      reg_rd = cfg_rb.auto_timeout[7:0];
            7'(REG_AUTO_TMO_1):      reg_rd = cfg_rb.auto_timeout[15:8];
            7'(REG_AUTO_TMO_2):      reg_rd = cfg_rb.auto_timeout[23:16];
            7'(REG_AUTO_TMO_3):      reg_rd = cfg_rb.auto_timeout[31:24];
            7'(REG_PROBE_DIV_L):     reg_rd = probe_div_rb[7:0];
            7'(REG_PROBE_DIV_H):     reg_rd = probe_div_rb[15:8];
            7'(REG_PROBE_CTL):       reg_rd = {7'b0, probe_en_rb};
            7'(REG_STATUS):          reg_rd = {sta.overrun, sta.triggered_by_auto,
                                               irq_level, sta.pll_lock, sta.frozen,
                                               sta.state};
            7'(REG_SAMPLE_COUNT_0):  reg_rd = sta.sample_count[7:0];
            7'(REG_SAMPLE_COUNT_1):  reg_rd = sta.sample_count[15:8];
            7'(REG_SAMPLE_COUNT_2):  reg_rd = sta.sample_count[23:16];
            7'(REG_SAMPLE_COUNT_3):  reg_rd = sta.sample_count[31:24];
            7'(REG_TRIG_PTR_0):      reg_rd = sta.trig_ptr[7:0];
            7'(REG_TRIG_PTR_1):      reg_rd = sta.trig_ptr[15:8];
            7'(REG_TRIG_PTR_2):      reg_rd = sta.trig_ptr[23:16];
            7'(REG_TRIG_PTR_3):      reg_rd = sta.trig_ptr[31:24];
            7'(REG_TRIG_PHASE_L):    reg_rd = sta.trig_phase[7:0];
            7'(REG_TRIG_PHASE_H):    reg_rd = sta.trig_phase[15:8];
            7'(REG_OVERRANGE_CNT_L): reg_rd = sta.overrange_cnt[7:0];
            7'(REG_OVERRANGE_CNT_H): reg_rd = sta.overrange_cnt[15:8];
            7'(REG_ENC_HS_L):        reg_rd = enc_hs_cnt[7:0];
            7'(REG_ENC_HS_H):        reg_rd = enc_hs_cnt[15:8];
            7'(REG_ENC_HO_L):        reg_rd = enc_ho_cnt[7:0];
            7'(REG_ENC_HO_H):        reg_rd = enc_ho_cnt[15:8];
            7'(REG_ENC_TG_L):        reg_rd = enc_tg_cnt[7:0];
            7'(REG_ENC_TG_H):        reg_rd = enc_tg_cnt[15:8];
            7'(REG_ENC_BTN):         reg_rd = {2'b0, enc_btn};
            7'(REG_REC_DATA):        reg_rd = rec_byte;
            7'(REG_REC_STATUS):      reg_rd = {5'b0, rec_underflow, rec_done, 1'b0};
            default:                 reg_rd = 8'h00;
        endcase
    endfunction

    // Byte for the slot currently shifting out. frm_ix is stable through a byte
    // and steps at each byte boundary, so this is a clean per-byte mux. Slot 0
    // (header shifting in) and slot 1 (turnaround) send 0x00.
    always_comb begin
        if (!have_hdr || !is_read || (frm_ix <= 8'd1)) begin
            tx_byte = 8'h00;
        end else if (is_rec) begin
            tx_byte = rec_byte;
        end else begin
            tx_byte = reg_rd(addr + frm_ix[6:0] - 7'd2);
        end
    end

    // Step the record readout at the last bit of each REC_DATA data byte, so the
    // bridge's next byte is settled before the following byte starts shifting.
    assign rec_advance = have_hdr && is_read && is_rec
                      && (frm_ix >= 8'd2) && (bit_pos == 3'd7);

endmodule

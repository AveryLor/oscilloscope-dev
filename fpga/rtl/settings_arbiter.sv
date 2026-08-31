/*
 * File: settings_arbiter.sv
 * Description: Housekeeping-domain owner of every writable setting. It pops host
 *              register writes from the SPI->HK FIFO, decodes the three
 *              horizontal / trigger encoders, and merges the two sources into one
 *              authoritative config (last writer wins). Any change registers the
 *              new value and, one cycle later, flips commit_tog so the config
 *              crossers re-sample settled data. CONTROL write-1 bits become
 *              single-cycle command pulses.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module settings_arbiter
    import scope_pkg::*;
#(
    parameter int DEPTH     = 16384,
    parameter int CW        = SCOPE_CNT_W,
    parameter int LEVEL_STEP = 8,
    parameter int SPLIT_STEP = 64,
    parameter int ENC_DEBOUNCE = 400,
    parameter int AUTO_TMO_DEFAULT = 10_500_000  // ~100 ms of 105 MHz ticks
) (
    input  logic        clk,
    input  logic        rst_n,

    // SPI -> HK register-write FIFO (read side).
    input  logic        wr_pending,
    input  logic [6:0]  wr_addr,
    input  logic [7:0]  wr_data,
    output logic        wr_pop,

    // Raw encoder pins.
    input  logic        dial_hs_a, dial_hs_b, dial_hs_btn,
    input  logic        dial_ho_a, dial_ho_b, dial_ho_btn,
    input  logic        dial_tg_a, dial_tg_b, dial_tg_btn,
    input  logic        enc_btn_clr,     // pulse, synced from SPI

    // Authoritative config out.
    output scope_cfg_t  cfg_o,
    output logic [15:0] probe_div_o,
    output logic        probe_en_o,
    output logic        commit_tog,

    // Command pulses (HK domain).
    output logic        cmd_arm,
    output logic        cmd_abort,
    output logic        cmd_force,
    output logic        cmd_irq_clr,
    output logic        cmd_soft_reset,

    // Encoder read-back (HK domain; top crosses these to SPI).
    output logic [15:0] enc_hs_cnt,
    output logic [15:0] enc_ho_cnt,
    output logic [15:0] enc_tg_cnt,
    output logic [5:0]  enc_btn
);

    // ---- Encoders -----------------------------------------------------------
    logic signed [15:0] hs_cnt, ho_cnt, tg_cnt;
    logic [15:0]        hs_gray, ho_gray, tg_gray;
    logic               hs_lvl, hs_evt, ho_lvl, ho_evt, tg_lvl, tg_evt;

    quad_decoder #(.CNT_W(16), .DEBOUNCE_CYC(ENC_DEBOUNCE)) u_qd_hs (
        .clk(clk), .rst_n(rst_n),
        .a_raw(dial_hs_a), .b_raw(dial_hs_b), .btn_raw(dial_hs_btn),
        .count(hs_cnt), .count_gray(hs_gray),
        .btn_level(hs_lvl), .btn_event(hs_evt), .btn_event_clr(enc_btn_clr)
    );
    quad_decoder #(.CNT_W(16), .DEBOUNCE_CYC(ENC_DEBOUNCE)) u_qd_ho (
        .clk(clk), .rst_n(rst_n),
        .a_raw(dial_ho_a), .b_raw(dial_ho_b), .btn_raw(dial_ho_btn),
        .count(ho_cnt), .count_gray(ho_gray),
        .btn_level(ho_lvl), .btn_event(ho_evt), .btn_event_clr(enc_btn_clr)
    );
    quad_decoder #(.CNT_W(16), .DEBOUNCE_CYC(ENC_DEBOUNCE)) u_qd_tg (
        .clk(clk), .rst_n(rst_n),
        .a_raw(dial_tg_a), .b_raw(dial_tg_b), .btn_raw(dial_tg_btn),
        .count(tg_cnt), .count_gray(tg_gray),
        .btn_level(tg_lvl), .btn_event(tg_evt), .btn_event_clr(enc_btn_clr)
    );

    assign enc_hs_cnt = hs_cnt;
    assign enc_ho_cnt = ho_cnt;
    assign enc_tg_cnt = tg_cnt;
    assign enc_btn    = {tg_evt, tg_lvl, ho_evt, ho_lvl, hs_evt, hs_lvl};

    // ---- Config registers -------------------------------------------------
    logic [1:0]  mode_r;
    logic        peak_r;
    logic [1:0]  tsrc_r;
    logic [1:0]  tedge_r;
    logic [9:0]  tlevel_r;
    logic [7:0]  thyst_r;
    logic [15:0] dec_r;
    logic [CW-1:0] pre_r;
    logic [CW-1:0] post_r;
    logic [31:0] tmo_r;
    logic        auto_rearm_r;
    logic        invert_r;
    logic [15:0] probe_div_r;
    logic        probe_en_r;

    logic signed [15:0] hs_prev, ho_prev, tg_prev;
    logic               changed;

    always_comb begin
        cfg_o.mode         = mode_r;
        cfg_o.peak_en      = peak_r;
        cfg_o.invert_en    = invert_r;
        cfg_o.auto_rearm   = auto_rearm_r;
        cfg_o.trig_src     = tsrc_r;
        cfg_o.trig_edge    = tedge_r;
        cfg_o.trig_level   = tlevel_r;
        cfg_o.trig_hyst    = thyst_r;
        cfg_o.dec_factor   = dec_r;
        cfg_o.pre_count    = pre_r;
        cfg_o.post_count   = post_r;
        cfg_o.auto_timeout = tmo_r;
    end
    assign probe_div_o = probe_div_r;
    assign probe_en_o  = probe_en_r;

    // Signed helpers for encoder-driven adjustments.
    function automatic logic [9:0] clamp_level(input logic signed [31:0] v);
        if (v < 0)         return 10'd0;
        else if (v > 1023) return 10'd1023;
        else               return v[9:0];
    endfunction

    function automatic logic [CW-1:0] clamp_cnt(input logic signed [31:0] v);
        if (v < 0)             return '0;
        else if (v > DEPTH)    return CW'(DEPTH);
        else                   return v[CW-1:0];
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode_r        <= 2'd0;
            peak_r        <= 1'b0;
            tsrc_r        <= 2'd0;
            tedge_r       <= 2'd0;
            tlevel_r      <= 10'h200;
            thyst_r       <= 8'h08;
            dec_r         <= 16'd0;
            pre_r         <= CW'(DEPTH/2);
            post_r        <= CW'(DEPTH/2);
            tmo_r         <= 32'(AUTO_TMO_DEFAULT);
            auto_rearm_r  <= 1'b0;
            invert_r      <= 1'b0;
            probe_div_r   <= 16'd0;
            probe_en_r    <= 1'b1;
            hs_prev       <= '0;
            ho_prev       <= '0;
            tg_prev       <= '0;
            commit_tog    <= 1'b0;
            wr_pop        <= 1'b0;
            cmd_arm        <= 1'b0;
            cmd_abort      <= 1'b0;
            cmd_force      <= 1'b0;
            cmd_irq_clr    <= 1'b0;
            cmd_soft_reset <= 1'b0;
        end else begin
            cmd_arm        <= 1'b0;
            cmd_abort      <= 1'b0;
            cmd_force      <= 1'b0;
            cmd_irq_clr    <= 1'b0;
            cmd_soft_reset <= 1'b0;
            wr_pop         <= 1'b0;
            changed         = 1'b0;

            // One host write per cycle.
            if (wr_pending && !wr_pop) begin
                wr_pop <= 1'b1;
                unique case (wr_addr)
                    7'(REG_CONTROL): begin
                        cmd_arm        <= wr_data[CTRL_ARM_BIT];
                        cmd_abort      <= wr_data[CTRL_ABORT_BIT];
                        cmd_force      <= wr_data[CTRL_FORCE_TRIG_BIT];
                        cmd_irq_clr    <= wr_data[CTRL_IRQ_CLR_BIT];
                        cmd_soft_reset <= wr_data[CTRL_SOFT_RESET_BIT];
                        auto_rearm_r   <= wr_data[CTRL_AUTO_REARM_BIT];
                        invert_r       <= wr_data[CTRL_INVERT_EN_BIT];
                        changed         = 1'b1;
                    end
                    7'(REG_MODE): begin
                        mode_r  <= wr_data[1:0];
                        peak_r  <= wr_data[MODE_PEAK_BIT];
                        changed  = 1'b1;
                    end
                    7'(REG_TRIG_CFG): begin
                        tsrc_r  <= wr_data[1:0];
                        tedge_r <= wr_data[3:2];
                        changed  = 1'b1;
                    end
                    7'(REG_TRIG_LEVEL_L): begin tlevel_r[7:0] <= wr_data;        changed = 1'b1; end
                    7'(REG_TRIG_LEVEL_H): begin tlevel_r[9:8] <= wr_data[1:0];   changed = 1'b1; end
                    7'(REG_TRIG_HYST):    begin thyst_r       <= wr_data;        changed = 1'b1; end
                    7'(REG_DEC_FACTOR_L): begin dec_r[7:0]    <= wr_data;        changed = 1'b1; end
                    7'(REG_DEC_FACTOR_H): begin dec_r[15:8]   <= wr_data;        changed = 1'b1; end
                    7'(REG_PRE_COUNT_L):  begin pre_r[7:0]    <= wr_data;        changed = 1'b1; end
                    7'(REG_PRE_COUNT_H):  begin pre_r[15:8]   <= wr_data;        changed = 1'b1; end
                    7'(REG_POST_COUNT_L): begin post_r[7:0]   <= wr_data;        changed = 1'b1; end
                    7'(REG_POST_COUNT_H): begin post_r[15:8]  <= wr_data;        changed = 1'b1; end
                    7'(REG_AUTO_TMO_0):   begin tmo_r[7:0]    <= wr_data;        changed = 1'b1; end
                    7'(REG_AUTO_TMO_1):   begin tmo_r[15:8]   <= wr_data;        changed = 1'b1; end
                    7'(REG_AUTO_TMO_2):   begin tmo_r[23:16]  <= wr_data;        changed = 1'b1; end
                    7'(REG_AUTO_TMO_3):   begin tmo_r[31:24]  <= wr_data;        changed = 1'b1; end
                    7'(REG_PROBE_DIV_L):  begin probe_div_r[7:0]  <= wr_data;    changed = 1'b1; end
                    7'(REG_PROBE_DIV_H):  begin probe_div_r[15:8] <= wr_data;    changed = 1'b1; end
                    7'(REG_PROBE_CTL):    begin probe_en_r    <= wr_data[PROBE_EN_BIT]; changed = 1'b1; end
                    default: ; // read-only or unmapped
                endcase
            end

            // Encoder-driven adjustments, one detent step per cycle.
            if (tg_cnt != tg_prev) begin
                if (tg_cnt > tg_prev) begin
                    tlevel_r <= clamp_level($signed({16'd0, tlevel_r}) + LEVEL_STEP);
                    tg_prev  <= tg_prev + 16'sd1;
                end else begin
                    tlevel_r <= clamp_level($signed({16'd0, tlevel_r}) - LEVEL_STEP);
                    tg_prev  <= tg_prev - 16'sd1;
                end
                changed = 1'b1;
            end
            if (hs_cnt != hs_prev) begin
                if (hs_cnt > hs_prev) begin
                    dec_r   <= (dec_r == 16'hFFFF) ? dec_r : ((dec_r << 1) | 16'd1);
                    hs_prev <= hs_prev + 16'sd1;
                end else begin
                    dec_r   <= (dec_r == 16'd0) ? dec_r : (dec_r >> 1);
                    hs_prev <= hs_prev - 16'sd1;
                end
                changed = 1'b1;
            end
            if (ho_cnt != ho_prev) begin
                if (ho_cnt > ho_prev) begin
                    pre_r   <= clamp_cnt($signed({12'd0, pre_r}) + SPLIT_STEP);
                    post_r  <= clamp_cnt($signed({12'd0, post_r}) - SPLIT_STEP);
                    ho_prev <= ho_prev + 16'sd1;
                end else begin
                    pre_r   <= clamp_cnt($signed({12'd0, pre_r}) - SPLIT_STEP);
                    post_r  <= clamp_cnt($signed({12'd0, post_r}) + SPLIT_STEP);
                    ho_prev <= ho_prev - 16'sd1;
                end
                changed = 1'b1;
            end

            if (changed) begin
                commit_tog <= ~commit_tog;
            end
        end
    end

endmodule

/*
 * File: top.sv
 * Description: Top-level RTL for the Tang Nano 20K oscilloscope FPGA design.
 *              Ties the ADC capture datapath (condition -> decimate -> trigger ->
 *              ring buffer -> acquisition FSM) in the 105 MHz sample domain to
 *              the SPI slave register file and record readout in the SPI domain,
 *              with the encoders, probe-comp generator and capture-ready IRQ in
 *              the 27 MHz housekeeping domain. See docs/PROTOCOL.md for the SPI
 *              contract.
 * Author: Avery Lor
 * Date: Aug 3 2026
 */

module top
    import scope_pkg::*;
#(
    parameter int SAMPLE_DEPTH = 16384,
    parameter int POR_CYCLES   = 135000  // ~5 ms of the 27 MHz crystal
) (
    input  logic       clk,
    input  logic       fpga_clk,
    input  logic [9:0] adc_d,
    input  logic       adc_or,
    input  logic       hw_trigger,
    input  logic       spi_sclk,
    input  logic       spi_cs,
    input  logic       spi_mosi,
    output logic       spi_miso,
    output logic       fpga_irq,
    input  logic       dial_hs_a,
    input  logic       dial_hs_b,
    input  logic       dial_hs_btn,
    input  logic       dial_ho_a,
    input  logic       dial_ho_b,
    input  logic       dial_ho_btn,
    input  logic       dial_tg_a,
    input  logic       dial_tg_b,
    input  logic       dial_tg_btn,
    output logic       probe_comp,
    input  logic [2:0] fpga_flex
);

    localparam int AW = $clog2(SAMPLE_DEPTH);
    localparam int CW = SCOPE_CNT_W;

    localparam logic [7:0] CAPS_VALUE =
        (8'b0
         | (8'b1 << CAPS_PEAK_BIT)
         | (8'b1 << CAPS_EXTTRIG_BIT)
         | ((SAMPLE_DEPTH == 32768) ? (8'b1 << CAPS_32K_BIT) : 8'b0));

    // fpga_flex[2:0] are spare trigger-mezzanine lines, reserved.
    wire _flex_unused = |{1'b0, fpga_flex};

    // ---- Clocking and reset ---------------------------------------------------
    logic adc_sample_clk;
    logic pll_lock;

    adc_pll u_adc_pll (
        .clkin   (fpga_clk),
        .clkoutp (adc_sample_clk),
        .lock    (pll_lock)
    );

    logic por_n;
    por_gen #(.RST_CYCLES(POR_CYCLES)) u_por (.clk(clk), .por_n(por_n));

    logic rst_hk_n;
    reset_sync u_rst_hk (.clk(clk), .arst_n(por_n), .rst_n(rst_hk_n));

    logic pll_lock_hk;
    cdc_bit_sync #(.WIDTH(1)) u_pll_lock_hk (.clk(clk), .d(pll_lock), .q(pll_lock_hk));

    logic cap_arst_n, rst_cap_n;
    assign cap_arst_n = por_n & pll_lock_hk;
    reset_sync u_rst_cap (.clk(adc_sample_clk), .arst_n(cap_arst_n), .rst_n(rst_cap_n));

    // ---- ADC input path: IOLOGIC pad registers ------------------------------
    // VIN+ / VIN- are swapped on the analog front end; adc_input_cond corrects
    // the codes around mid-scale when cfg.invert_en is set.
    (* syn_useioff = 1, syn_keep = "true" *) logic [9:0] adc_d_q;
    (* syn_useioff = 1, syn_keep = "true" *) logic       adc_or_q;
    (* syn_useioff = 1, syn_keep = "true" *) logic       hw_trigger_q;

    // Unconditional so these stay packed in IOLOGIC. pll_lock gating is done
    // downstream on the capture-buffer write, not here.
    always_ff @(posedge adc_sample_clk) begin
        adc_d_q      <= adc_d;
        adc_or_q     <= adc_or;
        hw_trigger_q <= hw_trigger;
    end

    (* syn_keep = "true" *) logic hw_trigger_sync;
    always_ff @(posedge adc_sample_clk) begin
        hw_trigger_sync <= hw_trigger_q;
    end

    // ---- Housekeeping domain: settings, encoders, probe comp, IRQ ------------
    scope_cfg_t  cfg_hk;
    logic [15:0] probe_div_hk;
    logic        probe_en_hk;
    logic        commit_tog_hk;
    logic        cmd_arm, cmd_abort, cmd_force, cmd_irq_clr, cmd_soft_reset;
    logic [15:0] enc_hs_cnt_hk, enc_ho_cnt_hk, enc_tg_cnt_hk;
    logic [5:0]  enc_btn_hk;

    logic        hw_wr_pending;
    logic [6:0]  hw_wr_addr;
    logic [7:0]  hw_wr_data;
    logic        hw_wr_pop;
    logic        enc_btn_clr_hk;

    settings_arbiter #(.DEPTH(SAMPLE_DEPTH)) u_settings (
        .clk         (clk),
        .rst_n       (rst_hk_n),
        .wr_pending  (hw_wr_pending),
        .wr_addr     (hw_wr_addr),
        .wr_data     (hw_wr_data),
        .wr_pop      (hw_wr_pop),
        .dial_hs_a   (dial_hs_a), .dial_hs_b(dial_hs_b), .dial_hs_btn(dial_hs_btn),
        .dial_ho_a   (dial_ho_a), .dial_ho_b(dial_ho_b), .dial_ho_btn(dial_ho_btn),
        .dial_tg_a   (dial_tg_a), .dial_tg_b(dial_tg_b), .dial_tg_btn(dial_tg_btn),
        .enc_btn_clr (enc_btn_clr_hk),
        .cfg_o       (cfg_hk),
        .probe_div_o (probe_div_hk),
        .probe_en_o  (probe_en_hk),
        .commit_tog  (commit_tog_hk),
        .cmd_arm     (cmd_arm),
        .cmd_abort   (cmd_abort),
        .cmd_force   (cmd_force),
        .cmd_irq_clr (cmd_irq_clr),
        .cmd_soft_reset (cmd_soft_reset),
        .enc_hs_cnt  (enc_hs_cnt_hk),
        .enc_ho_cnt  (enc_ho_cnt_hk),
        .enc_tg_cnt  (enc_tg_cnt_hk),
        .enc_btn     (enc_btn_hk)
    );

    probe_comp_gen u_probe (
        .clk     (clk),
        .rst_n   (rst_hk_n),
        .cfg_div (probe_div_hk),
        .cfg_en  (probe_en_hk),
        .sq_out  (probe_comp)
    );

    logic cap_irq_toggle;   // from the acquisition FSM (capture domain)
    logic irq_level_hk;

    irq_gen u_irq (
        .clk            (clk),
        .rst_n          (rst_hk_n),
        .irq_toggle_cap (cap_irq_toggle),
        .irq_clr        (cmd_irq_clr),
        .arm_seen       (cmd_arm),
        .irq_out        (fpga_irq),
        .irq_level      (irq_level_hk)
    );

    // ---- SPI -> HK register-write FIFO -------------------------------------
    logic        host_wr_stb;
    logic [6:0]  host_wr_addr;
    logic [7:0]  host_wr_data;
    logic        hw_fifo_empty;
    logic        hw_fifo_full;

    async_fifo #(.DW(15), .DEPTH(16)) u_hostwr_fifo (
        .wr_clk   (spi_sclk),
        .wr_rst_n (por_n),
        .wr_en    (host_wr_stb),
        .wr_data  ({host_wr_addr, host_wr_data}),
        .full     (hw_fifo_full),
        .rd_clk   (clk),
        .rd_rst_n (rst_hk_n),
        .rd_en    (hw_wr_pop),
        .rd_data  ({hw_wr_addr, hw_wr_data}),
        .empty    (hw_fifo_empty)
    );
    assign hw_wr_pending = ~hw_fifo_empty;

    // ---- Config crossings: HK -> CAP and HK -> SPI read-back --------------
    scope_cfg_t cfg_cap;
    logic       cfg_update_cap;
    logic [$bits(scope_cfg_t)-1:0] cfg_hk_flat, cfg_cap_flat;
    assign cfg_hk_flat = cfg_hk;
    assign cfg_cap     = cfg_cap_flat;

    config_cdc #(.WIDTH($bits(scope_cfg_t))) u_cfg_to_cap (
        .src_data   (cfg_hk_flat),
        .src_commit (commit_tog_hk),
        .dst_clk    (adc_sample_clk),
        .dst_rst_n  (rst_cap_n),
        .dst_data   (cfg_cap_flat),
        .dst_update (cfg_update_cap)
    );

    localparam int RB_W = $bits(scope_cfg_t) + 16 + 1;
    scope_cfg_t      cfg_rb_spi;
    logic [15:0]     probe_div_spi;
    logic            probe_en_spi;
    logic            rb_update_spi;
    logic [RB_W-1:0] rb_flat_spi;

    config_cdc #(.WIDTH(RB_W)) u_cfg_to_spi (
        .src_data   ({cfg_hk_flat, probe_div_hk, probe_en_hk}),
        .src_commit (commit_tog_hk),
        .dst_clk    (spi_sclk),
        .dst_rst_n  (por_n),
        .dst_data   (rb_flat_spi),
        .dst_update (rb_update_spi)
    );
    assign cfg_rb_spi    = rb_flat_spi[RB_W-1 -: $bits(scope_cfg_t)];
    assign probe_div_spi = rb_flat_spi[16:1];
    assign probe_en_spi  = rb_flat_spi[0];

    // ---- Capture datapath (adc_sample_clk domain) -----------------------------
    logic [9:0] cond_sample;
    logic       cond_or, cond_valid;

    adc_input_cond u_cond (
        .clk        (adc_sample_clk),
        .rst_n      (rst_cap_n),
        .invert_en  (cfg_cap.invert_en),
        .d_in       (adc_d_q),
        .or_in      (adc_or_q),
        .sample_out (cond_sample),
        .or_out     (cond_or),
        .valid_out  (cond_valid)
    );

    logic        fsm_arm_align;
    logic [9:0]  dec_sample;
    logic        dec_or, dec_is_max, dec_valid;
    logic [15:0] dec_phase;

    timebase_decimator u_decim (
        .clk            (adc_sample_clk),
        .rst_n          (rst_cap_n),
        .cfg_dec_factor (cfg_cap.dec_factor),
        .cfg_peak_mode  (cfg_cap.peak_en),
        .arm_align      (fsm_arm_align),
        .sample_in      (cond_sample),
        .or_in          (cond_or),
        .valid_in       (cond_valid),
        .sample_out     (dec_sample),
        .or_out         (dec_or),
        .is_max_out     (dec_is_max),
        .valid_out      (dec_valid),
        .dec_phase_out  (dec_phase)
    );

    logic fsm_armed, fsm_force_trig, trig_pulse;

    trigger_engine u_trig (
        .clk           (adc_sample_clk),
        .rst_n         (rst_cap_n),
        .sample_in     (cond_sample),
        .valid_in      (cond_valid),
        .ext_trig_sync (hw_trigger_sync),
        .cfg_src       (cfg_cap.trig_src),
        .cfg_edge      (cfg_cap.trig_edge),
        .cfg_level     (cfg_cap.trig_level),
        .cfg_hyst      (cfg_cap.trig_hyst),
        .armed         (fsm_armed),
        .force_trig    (fsm_force_trig),
        .trig_pulse    (trig_pulse)
    );

    logic [15:0] trig_phase_q;
    always_ff @(posedge adc_sample_clk or negedge rst_cap_n) begin
        if (!rst_cap_n)        trig_phase_q <= '0;
        else if (trig_pulse)   trig_phase_q <= dec_phase;
    end

    logic              fsm_buf_start, fsm_buf_abort, fsm_run;
    logic              buf_frozen_w, buf_triggered_w;
    logic [AW-1:0]     buf_rec_start;
    logic [CW-1:0]     buf_rec_count, buf_rec_trig_off, buf_valid_count;
    logic [15:0]       buf_overrange_cnt;
    logic [AW-1:0]     buf_rd_addr;
    logic              buf_rd_en;
    logic [SCOPE_DW-1:0] buf_rd_data;

    capture_buffer #(.DEPTH(SAMPLE_DEPTH)) u_buf (
        .wr_clk         (adc_sample_clk),
        .wr_rst_n       (rst_cap_n),
        .start          (fsm_buf_start),
        .abort          (fsm_buf_abort),
        .run            (fsm_run),
        .wr_en          (dec_valid),
        .wr_data        ({dec_is_max, dec_or, 4'b0000, dec_sample}),
        .trig_pulse     (trig_pulse),
        .cfg_pre_count  (cfg_cap.pre_count),
        .cfg_post_count (cfg_cap.post_count),
        .frozen_w       (buf_frozen_w),
        .triggered_w    (buf_triggered_w),
        .rec_start      (buf_rec_start),
        .rec_count      (buf_rec_count),
        .rec_trig_off   (buf_rec_trig_off),
        .valid_count    (buf_valid_count),
        .overrange_cnt  (buf_overrange_cnt),
        .rd_clk         (spi_sclk),
        .rd_addr        (buf_rd_addr),
        .rd_en          (buf_rd_en),
        .rd_data        (buf_rd_data)
    );

    logic [2:0] fsm_state;
    logic       fsm_trigd_auto, fsm_rearm_req, rearm_ack_cap;
    logic       arm_cap, abort_cap, force_cap;

    acq_ctrl_fsm u_fsm (
        .clk              (adc_sample_clk),
        .rst_n            (rst_cap_n),
        .cfg_mode         (cfg_cap.mode),
        .cfg_pre_count    (cfg_cap.pre_count),
        .cfg_auto_timeout (cfg_cap.auto_timeout),
        .cfg_auto_rearm   (cfg_cap.auto_rearm),
        .arm_stb          (arm_cap),
        .abort_stb        (abort_cap),
        .force_trig_stb   (force_cap),
        .trig_pulse       (trig_pulse),
        .valid_count      (buf_valid_count),
        .frozen_w         (buf_frozen_w),
        .rearm_req        (fsm_rearm_req),
        .rearm_ack        (rearm_ack_cap),
        .buf_start        (fsm_buf_start),
        .buf_abort        (fsm_buf_abort),
        .run              (fsm_run),
        .arm_align        (fsm_arm_align),
        .armed            (fsm_armed),
        .force_trig       (fsm_force_trig),
        .state_out        (fsm_state),
        .triggered_by_auto(fsm_trigd_auto),
        .irq_toggle       (cap_irq_toggle)
    );

    // ---- HK -> CAP command strobes -----------------------------------------
    cdc_pulse_toggle u_cmd_arm (
        .src_clk(clk), .src_rst_n(rst_hk_n), .src_pulse(cmd_arm),
        .dst_clk(adc_sample_clk), .dst_rst_n(rst_cap_n), .dst_pulse(arm_cap));
    cdc_pulse_toggle u_cmd_abort (
        .src_clk(clk), .src_rst_n(rst_hk_n), .src_pulse(cmd_abort | cmd_soft_reset),
        .dst_clk(adc_sample_clk), .dst_rst_n(rst_cap_n), .dst_pulse(abort_cap));
    cdc_pulse_toggle u_cmd_force (
        .src_clk(clk), .src_rst_n(rst_hk_n), .src_pulse(cmd_force),
        .dst_clk(adc_sample_clk), .dst_rst_n(rst_cap_n), .dst_pulse(force_cap));

    // Re-arm handshake: CAP asks, HK relays straight back; the two-sync round
    // trip is the guaranteed hold time before CAP resumes writing.
    logic rearm_req_hk;
    cdc_pulse_toggle u_rearm_req (
        .src_clk(adc_sample_clk), .src_rst_n(rst_cap_n), .src_pulse(fsm_rearm_req),
        .dst_clk(clk), .dst_rst_n(rst_hk_n), .dst_pulse(rearm_req_hk));
    cdc_pulse_toggle u_rearm_ack (
        .src_clk(clk), .src_rst_n(rst_hk_n), .src_pulse(rearm_req_hk),
        .dst_clk(adc_sample_clk), .dst_rst_n(rst_cap_n), .dst_pulse(rearm_ack_cap));

    // ---- Status crossing CAP -> SPI --------------------------------------
    scope_sta_t sta_spi;

    status_cdc u_sta (
        .cap_state         (fsm_state),
        .cap_frozen        (buf_frozen_w),
        .cap_pll_lock      (pll_lock),
        .cap_irq           (1'b0),
        .cap_trigd_auto    (fsm_trigd_auto),
        .cap_overrun       (1'b0),
        .cap_sample_count  (32'(buf_rec_count)),
        .cap_trig_ptr      (32'(buf_rec_trig_off)),
        .cap_trig_phase    (trig_phase_q),
        .cap_overrange_cnt (buf_overrange_cnt),
        .spi_clk           (spi_sclk),
        .spi_sta           (sta_spi)
    );

    logic [AW-1:0] rec_start_spi;
    cdc_bit_sync #(.WIDTH(AW)) u_recstart_spi (
        .clk(spi_sclk), .d(buf_rec_start), .q(rec_start_spi));

    logic irq_level_spi;
    cdc_bit_sync #(.WIDTH(1)) u_irqlvl_spi (
        .clk(spi_sclk), .d(irq_level_hk), .q(irq_level_spi));

    // ---- Encoder crossing HK -> SPI -------------------------------------
    logic [15:0] enc_hs_spi, enc_ho_spi, enc_tg_spi;
    cdc_gray_sync #(.WIDTH(16)) u_enc_hs (
        .src_clk(clk), .src_rst_n(rst_hk_n), .src_bin(enc_hs_cnt_hk),
        .dst_clk(spi_sclk), .dst_rst_n(por_n), .dst_bin(enc_hs_spi));
    cdc_gray_sync #(.WIDTH(16)) u_enc_ho (
        .src_clk(clk), .src_rst_n(rst_hk_n), .src_bin(enc_ho_cnt_hk),
        .dst_clk(spi_sclk), .dst_rst_n(por_n), .dst_bin(enc_ho_spi));
    cdc_gray_sync #(.WIDTH(16)) u_enc_tg (
        .src_clk(clk), .src_rst_n(rst_hk_n), .src_bin(enc_tg_cnt_hk),
        .dst_clk(spi_sclk), .dst_rst_n(por_n), .dst_bin(enc_tg_spi));

    logic [5:0] enc_btn_spi;
    cdc_bit_sync #(.WIDTH(6)) u_enc_btn (.clk(spi_sclk), .d(enc_btn_hk), .q(enc_btn_spi));

    // ---- Record readout bridge (spi_sclk domain) -----------------------
    logic [7:0] rec_byte;
    logic       rec_advance, rec_done, rec_underflow, rewind_stb;

    record_readout_bridge #(.DEPTH(SAMPLE_DEPTH)) u_readout (
        .clk           (spi_sclk),
        .rst_n         (por_n),
        .frozen        (sta_spi.frozen),
        .rec_start     (rec_start_spi),
        .rec_count     (sta_spi.sample_count[CW-1:0]),
        .rewind        (rewind_stb),
        .buf_rd_addr   (buf_rd_addr),
        .buf_rd_en     (buf_rd_en),
        .buf_rd_data   (buf_rd_data),
        .rec_byte      (rec_byte),
        .rec_advance   (rec_advance),
        .rec_done      (rec_done),
        .rec_underflow (rec_underflow)
    );

    // ---- SPI slave + protocol -----------------------------------------
    logic [7:0] spi_rx_byte, spi_tx_byte, spi_byte_idx;
    logic [2:0] spi_bit_pos;
    logic       spi_rx_stb;
    logic       enc_btn_rd_spi;

    spi_slave u_spi_slave (
        .spi_sclk (spi_sclk),
        .spi_cs_n (spi_cs),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso),
        .rx_byte  (spi_rx_byte),
        .rx_stb   (spi_rx_stb),
        .byte_idx (spi_byte_idx),
        .bit_pos  (spi_bit_pos),
        .tx_byte  (spi_tx_byte)
    );

    spi_protocol u_spi_proto (
        .spi_sclk     (spi_sclk),
        .spi_cs_n     (spi_cs),
        .rx_byte      (spi_rx_byte),
        .rx_stb       (spi_rx_stb),
        .bit_pos      (spi_bit_pos),
        .tx_byte      (spi_tx_byte),
        .sta          (sta_spi),
        .irq_level    (irq_level_spi),
        .cfg_rb       (cfg_rb_spi),
        .probe_div_rb (probe_div_spi),
        .probe_en_rb  (probe_en_spi),
        .caps         (CAPS_VALUE),
        .buf_depth    (16'(SAMPLE_DEPTH)),
        .enc_hs_cnt   (enc_hs_spi),
        .enc_ho_cnt   (enc_ho_spi),
        .enc_tg_cnt   (enc_tg_spi),
        .enc_btn      (enc_btn_spi),
        .enc_btn_rd   (enc_btn_rd_spi),
        .rec_byte     (rec_byte),
        .rec_done     (rec_done),
        .rec_underflow(rec_underflow),
        .rec_advance  (rec_advance),
        .host_wr_stb  (host_wr_stb),
        .host_wr_addr (host_wr_addr),
        .host_wr_data (host_wr_data),
        .rewind_stb   (rewind_stb)
    );

    // ENC_BTN read clears the button events (SPI -> HK).
    cdc_pulse_toggle u_encbtn_clr (
        .src_clk(spi_sclk), .src_rst_n(por_n), .src_pulse(enc_btn_rd_spi),
        .dst_clk(clk), .dst_rst_n(rst_hk_n), .dst_pulse(enc_btn_clr_hk));

endmodule

/*
 * File: tb_mode_persist.sv
 * Description: The acquisition type (MODE.b2 peak / MODE.b3 high-res) must
 *              survive captures. Drives top with the ESP32 firmware's exact SPI
 *              traffic: the boot configure (scope_or_protect_cfg + scope_arm),
 *              then per capture what stream.c does (read SAMPLE_COUNT and
 *              TRIG_PTR, REC_REWIND, a REC_DATA burst, IRQ_CLR, the
 *              scope_read_effective MODE..POST_COUNT burst, STATUS, and the
 *              scope_rearm CONTROL|ARM). A mode set by a host SET_ACQ
 *              (read-modify-write of MODE) or by the horizontal-scale button
 *              must read back unchanged after every following capture.
 * Author: Avery Lor
 * Date: Nov 15 2026
 */

`timescale 1ns/1ps

module tb_mode_persist;
    import scope_pkg::*;
    `include "tb_common.svh"

    localparam int DEPTH = 256;
    localparam int PRE   = 32;
    localparam int POST  = 32;

    logic clk = 0;        // 27 MHz housekeeping
    logic fpga_clk = 0;   // 100 MHz encode clock
    always #18 clk = ~clk;
    always #5  fpga_clk = ~fpga_clk;

    logic [9:0] adc_d, adc_d_src;
    logic       adc_or, adc_or_src;
    logic       spi_sclk, spi_cs, spi_mosi, spi_miso;
    logic       fpga_irq;
    logic       probe_comp;
    logic       hw_trigger = 1'b0;
    logic [1:0] fpga_flex  = 2'b00;
    logic       fpga_alarm;
    logic       dhs_a=1,dhs_b=1,dhs_btn=1, dho_a=1,dho_b=1,dho_btn=1, dtg_a=1,dtg_b=1,dtg_btn=1;

    adc_waveform_src #(.PERIOD(220)) u_src (
        .clk(fpga_clk), .rst_n(1'b1), .en(1'b1), .inject_spike(1'b0),
        .adc_d(adc_d_src), .adc_or(adc_or_src));

    // AD9215 output delay: tOD = 4.8 ns typical after the encode edge.
    assign #4.8 adc_d  = adc_d_src;
    logic or_force = 1'b0;   // drive a sustained over-range for the alarm test
    assign #4.8 adc_or = adc_or_src | or_force;

    spi_master_bfm #(.SCLK_NS(40.0)) mst (
        .sclk(spi_sclk), .cs_n(spi_cs), .mosi(spi_mosi), .miso(spi_miso));

    top #(.SAMPLE_DEPTH(DEPTH), .POR_CYCLES(64)) dut (
        .clk(clk), .fpga_clk(fpga_clk),
        .adc_d(adc_d), .adc_or(adc_or), .hw_trigger(hw_trigger),
        .spi_sclk(spi_sclk), .spi_cs(spi_cs), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
        .fpga_irq(fpga_irq),
        .dial_hs_a(dhs_a), .dial_hs_b(dhs_b), .dial_hs_btn(dhs_btn),
        .dial_ho_a(dho_a), .dial_ho_b(dho_b), .dial_ho_btn(dho_btn),
        .dial_tg_a(dtg_a), .dial_tg_b(dtg_b), .dial_tg_btn(dtg_btn),
        .probe_comp(probe_comp), .fpga_alarm(fpga_alarm), .fpga_flex(fpga_flex));

    logic [7:0] d;
    task automatic wr(input [6:0] a, input [7:0] v);
        mst.cs_lo(); mst.xfer_byte({1'b0, a}, d); mst.xfer_byte(v, d); mst.cs_hi();
    endtask
    task automatic rd(input [6:0] a, output [7:0] v);
        mst.cs_lo(); mst.xfer_byte({1'b1, a}, d); mst.xfer_byte(8'h00, d); mst.xfer_byte(8'h00, v); mst.cs_hi();
    endtask
    // ESP32 fpga_link_read_reg: one CS, header, turnaround, n bytes.
    logic [7:0] burst [0:63];
    task automatic rd_burst(input [6:0] a, input integer n);
        mst.cs_lo(); mst.xfer_byte({1'b1, a}, d); mst.xfer_byte(8'h00, d);
        for (int i = 0; i < n; i++) begin
            logic [7:0] q;
            mst.xfer_byte(8'h00, q);
            burst[i] = q;
        end
        mst.cs_hi();
    endtask

    // One ESP32 stream-loop iteration: scope_read_envelope, scope_read_effective,
    // STATUS, scope_rearm. CONTROL writes always carry INVERT_EN (0x10).
    task automatic esp_capture(output [7:0] mode_seen);
        for (int g = 0; g < 80000 && !fpga_irq; g++) #10;
        if (!fpga_irq) $display("  (capture timeout)");
        rd_burst(7'h21, 4);                  // SAMPLE_COUNT
        rd_burst(7'h25, 4);                  // TRIG_PTR
        wr(7'h08, 8'h50);                    // REC_REWIND | INVERT
        rd_burst(7'h40, 60);                 // REC_DATA chunk
        wr(7'h08, 8'h30);                    // IRQ_CLR | INVERT
        rd_burst(7'h09, 15);                 // scope_read_effective MODE..POST_H
        mode_seen = burst[0];
        rd(7'h20, d);                        // STATUS
        wr(7'h08, 8'h11);                    // scope_rearm: ARM | INVERT
    endtask

    logic [7:0] m;
    initial begin
        #4000;
        // Boot: scope_or_protect_cfg then scope_arm(initial), AUTO, sampled.
        mst.cs_lo(); mst.xfer_byte(8'h12, d); mst.xfer_byte(8'd20, d); mst.xfer_byte(8'd16, d); mst.cs_hi();
        wr(7'h09, 8'h01);  wr(7'h0A, 8'h00);
        mst.cs_lo(); mst.xfer_byte(8'h0C, d); mst.xfer_byte(8'h00, d); mst.xfer_byte(8'h02, d); mst.cs_hi();
        wr(7'h0E, 8'h04);
        mst.cs_lo(); mst.xfer_byte(8'h10, d); mst.xfer_byte(8'h03, d); mst.xfer_byte(8'h00, d); mst.cs_hi();
        mst.cs_lo(); mst.xfer_byte(8'h14, d); mst.xfer_byte(8'd32, d); mst.xfer_byte(8'h00, d); mst.cs_hi();
        mst.cs_lo(); mst.xfer_byte(8'h16, d); mst.xfer_byte(8'd32, d); mst.xfer_byte(8'h00, d); mst.cs_hi();
        mst.cs_lo(); mst.xfer_byte(8'h18, d); mst.xfer_byte(8'd200, d); mst.xfer_byte(0, d); mst.xfer_byte(0, d); mst.xfer_byte(0, d); mst.cs_hi();
        wr(7'h08, 8'h10); wr(7'h08, 8'h11);

        esp_capture(m); $display("boot capture       MODE=%02h", m);

        // live_cfg_set_acq(peak): read-modify-write MODE.
        rd(7'h09, d); wr(7'h09, (d & 8'h03) | 8'h04);
        for (int k = 0; k < 4; k++) begin esp_capture(m); $display("after SET_ACQ 1 #%0d MODE=%02h", k, m); end
        `EXPECT_EQ(m, 8'h05, "peak survives four captures");

        rd(7'h09, d); wr(7'h09, (d & 8'h03) | 8'h08);
        for (int k = 0; k < 4; k++) begin esp_capture(m); $display("after SET_ACQ 2 #%0d MODE=%02h", k, m); end
        `EXPECT_EQ(m, 8'h09, "high-res survives four captures");

        // Physical HS button press (active low, debounce 400 clk27 cycles).
        dhs_btn = 0; #40000; dhs_btn = 1; #40000;
        for (int k = 0; k < 3; k++) begin esp_capture(m); $display("after HS press  #%0d MODE=%02h", k, m); end
        `EXPECT_EQ(m, 8'h01, "HS press from high-res -> sampled, and it stays");
        dhs_btn = 0; #40000; dhs_btn = 1; #40000;
        for (int k = 0; k < 3; k++) begin esp_capture(m); $display("after HS press2 #%0d MODE=%02h", k, m); end
        `EXPECT_EQ(m, 8'h05, "second HS press -> peak, and it stays");
        `TB_FINISH("tb_mode_persist");
    end
endmodule

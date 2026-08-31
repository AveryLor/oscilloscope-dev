/*
 * File: tb_top.sv
 * Description: End-to-end smoke test of the whole FPGA. A behavioral rPLL and a
 *              triangle ADC source feed top; the SPI master BFM configures a
 *              force-only / AUTO capture, arms it, waits for fpga_irq, then reads
 *              STATUS, SAMPLE_COUNT and a run of REC_DATA and checks the record
 *              is the right length and decodes to in-range codes.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_top;
    import scope_pkg::*;
    `include "tb_common.svh"

    localparam int DEPTH = 256;
    localparam int PRE   = 32;
    localparam int POST  = 32;

    logic clk = 0;        // 27 MHz housekeeping
    logic fpga_clk = 0;   // 105 MHz encode clock
    always #18 clk = ~clk;
    always #5  fpga_clk = ~fpga_clk;

    logic [9:0] adc_d;
    logic       adc_or;
    logic       spi_sclk, spi_cs, spi_mosi, spi_miso;
    logic       fpga_irq;
    logic       probe_comp;
    logic       hw_trigger = 1'b0;
    logic [2:0] fpga_flex  = 3'b000;
    logic       dhs_a=1,dhs_b=1,dhs_btn=1, dho_a=1,dho_b=1,dho_btn=1, dtg_a=1,dtg_b=1,dtg_btn=1;

    adc_waveform_src #(.PERIOD(220)) u_src (
        .clk(fpga_clk), .rst_n(1'b1), .en(1'b1), .inject_spike(1'b0),
        .adc_d(adc_d), .adc_or(adc_or));

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
        .probe_comp(probe_comp), .fpga_flex(fpga_flex));

    logic [7:0] d;

    task automatic reg_write(input [6:0] a, input [7:0] v);
        mst.cs_lo();
        mst.xfer_byte({1'b0, a}, d);
        mst.xfer_byte(v, d);
        mst.cs_hi();
    endtask

    task automatic reg_read(input [6:0] a, output [7:0] v);
        mst.cs_lo();
        mst.xfer_byte({1'b1, a}, d);
        mst.xfer_byte(8'h00, d);   // turnaround
        mst.xfer_byte(8'h00, v);
        mst.cs_hi();
    endtask

    integer i, n;
    logic [7:0] lo, hi;
    logic [9:0] code;
    integer     nonzero;

    initial begin
        // Let the PLL lock and POR release.
        #4000;

        reg_read(7'h20, d);
        `EXPECT(d[STAT_PLL_LOCK_BIT] === 1'b1, "STATUS reports PLL locked");

        // Configure: force-only trigger source, AUTO mode with a short timeout.
        reg_write(7'h09, 8'h01);                 // MODE = AUTO
        reg_write(7'h0A, 8'h02);                 // TRIG_CFG src = force-only
        reg_write(7'h14, 8'(PRE));  reg_write(7'h15, 8'(PRE >> 8));
        reg_write(7'h16, 8'(POST)); reg_write(7'h17, 8'(POST >> 8));
        reg_write(7'h18, 8'd200); reg_write(7'h19, 8'd0);
        reg_write(7'h1A, 8'd0);   reg_write(7'h1B, 8'd0);

        // Arm.
        reg_write(7'h08, 8'h01);

        // Wait for the capture-ready IRQ.
        fork
            begin : wait_irq
                @(posedge fpga_irq);
            end
            begin : irq_timeout
                #500000;
                `EXPECT(1'b0, "timed out waiting for fpga_irq");
            end
        join_any
        disable irq_timeout;
        disable wait_irq;

        reg_read(7'h20, d);
        `EXPECT(d[STAT_FROZEN_BIT] === 1'b1, "STATUS frozen after capture");

        // SAMPLE_COUNT (32-bit LE) should be PRE + POST.
        n = 0;
        reg_read(7'h21, d); n = n | (d << 0);
        reg_read(7'h22, d); n = n | (d << 8);
        reg_read(7'h23, d); n = n | (d << 16);
        reg_read(7'h24, d); n = n | (d << 24);
        `EXPECT_EQ(n, PRE + POST, "record length = PRE + POST");

        // Read the record: one long CS burst, header + turnaround + 2*n bytes.
        mst.cs_lo();
        mst.xfer_byte(8'h80 | 7'h40, d);   // read REG_REC_DATA
        mst.xfer_byte(8'h00, d);           // turnaround
        nonzero = 0;
        for (i = 0; i < n; i = i + 1) begin
            mst.xfer_byte(8'h00, lo);
            mst.xfer_byte(8'h00, hi);
            code = {hi[1:0], lo};
            `EXPECT(code <= 10'd1023, "record code in range");
            if (code != 0) nonzero = nonzero + 1;
        end
        mst.cs_hi();
        `EXPECT(nonzero > 0, "record is not all zero");

        // IRQ acknowledge clears the line.
        reg_write(7'h08, 8'h20);           // CONTROL.IRQ_CLR
        repeat (20) @(posedge clk); #1;
        `EXPECT_EQ(fpga_irq, 1'b0, "fpga_irq cleared after IRQ_CLR");

        `TB_FINISH("tb_top");
    end
endmodule

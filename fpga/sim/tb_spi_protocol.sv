/*
 * File: tb_spi_protocol.sv
 * Description: spi_slave + spi_protocol over the SPI master BFM. Checks the read
 *              turnaround byte and ID/VERSION values, little-endian multi-byte
 *              config read-back from a stubbed effective-config bundle, that
 *              writes emit host_wr strobes with an auto-incrementing address, and
 *              that a REC_DATA burst pops the record stream in order.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_spi_protocol;
    import scope_pkg::*;
    `include "tb_common.svh"

    logic sclk, cs_n, mosi, miso;

    spi_master_bfm #(.SCLK_NS(20.0)) mst (
        .sclk(sclk), .cs_n(cs_n), .mosi(mosi), .miso(miso));

    logic [7:0] rx_byte, byte_idx, tx_byte;
    logic [2:0] bit_pos;
    logic       rx_stb;

    spi_slave u_slave (
        .spi_sclk(sclk), .spi_cs_n(cs_n), .spi_mosi(mosi), .spi_miso(miso),
        .rx_byte(rx_byte), .rx_stb(rx_stb), .byte_idx(byte_idx),
        .bit_pos(bit_pos), .tx_byte(tx_byte));

    // Stubbed synced inputs.
    scope_sta_t  sta;
    scope_cfg_t  cfg_rb;
    logic        irq_level = 1'b0;
    logic [15:0] probe_div_rb = 16'h0000;
    logic        probe_en_rb  = 1'b1;

    initial begin
        sta = '0;
        cfg_rb = '0;
        cfg_rb.trig_level = 10'h123;  // L=0x23, H=0x01
        cfg_rb.dec_factor = 16'hABCD;
        cfg_rb.mode       = 2'd2;
    end

    // Stub record bridge: rec_byte increments on each byte-boundary advance,
    // starting at 0x10.
    logic [7:0] rec_byte = 8'h10;
    logic       rec_advance;
    always @(posedge sclk) if (rec_advance) rec_byte <= rec_byte + 8'd1;

    logic       host_wr_stb;
    logic [6:0] host_wr_addr;
    logic [7:0] host_wr_data;
    logic       enc_btn_rd, rewind_stb;

    // Capture the write strobes.
    logic [6:0] wlog_addr [0:7];
    logic [7:0] wlog_data [0:7];
    integer     wlog_n = 0;
    always @(posedge sclk) if (host_wr_stb) begin
        wlog_addr[wlog_n] = host_wr_addr;
        wlog_data[wlog_n] = host_wr_data;
        wlog_n = wlog_n + 1;
    end

    spi_protocol u_proto (
        .spi_sclk(sclk), .spi_cs_n(cs_n),
        .rx_byte(rx_byte), .rx_stb(rx_stb), .bit_pos(bit_pos), .tx_byte(tx_byte),
        .sta(sta), .irq_level(irq_level), .cfg_rb(cfg_rb),
        .probe_div_rb(probe_div_rb), .probe_en_rb(probe_en_rb),
        .caps(8'h0B), .buf_depth(16'd16384),
        .enc_hs_cnt(16'd0), .enc_ho_cnt(16'd0), .enc_tg_cnt(16'd0),
        .enc_btn(6'd0), .enc_btn_rd(enc_btn_rd),
        .rec_byte(rec_byte), .rec_done(1'b0), .rec_underflow(1'b0), .rec_advance(rec_advance),
        .host_wr_stb(host_wr_stb), .host_wr_addr(host_wr_addr), .host_wr_data(host_wr_data),
        .rewind_stb(rewind_stb));

    logic [7:0] d;
    integer i;

    initial begin
        #100;

        // --- Read ID0..VER_MIN (addr 0x00, 4 bytes) ---
        mst.cs_lo();
        mst.xfer_byte(8'h80, d);              // header: read, addr 0x00
        mst.xfer_byte(8'h00, d); `EXPECT_EQ(d, 8'h00, "turnaround byte");
        mst.xfer_byte(8'h00, d); `EXPECT_EQ(d, 8'h53, "ID0 = 'S'");
        mst.xfer_byte(8'h00, d); `EXPECT_EQ(d, 8'h43, "ID1 = 'C'");
        mst.xfer_byte(8'h00, d); `EXPECT_EQ(d, 8'h01, "VER_MAJ = 1");
        mst.xfer_byte(8'h00, d); `EXPECT_EQ(d, 8'h00, "VER_MIN = 0");
        mst.cs_hi();

        // --- Read TRIG_LEVEL_L/H (little-endian 0x123) ---
        mst.cs_lo();
        mst.xfer_byte(8'h80 | 7'h0C, d);
        mst.xfer_byte(8'h00, d);                        // turnaround
        mst.xfer_byte(8'h00, d); `EXPECT_EQ(d, 8'h23, "TRIG_LEVEL_L");
        mst.xfer_byte(8'h00, d); `EXPECT_EQ(d, 8'h01, "TRIG_LEVEL_H");
        mst.cs_hi();

        // --- Write DEC_FACTOR_L/H = 0x0207, address auto-increments ---
        wlog_n = 0;
        mst.cs_lo();
        mst.xfer_byte(8'h00 | 7'h10, d);   // header: write, addr 0x10
        mst.xfer_byte(8'h07, d);
        mst.xfer_byte(8'h02, d);
        mst.cs_hi();
        `EXPECT_EQ(wlog_n, 2, "two write strobes");
        `EXPECT_EQ(wlog_addr[0], 7'h10, "first write addr");
        `EXPECT_EQ(wlog_data[0], 8'h07, "first write data");
        `EXPECT_EQ(wlog_addr[1], 7'h11, "second write addr auto-incremented");
        `EXPECT_EQ(wlog_data[1], 8'h02, "second write data");

        // --- REC_DATA burst: increments 0x10, 0x11, 0x12, 0x13 ---
        mst.cs_lo();
        mst.xfer_byte(8'h80 | 7'h40, d);   // read REG_REC_DATA
        mst.xfer_byte(8'h00, d);           // turnaround
        for (i = 0; i < 4; i = i + 1) begin
            mst.xfer_byte(8'h00, d);
            `EXPECT_EQ(d, 8'h10 + i, "record byte in order");
        end
        mst.cs_hi();

        `TB_FINISH("tb_spi_protocol");
    end
endmodule

/*
 * File: tb_spi_slave.sv
 * Description: spi_slave mode-0 byte engine: bytes shifted in on MOSI appear on
 *              rx_byte with an rx_stb pulse; the first byte shifted out is 0x00
 *              and every following byte is tx_byte, MSB first; CS between frames
 *              resets the bit counter.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module tb_spi_slave;
    `include "tb_common.svh"

    logic sclk, cs_n, mosi, miso;

    logic [7:0] rx_byte, byte_idx;
    logic       rx_stb;

    // Mimic the protocol layer: byte 0 (header slot) sends 0x00, then 0xA5.
    logic [7:0] tx_byte;
    assign tx_byte = (byte_idx == 8'd0) ? 8'h00 : 8'hA5;

    integer rx_count = 0;
    logic [7:0] rx_last;

    spi_master_bfm #(.SCLK_NS(20.0)) mst (
        .sclk(sclk), .cs_n(cs_n), .mosi(mosi), .miso(miso));

    spi_slave dut (
        .spi_sclk(sclk), .spi_cs_n(cs_n), .spi_mosi(mosi), .spi_miso(miso),
        .rx_byte(rx_byte), .rx_stb(rx_stb), .byte_idx(byte_idx), .tx_byte(tx_byte));

    always @(posedge sclk) if (rx_stb) begin
        rx_count = rx_count + 1;
        rx_last  = rx_byte;
    end

    logic [7:0] q0, q1, q2;
    initial begin
        #50;
        mst.cs_lo();
        mst.xfer_byte(8'h3C, q0);   // slave sends 0x00 during this byte
        mst.xfer_byte(8'h00, q1);   // slave sends tx_byte = 0xA5
        mst.xfer_byte(8'h00, q2);   // slave sends tx_byte = 0xA5 again
        mst.cs_hi();

        `EXPECT_EQ(rx_count, 3, "three bytes received");
        `EXPECT_EQ(rx_last, 8'h00, "last rx byte value");
        `EXPECT_EQ(q0, 8'h00, "first slave byte is 0x00");
        `EXPECT_EQ(q1, 8'hA5, "second slave byte is tx_byte");
        `EXPECT_EQ(q2, 8'hA5, "third slave byte is tx_byte");

        // A fresh frame re-syncs cleanly.
        #40;
        mst.cs_lo();
        mst.xfer_byte(8'h81, q0);
        mst.cs_hi();
        `EXPECT_EQ(rx_count, 4, "frame 2 delivered one more byte");
        `EXPECT_EQ(rx_last, 8'h81, "frame 2 byte value");

        `TB_FINISH("tb_spi_slave");
    end
endmodule

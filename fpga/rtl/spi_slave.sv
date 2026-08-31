/*
 * File: spi_slave.sv
 * Description: SPI mode-0 slave byte engine. MOSI is sampled on the rising edge
 *              of spi_sclk; MISO is a combinational mux of the current tx_byte
 *              indexed by the running bit counter, stable through each low phase
 *              where the master samples it (MSB first, 8-bit words). rx_byte and
 *              rx_stb are combinational so a same-edge consumer sees the byte on
 *              its 8th rising edge rather than one edge late. spi_cs_n frames the
 *              transfer and asynchronously clears the counters between frames.
 *
 * tx_byte must be the response for the byte currently being shifted; the
 * protocol layer derives it from a frame byte index that advances on rx_stb, so
 * it is settled for byte N by the time byte N starts.
 *
 * All logic here runs on spi_sclk, which only toggles while CS is low.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module spi_slave (
    input  logic       spi_sclk,
    input  logic       spi_cs_n,
    input  logic       spi_mosi,
    output logic       spi_miso,

    // Byte stream, all in the spi_sclk domain.
    output logic [7:0] rx_byte,   // combinational: valid on the 8th rising edge
    output logic       rx_stb,    // combinational: high on the 8th rising edge
    output logic [7:0] byte_idx,  // bytes received so far (0 while header shifts in)
    output logic [2:0] bit_pos,   // bit index within the byte being shifted (0 = MSB)
    input  logic [7:0] tx_byte    // response for the byte being shifted out
);

    // Initialised so the counters are defined before the first CS edge; the
    // GW2AR registers power up to 0, so this matches hardware.
    logic [2:0] bit_cnt  = 3'd0;
    logic [7:0] rx_sh    = 8'd0;
    logic [7:0] byte_cnt = 8'd0;

    always_ff @(posedge spi_sclk or posedge spi_cs_n) begin
        if (spi_cs_n) begin
            bit_cnt  <= 3'd0;
            rx_sh    <= 8'd0;
            byte_cnt <= 8'd0;
        end else begin
            rx_sh <= {rx_sh[6:0], spi_mosi};
            if (bit_cnt == 3'd7) begin
                bit_cnt  <= 3'd0;
                byte_cnt <= byte_cnt + 8'd1;
            end else begin
                bit_cnt <= bit_cnt + 3'd1;
            end
        end
    end

    assign rx_byte  = {rx_sh[6:0], spi_mosi};
    assign rx_stb   = ~spi_cs_n & (bit_cnt == 3'd7);
    assign byte_idx = byte_cnt;
    assign bit_pos  = bit_cnt;

    // Transmit path: MSB-first mux of tx_byte by bit position.
    assign spi_miso = spi_cs_n ? 1'b0 : tx_byte[3'd7 - bit_cnt];

endmodule

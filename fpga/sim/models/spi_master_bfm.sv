/*
 * File: spi_master_bfm.sv
 * Description: Minimal SPI mode-0 master for the benches. Drive one frame as
 *              cs_lo(); repeated xfer_byte(...); cs_hi();. MOSI changes while
 *              SCLK is low and is sampled by the slave on the rising edge; MISO
 *              is sampled here just before that same rising edge, where a mode-0
 *              slave holds it stable.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`timescale 1ns/1ps

module spi_master_bfm #(
    parameter real SCLK_NS = 25.0
) (
    output logic sclk,
    output logic cs_n,
    output logic mosi,
    input  logic miso
);

    initial begin
        sclk = 1'b0;
        cs_n = 1'b1;
        mosi = 1'b0;
    end

    task automatic cs_lo;
        cs_n = 1'b0;
        #(SCLK_NS);
    endtask

    task automatic cs_hi;
        #(SCLK_NS / 2);
        cs_n = 1'b1;
        #(SCLK_NS);
    endtask

    task automatic xfer_byte(input logic [7:0] d, output logic [7:0] q);
        integer b;
        q = 8'h00;
        for (b = 7; b >= 0; b = b - 1) begin
            mosi = d[b];
            #(SCLK_NS / 2);
            q[b] = miso;          // stable while SCLK is still low
            sclk = 1'b1;
            #(SCLK_NS / 2);
            sclk = 1'b0;
        end
    endtask

endmodule

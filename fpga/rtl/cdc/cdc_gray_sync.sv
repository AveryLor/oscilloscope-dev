/*
 * File: cdc_gray_sync.sv
 * Description: Carry a free-running binary counter across a clock boundary. The
 *              source value is converted to Gray code (one bit changes per
 *              increment), synchronized, and converted back to binary in the
 *              destination domain.
 *
 * The source must change by at most one LSB per source-clock edge, which is the
 * case for the sample-buffer pointers and the encoder counts this is used for.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module cdc_gray_sync #(
    parameter int WIDTH  = 16,
    parameter int STAGES = 3
) (
    input  logic             src_clk,
    input  logic             src_rst_n,
    input  logic [WIDTH-1:0] src_bin,

    input  logic             dst_clk,
    input  logic             dst_rst_n,
    output logic [WIDTH-1:0] dst_bin
);

    function automatic logic [WIDTH-1:0] bin2gray(input logic [WIDTH-1:0] b);
        return b ^ (b >> 1);
    endfunction

    function automatic logic [WIDTH-1:0] gray2bin(input logic [WIDTH-1:0] g);
        logic [WIDTH-1:0] b;
        b[WIDTH-1] = g[WIDTH-1];
        for (int i = WIDTH-2; i >= 0; i--) begin
            b[i] = b[i+1] ^ g[i];
        end
        return b;
    endfunction

    (* syn_keep = "true" *)
    logic [WIDTH-1:0] gray_q;

    always_ff @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            gray_q <= '0;
        end else begin
            gray_q <= bin2gray(src_bin);
        end
    end

    (* syn_keep = "true", syn_preserve = "true" *)
    logic [WIDTH-1:0] sync_q [STAGES];

    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            for (int s = 0; s < STAGES; s++) begin
                sync_q[s] <= '0;
            end
        end else begin
            sync_q[0] <= gray_q;
            for (int s = 1; s < STAGES; s++) begin
                sync_q[s] <= sync_q[s-1];
            end
        end
    end

    assign dst_bin = gray2bin(sync_q[STAGES-1]);

endmodule

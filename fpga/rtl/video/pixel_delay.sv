/*
 * File: pixel_delay.sv
 * Description: Fixed N-stage shift register used to line up the video pipeline.
 *              Renderers that take a few pixel clocks (RAM reads, font lookups)
 *              emit their results at stage PIX_PIPE; the graticule and the
 *              de/hsync/vsync stream are combinational at stage 0 and get delayed
 *              here so the compositor sees one coherent pixel. No reset: a few
 *              pixels of startup garbage are off-screen and invisible.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

module pixel_delay #(
    parameter int W = 1,
    parameter int N = 3
) (
    input  logic         clk,
    input  logic [W-1:0] d,
    output logic [W-1:0] q
);

    generate
        if (N == 0) begin : g_passthru
            assign q = d;
        end else begin : g_chain
            logic [W-1:0] ch [N];
            integer i;
            always_ff @(posedge clk) begin
                ch[0] <= d;
                for (i = 1; i < N; i = i + 1) ch[i] <= ch[i-1];
            end
            assign q = ch[N-1];
        end
    endgenerate

endmodule

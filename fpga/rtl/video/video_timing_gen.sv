/*
 * File: video_timing_gen.sv
 * Description: 1280x720p60 CEA-861 video timing generator. Free-running H/V
 *              counters in the pixel-clock domain produce registered x/y pixel
 *              coordinates, data-enable, positive-going hsync/vsync, and one-cycle
 *              line_start / frame_start strobes for the rest of the pixel
 *              pipeline. See video_pkg.sv for the timing numbers.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

module video_timing_gen
    import video_pkg::*;
(
    input  logic        pix_clk,
    input  logic        rst_n,
    output logic [11:0] x,
    output logic [11:0] y,
    output logic        de,
    output logic        hsync,
    output logic        vsync,
    output logic        line_start,
    output logic        frame_start
);

    logic [11:0] hcnt, vcnt;

    wire h_last = (hcnt == H_TOTAL - 1);
    wire v_last = (vcnt == V_TOTAL - 1);

    always_ff @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            hcnt <= '0;
            vcnt <= '0;
        end else if (h_last) begin
            hcnt <= '0;
            vcnt <= v_last ? 12'd0 : vcnt + 12'd1;
        end else begin
            hcnt <= hcnt + 12'd1;
        end
    end

    // Combinational decode of the current counters, then one register stage so
    // every downstream consumer sees a clean, aligned pixel.
    logic        de_c, hs_c, vs_c, ls_c, fs_c;

    always_comb begin
        de_c = (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);
        hs_c = (hcnt >= (H_ACTIVE + H_FRONT)) &&
               (hcnt <  (H_ACTIVE + H_FRONT + H_SYNC));
        vs_c = (vcnt >= (V_ACTIVE + V_FRONT)) &&
               (vcnt <  (V_ACTIVE + V_FRONT + V_SYNC));
        ls_c = (hcnt == 12'd0);
        fs_c = (hcnt == 12'd0) && (vcnt == 12'd0);
    end

    always_ff @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            x           <= '0;
            y           <= '0;
            de          <= 1'b0;
            hsync       <= 1'b0;
            vsync       <= 1'b0;
            line_start  <= 1'b0;
            frame_start <= 1'b0;
        end else begin
            x           <= hcnt;
            y           <= vcnt;
            de          <= de_c;
            hsync       <= hs_c;
            vsync       <= vs_c;
            line_start  <= ls_c;
            frame_start <= fs_c;
        end
    end

endmodule

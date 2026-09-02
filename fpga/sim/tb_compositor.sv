/*
 * File: tb_compositor.sv
 * Description: Exhaustively drives the compositor layer inputs and checks the
 *              output RGB is the palette entry of the highest-priority active
 *              layer, background when none is active, and black whenever de is
 *              low regardless of the layers.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

`timescale 1ns/1ps

module tb_compositor;
    import video_pkg::*;
    `include "tb_common.svh"

    logic        de, text_on, trig_level_on, trig_pos_on, trace_on;
    logic        grat_on, grat_bright;
    logic [23:0] text_color;
    logic [23:0] rgb;

    compositor dut (
        .de            (de),
        .text_on       (text_on),
        .text_color    (text_color),
        .trig_level_on (trig_level_on),
        .trig_pos_on   (trig_pos_on),
        .trace_on      (trace_on),
        .grat_on       (grat_on),
        .grat_bright   (grat_bright),
        .rgb           (rgb)
    );

    logic [23:0] expect_rgb;
    integer      combo;

    function automatic logic [23:0] model();
        if (!de)                   return 24'h000000;
        else if (text_on)          return text_color;
        else if (trig_level_on)    return COL_TRIG_LEVEL;
        else if (trig_pos_on)      return COL_TRIG_POS;
        else if (trace_on)         return COL_TRACE;
        else if (grat_on)          return grat_bright ? COL_GRAT_BRIGHT : COL_GRAT;
        else                       return COL_BG;
    endfunction

    initial begin
        text_color = COL_TEXT;
        for (combo = 0; combo < 128; combo = combo + 1) begin
            {de, text_on, trig_level_on, trig_pos_on, trace_on, grat_on, grat_bright}
                = combo[6:0];
            #1;
            expect_rgb = model();
            `EXPECT_EQ(rgb, expect_rgb, $sformatf("combo %0d layer priority", combo));
        end

        // de low must win over every lit layer.
        de = 0;
        {text_on, trig_level_on, trig_pos_on, trace_on, grat_on, grat_bright} = 6'b111111;
        #1;
        `EXPECT_EQ(rgb, 24'h000000, "blanking forces black over all layers");

        `TB_FINISH("tb_compositor");
    end
endmodule

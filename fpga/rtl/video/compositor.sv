/*
 * File: compositor.sv
 * Description: Final per-pixel layer mux for the oscilloscope screen. Priority,
 *              highest first: readout text, trigger-level marker, trigger-position
 *              marker, waveform trace, graticule, background. Forces black outside
 *              the active area. All inputs must already be aligned to the same
 *              pixel-pipeline stage.
 * Author: Avery Lor
 * Date: Sep 2 2026
 */

module compositor
    import video_pkg::*;
(
    input  logic        de,
    input  logic        text_on,
    input  logic [23:0] text_color,
    input  logic        trig_level_on,
    input  logic        trig_pos_on,
    input  logic        trace_on,
    input  logic        grat_on,
    input  logic        grat_bright,
    output logic [23:0] rgb
);

    always_comb begin
        if (!de)                    rgb = 24'h000000;
        else if (text_on)           rgb = text_color;
        else if (trig_level_on)     rgb = COL_TRIG_LEVEL;
        else if (trig_pos_on)       rgb = COL_TRIG_POS;
        else if (trace_on)          rgb = COL_TRACE;
        else if (grat_on)           rgb = grat_bright ? COL_GRAT_BRIGHT : COL_GRAT;
        else                        rgb = COL_BG;
    end

endmodule

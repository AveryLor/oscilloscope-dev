/*
 * File: status_cdc.sv
 * Description: Bring the acquisition status bundle from the capture domain to the
 *              SPI register-file domain. The narrow flags are level-stable at the
 *              acquisition rest points; the wide fields (sample count, trigger
 *              offset, trigger phase, over-range count) are latched in the
 *              capture domain when the record freezes and are static afterwards.
 *              The SPI side must only trust the wide fields while the synced
 *              frozen flag is high, which it is guaranteed to be only after those
 *              fields have long since settled.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module status_cdc
    import scope_pkg::*;
#(
    parameter int STAGES = 3
) (
    // Capture domain inputs.
    input  logic [2:0]  cap_state,
    input  logic        cap_frozen,
    input  logic        cap_pll_lock,
    input  logic        cap_irq,
    input  logic        cap_trigd_auto,
    input  logic        cap_overrun,
    input  logic [31:0] cap_sample_count,
    input  logic [31:0] cap_trig_ptr,
    input  logic [15:0] cap_trig_phase,
    input  logic [15:0] cap_overrange_cnt,

    // SPI domain.
    input  logic        spi_clk,
    output scope_sta_t  spi_sta
);

    scope_sta_t src_bundle;
    always_comb begin
        src_bundle.state             = cap_state;
        src_bundle.frozen            = cap_frozen;
        src_bundle.pll_lock          = cap_pll_lock;
        src_bundle.irq               = cap_irq;
        src_bundle.triggered_by_auto = cap_trigd_auto;
        src_bundle.overrun           = cap_overrun;
        src_bundle.sample_count      = cap_sample_count;
        src_bundle.trig_ptr          = cap_trig_ptr;
        src_bundle.trig_phase        = cap_trig_phase;
        src_bundle.overrange_cnt     = cap_overrange_cnt;
    end

    logic [$bits(scope_sta_t)-1:0] src_flat, dst_flat;
    assign src_flat = src_bundle;
    assign spi_sta  = dst_flat;

    cdc_bit_sync #(
        .WIDTH  ($bits(scope_sta_t)),
        .STAGES (STAGES)
    ) u_sync (
        .clk (spi_clk),
        .d   (src_flat),
        .q   (dst_flat)
    );

endmodule

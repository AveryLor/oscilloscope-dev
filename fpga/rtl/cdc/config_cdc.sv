/*
 * File: config_cdc.sv
 * Description: Carry a wide, slowly-changing data bundle across a clock boundary
 *              using the "stable data plus one sync bit" method. The source holds
 *              src_data steady and flips src_commit on every update; the
 *              destination synchronizes the commit toggle, edge-detects it, and
 *              re-registers the (by then long-settled) data, pulsing dst_update.
 *
 * The source must register src_data at least one cycle before it flips
 * src_commit, so the data is already settled by the time the toggle crosses.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module config_cdc #(
    parameter int WIDTH  = 32,
    parameter int STAGES = 3
) (
    input  logic [WIDTH-1:0] src_data,
    input  logic             src_commit,   // toggles once per update

    input  logic             dst_clk,
    input  logic             dst_rst_n,
    output logic [WIDTH-1:0] dst_data,
    output logic             dst_update    // one pulse per update
);

    (* syn_keep = "true", syn_preserve = "true" *)
    logic [STAGES-1:0] sync_q = '0;
    logic              edge_det;

    // Defined even if dst_rst_n never sees a falling edge.
    initial dst_data   = '0;
    initial dst_update = 1'b0;

    assign edge_det = sync_q[STAGES-1] ^ sync_q[STAGES-2];

    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            sync_q     <= '0;
            dst_data   <= '0;
            dst_update <= 1'b0;
        end else begin
            sync_q     <= {sync_q[STAGES-2:0], src_commit};
            dst_update <= edge_det;
            if (edge_det) begin
                dst_data <= src_data;
            end
        end
    end

endmodule

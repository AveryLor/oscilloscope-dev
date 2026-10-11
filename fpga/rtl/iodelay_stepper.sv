/*
 * File: iodelay_stepper.sv
 * Description: Drives the dynamic-adjust ports of a bank of Gowin IODELAYs so
 *              each one's tap tracks a target value. The GW2A IODELAY cannot be
 *              loaded with an arbitrary tap at runtime: SDTAP reloads the static
 *              C_STATIC_DLY (0 here), and after that each falling edge of VALUE
 *              moves the delay one tap in the direction SETN selects. So this
 *              block reloads every lane to tap 0 out of reset, keeps its own
 *              count of where each lane sits, and steps every lane that is off
 *              target by one tap per 4-cycle round until it matches.
 *
 * The SDTAP and SETN polarities come from Gowin UG289. They are parameters
 * because they are the one thing here that cannot be checked in simulation:
 * VERIFY on the first bring-up that a larger DLY_TAP_* delays the lane (the
 * eye monitor counts shift from B to A) and flip SETN_INC if it does not.
 * Author: Avery Lor
 * Date: Oct 7 2026
 */

module iodelay_stepper #(
    parameter int   N          = 11,
    parameter int   TW         = 7,
    parameter logic SDTAP_LOAD = 1'b0,  // SDTAP level that reloads C_STATIC_DLY
    parameter logic SETN_INC   = 1'b0,  // SETN level that increases the delay
    parameter int   LOAD_CYC   = 8      // cycles to hold SDTAP in the load state
) (
    input  logic            clk,
    input  logic            rst_n,
    input  logic [N*TW-1:0] tap_tgt,
    output logic [N-1:0]    sdtap,
    output logic [N-1:0]    setn,
    output logic [N-1:0]    value,
    output logic            busy
);

    logic [TW-1:0] cur [N];
    logic [N-1:0]  step, up;
    logic [$clog2(LOAD_CYC+1)-1:0] load_cnt;
    logic [1:0]    phase;
    logic          loading;

    // Lanes off target and which way each needs to go.
    logic [N-1:0] need, need_up;
    always_comb begin
        for (int i = 0; i < N; i++) begin
            need[i]    = (cur[i] != tap_tgt[i*TW +: TW]);
            need_up[i] = (tap_tgt[i*TW +: TW] > cur[i]);
        end
    end

    // Round per tap: 0 latch lanes and set SETN, 1 raise VALUE, 2 drop VALUE
    // (the falling edge steps the delay) and update the count, 3 settle.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < N; i++) cur[i] <= '0;
            step     <= '0;
            up       <= '0;
            sdtap    <= {N{SDTAP_LOAD}};
            setn     <= {N{~SETN_INC}};
            value    <= '0;
            load_cnt <= '0;
            loading  <= 1'b1;
            phase    <= 2'd0;
            busy     <= 1'b1;
        end else if (loading) begin
            // Reload C_STATIC_DLY = 0 into every lane so cur[] starts true.
            if (load_cnt == LOAD_CYC) begin
                sdtap   <= {N{~SDTAP_LOAD}};
                loading <= 1'b0;
            end else begin
                load_cnt <= load_cnt + 1'b1;
            end
        end else begin
            phase <= phase + 2'd1;
            case (phase)
                2'd0: begin
                    step <= need;
                    up   <= need_up;
                    for (int i = 0; i < N; i++)
                        setn[i] <= need_up[i] ? SETN_INC : ~SETN_INC;
                end
                2'd1: value <= step;
                2'd2: begin
                    value <= '0;
                    for (int i = 0; i < N; i++)
                        if (step[i]) cur[i] <= up[i] ? cur[i] + 1'b1 : cur[i] - 1'b1;
                end
                2'd3: ;
            endcase
            busy <= (|need) || (|step);
            if (phase == 2'd3) step <= '0;
        end
    end

endmodule

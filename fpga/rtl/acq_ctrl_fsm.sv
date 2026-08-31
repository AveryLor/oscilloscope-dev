/*
 * File: acq_ctrl_fsm.sv
 * Description: Acquisition sequencer in the capture clock domain. Runs the
 *              IDLE -> ARMED (prefill) -> WAIT_TRIG -> POST_TRIG -> FROZEN cycle,
 *              handles NORMAL / AUTO / SINGLE modes and optional auto-rearm, and
 *              coordinates the re-arm handshake with the readout side so a host
 *              ARM issued mid-dump does not clobber the frozen record.
 *
 * The post-trigger tail and the freeze itself are owned by capture_buffer; this
 * block reacts to its frozen_w / triggered_w / valid_count outputs.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module acq_ctrl_fsm
import scope_pkg::*;
#(
    parameter int CW = SCOPE_CNT_W
) (
    input  logic          clk,
    input  logic          rst_n,

    // Config (already committed into this domain).
    input  logic [1:0]    cfg_mode,        // acq_mode_e
    input  logic [CW-1:0] cfg_pre_count,
    input  logic [31:0]   cfg_auto_timeout,
    input  logic          cfg_auto_rearm,

    // Commands (single-cycle strobes from the SPI domain).
    input  logic          arm_stb,
    input  logic          abort_stb,
    input  logic          force_trig_stb,

    // From the capture datapath.
    input  logic          trig_pulse,
    input  logic [CW-1:0] valid_count,
    input  logic          frozen_w,

    // Re-arm handshake with the readout bridge (both single-cycle strobes).
    output logic          rearm_req,
    input  logic          rearm_ack,

    // To the capture datapath.
    output logic          buf_start,       // pulse
    output logic          buf_abort,       // pulse
    output logic          run,             // level
    output logic          arm_align,       // pulse
    output logic          armed,           // level: triggers accepted
    output logic          force_trig,      // pulse to trigger_engine

    // Status.
    output logic [2:0]    state_out,       // acq_state_e
    output logic          triggered_by_auto,
    output logic          irq_toggle
);

    typedef enum logic [2:0] {
        S_IDLE,
        S_PREFILL,
        S_WAIT_TRIG,
        S_POST_TRIG,
        S_FROZEN,
        S_REARM_WAIT
    } state_e;

    state_e       state;
    logic [31:0]  tmo_cnt;
    logic         auto_forced;

    // Report a stable 3-bit acquisition state matching acq_state_e.
    always_comb begin
        unique case (state)
            S_IDLE:       state_out = 3'(ACQ_ST_IDLE);
            S_PREFILL:    state_out = 3'(ACQ_ST_PREFILL);
            S_WAIT_TRIG:  state_out = 3'(ACQ_ST_WAIT_TRIG);
            S_POST_TRIG:  state_out = 3'(ACQ_ST_POST_TRIG);
            S_FROZEN:     state_out = 3'(ACQ_ST_FROZEN);
            S_REARM_WAIT: state_out = 3'(ACQ_ST_ARMED);
            default:      state_out = 3'(ACQ_ST_IDLE);
        endcase
    end

    assign run   = (state == S_PREFILL) || (state == S_WAIT_TRIG) || (state == S_POST_TRIG);
    assign armed = (state == S_WAIT_TRIG);

    wire tmo_hit = (cfg_mode == 2'(ACQ_MODE_AUTO)) &&
                   (cfg_auto_timeout != 32'd0) &&
                   (tmo_cnt >= cfg_auto_timeout);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_IDLE;
            tmo_cnt           <= '0;
            auto_forced       <= 1'b0;
            rearm_req         <= 1'b0;
            buf_start         <= 1'b0;
            buf_abort         <= 1'b0;
            arm_align         <= 1'b0;
            force_trig        <= 1'b0;
            triggered_by_auto <= 1'b0;
            irq_toggle        <= 1'b0;
        end else begin
            // Default strobes low.
            rearm_req  <= 1'b0;
            buf_start  <= 1'b0;
            buf_abort  <= 1'b0;
            arm_align  <= 1'b0;
            force_trig <= 1'b0;

            // Abort wins from anywhere.
            if (abort_stb) begin
                state       <= S_IDLE;
                buf_abort   <= 1'b1;
                auto_forced <= 1'b0;
            end else begin
                unique case (state)
                    S_IDLE: begin
                        if (arm_stb) begin
                            state             <= S_PREFILL;
                            buf_start         <= 1'b1;
                            arm_align         <= 1'b1;
                            triggered_by_auto <= 1'b0;
                            auto_forced       <= 1'b0;
                            tmo_cnt           <= '0;
                        end
                    end

                    S_PREFILL: begin
                        if (valid_count >= cfg_pre_count) begin
                            state   <= S_WAIT_TRIG;
                            tmo_cnt <= '0;
                        end
                    end

                    S_WAIT_TRIG: begin
                        tmo_cnt <= tmo_cnt + 1'b1;
                        if (trig_pulse) begin
                            state <= S_POST_TRIG;
                            if (auto_forced) triggered_by_auto <= 1'b1;
                        end else if ((tmo_hit || force_trig_stb) && !auto_forced) begin
                            // Kick the trigger engine; the resulting trig_pulse
                            // moves us on and records the auto flag.
                            force_trig  <= 1'b1;
                            auto_forced <= tmo_hit;
                        end
                    end

                    S_POST_TRIG: begin
                        if (frozen_w) begin
                            state      <= S_FROZEN;
                            irq_toggle <= ~irq_toggle;
                        end
                    end

                    S_FROZEN: begin
                        if (arm_stb || cfg_auto_rearm) begin
                            state     <= S_REARM_WAIT;
                            rearm_req <= 1'b1;
                        end
                    end

                    S_REARM_WAIT: begin
                        if (rearm_ack) begin
                            state             <= S_PREFILL;
                            buf_start         <= 1'b1;
                            arm_align         <= 1'b1;
                            triggered_by_auto <= 1'b0;
                            auto_forced       <= 1'b0;
                            tmo_cnt           <= '0;
                        end
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule

/*
 * File: quad_decoder.sv
 * Description: One rotary-encoder channel: two-flop synchronize A/B/BTN,
 *              debounce, decode the quadrature transitions to +/-1 per detent,
 *              and accumulate a signed count clamped to [CLAMP_MIN, CLAMP_MAX].
 *              The button is debounced to a level plus a one-shot press event
 *              that latches until btn_event_clr.
 *
 * count_gray tracks count in Gray code so a reader in another clock domain can
 * take it through a plain synchronizer (count moves by at most one per detent).
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

module quad_decoder #(
    parameter int CNT_W        = 16,
    parameter int DEBOUNCE_CYC = 400,          // ~15 us at 27 MHz, per edge
    parameter int CLAMP_MIN    = -(1 << 14),
    parameter int CLAMP_MAX    = (1 << 14) - 1
) (
    input  logic               clk,
    input  logic               rst_n,

    input  logic               a_raw,
    input  logic               b_raw,
    input  logic               btn_raw,

    output logic signed [CNT_W-1:0] count,
    output logic [CNT_W-1:0]        count_gray,
    output logic                    btn_level,
    output logic                    btn_event,
    input  logic                    btn_event_clr
);

    // Synchronize the three raw inputs.
    logic [2:0] sync0, sync1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync0 <= 3'b000;
            sync1 <= 3'b000;
        end else begin
            sync0 <= {btn_raw, b_raw, a_raw};
            sync1 <= sync0;
        end
    end

    logic [2:0] dbnc;
    debounce #(
        .WIDTH      (3),
        .STABLE_CYC (DEBOUNCE_CYC)
    ) u_dbnc (
        .clk   (clk),
        .rst_n (rst_n),
        .d     (sync1),
        .q     (dbnc)
    );

    wire a_db   = dbnc[0];
    wire b_db   = dbnc[1];
    wire btn_db = dbnc[2];

    // Quadrature decode. The detent rest position is both contacts released
    // (A = B = 1, pull-ups). One count is emitted per detent, on the return to
    // the rest state, so count and count_gray move by at most one per detent.
    logic [1:0] q_prev;
    logic       step_up, step_dn;

    always_comb begin
        step_up = (q_prev == 2'b10) && (b_db && a_db); // A released last => forward
        step_dn = (q_prev == 2'b01) && (b_db && a_db); // B released last => reverse
    end

    logic signed [CNT_W-1:0] count_q;
    assign count = count_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_prev  <= 2'b00;
            count_q <= '0;
        end else begin
            q_prev <= {b_db, a_db};
            if (step_up && (count_q < CNT_W'(CLAMP_MAX))) begin
                count_q <= count_q + 1'b1;
            end else if (step_dn && (count_q > CNT_W'(CLAMP_MIN))) begin
                count_q <= count_q - 1'b1;
            end
        end
    end

    assign count_gray = count_q ^ (count_q >> 1);

    // Button: active-low input (pull-up on the pin), level = pressed.
    logic btn_prev;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_prev  <= 1'b1;
            btn_level <= 1'b0;
            btn_event <= 1'b0;
        end else begin
            btn_prev  <= btn_db;
            btn_level <= ~btn_db;
            if (btn_prev && !btn_db) begin
                btn_event <= 1'b1;           // falling edge = press
            end else if (btn_event_clr) begin
                btn_event <= 1'b0;
            end
        end
    end

endmodule

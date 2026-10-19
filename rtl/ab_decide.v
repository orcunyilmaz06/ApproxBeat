// ApproxBeat: Pan-Tompkins decision logic (peak detector, adaptive thresholds, searchback).
//
// Bit-exact to matlab/model/ab_pt_decide.m in integer mode with the baseline parameters
// (docs/algorithm.md). One sample per in_valid; the sample is processed in four phases,
// in the model's order:
//   PEAK    age counters, MWI peak detector, segment maxima of sq and |hp|
//   CLASS   startup (blanking, learning, initial levels) or classification of a peak
//   SEARCH  searchback
//   BOOK    QRS bookkeeping: RR average, last QRS, beat output
// peak_valid pulses in the cycle after CLASS, while the levels hold their values after the
// classification; beat_valid and done pulse in the cycle after BOOK. Event positions are
// age counters (samples since the event) that saturate at 2047.
`default_nettype none
`timescale 1ns / 1ps

module ab_decide (
    input  wire               clk,
    input  wire               rst_n,        // synchronous, active low
    input  wire               in_valid,     // mwi, sq, hp hold a new sample this cycle
    input  wire        [20:0] mwi,
    input  wire        [15:0] sq,
    input  wire signed [12:0] hp,
    output reg                done,         // pulse: the sample has been processed
    output reg                peak_valid,   // pulse: an MWI peak was classified on this sample
    output reg         [1:0]  peak_class,   // 0 refractory, 1 QRS, 2 noise, 3 T wave
    output reg                beat_valid,   // pulse (with done): a QRS was declared on this sample
    output reg                beat_kind,    // 0 above threshold, 1 searchback
    output reg         [10:0] beat_r_age    // samples from the beat's R peak (largest |hp|) to now
);
    // parameters of ab_params (fs = 200 Hz)
    localparam [8:0]  BLANK      = 9'd128;
    localparam [8:0]  LEARN_END  = 9'd384;    // blanking + learning samples
    localparam [5:0]  PK_TIMEOUT = 6'd40;
    localparam        REFRACTORY = 40;
    localparam        TWAVE_WIN  = 72;
    localparam [13:0] RR_ACC0    = 14'd1600;  // 8 x rr_init (200 samples)
    localparam [11:0] RR_LIM0    = 12'd331;   // 200 + 100 + 25 + 6

    localparam [2:0] S_IDLE = 3'd0, S_PEAK = 3'd1, S_CLASS = 3'd2, S_SEARCH = 3'd3, S_BOOK = 3'd4;
    reg [2:0] state;

    // the sample being processed
    reg [20:0] mwi_r;
    reg [15:0] sq_r;
    reg [11:0] ahp_r;                         // |hp| <= 2302
    reg [8:0]  idx;                           // its 0-based index, saturating at 384

    // peak detector
    reg        rising;
    reg [20:0] pk_max;
    reg [5:0]  pk_age;                        // <= 40 while rising
    reg [15:0] seg_sq;                        // largest sq since the previous peak (slope)
    reg [11:0] seg_hp;                        // largest |hp| since the previous peak
    reg [10:0] seg_hp_age;
    reg        is_pk;                         // a peak was confirmed on this sample
    reg [20:0] c_val;
    reg [5:0]  c_age;
    reg [15:0] c_slope;
    reg [10:0] c_r_age;

    // levels and startup
    reg [20:0] spk, npk, thr1;                // THR2 = thr1 >> 1
    reg [20:0] learn_max, learn_sum;

    // QRS history
    reg        have_qrs;
    reg [10:0] qrs_age;
    reg [15:0] last_slope;
    reg [13:0] rr_acc;                        // RR average with three fraction bits
    reg [11:0] rr_lim;

    // searchback candidate
    reg        sb_valid;
    reg [20:0] sb_val;
    reg [10:0] sb_age;
    reg [15:0] sb_slope;
    reg [10:0] sb_r_age;
    reg [1:0]  found;                         // 0 none, 1 threshold, 2 searchback

    // level + floor((x - level) / 2^k) for 21-bit unsigned level and x. Done in a signed
    // local so that >>> stays arithmetic; the true result fits in 21 bits.
    function [20:0] ema;
        input [20:0] level;
        input [20:0] x;
        input [1:0]  k;
        reg signed [22:0] d;
        begin
            d   = $signed({2'b00, x}) - $signed({2'b00, level});
            d   = d >>> k;
            ema = level + d[20:0];
        end
    endfunction

    function [10:0] inc11;                    // saturating age counter
        input [10:0] a;
        inc11 = (a == 11'd2047) ? a : a + 11'd1;
    endfunction

    // ---- PEAK phase ------------------------------------------------------------------
    wire [5:0]  pk_age_a     = (pk_age == 6'd63) ? pk_age : pk_age + 6'd1;
    wire [10:0] seg_hp_age_a = inc11(seg_hp_age);
    wire        up           = mwi_r > pk_max;
    wire        confirm      = rising && !up && ((mwi_r < (pk_max >> 1)) || (pk_age_a >= PK_TIMEOUT));
    wire [15:0] seg_sq_base  = confirm ? 16'd0 : seg_sq;
    wire [11:0] seg_hp_base  = confirm ? 12'd0 : seg_hp;

    // ---- CLASS phase -----------------------------------------------------------------
    wire [20:0] lmax_n   = (mwi_r > learn_max) ? mwi_r : learn_max;
    wire [20:0] lsum_n   = learn_sum + {8'd0, mwi_r[20:8]};
    wire [20:0] spk_init = {2'b00, lmax_n[20:2]} + {4'b0000, lmax_n[20:4]};
    wire [20:0] npk_init = {1'b0, lsum_n[20:1]};

    wire signed [11:0] dt   = $signed({1'b0, qrs_age}) - $signed({6'd0, c_age});
    wire        refr_ok     = !have_qrs || (dt > REFRACTORY);
    wire        twave       = have_qrs && (dt < TWAVE_WIN) && (c_slope < (last_slope >> 2));
    wire        is_qrs      = (c_val > thr1) && !twave;
    wire [21:0] clip        = {1'b0, spk} + {3'b000, spk[20:2]};      // 1.25 x SPKI
    wire [20:0] pk_in       = ({1'b0, c_val} < clip) ? c_val : clip[20:0];
    wire [20:0] spk_c       = is_qrs ? ema(spk, pk_in, 2'd3) : spk;
    wire [20:0] npk_c       = is_qrs ? npk : ema(npk, c_val, 2'd3);
    wire        take_cand   = !is_qrs && !twave && (c_val > (thr1 >> 1)) && (!sb_valid || (c_val > sb_val));

    // ---- SEARCH phase ----------------------------------------------------------------
    wire        sb_fire     = (found == 2'd0) && sb_valid && ({1'b0, qrs_age} > rr_lim);
    wire [20:0] spk_s       = ema(spk, sb_val, 2'd2);

    // ---- BOOK phase ------------------------------------------------------------------
    wire [10:0] f_age       = (found == 2'd1) ? {5'd0, c_age} : sb_age;
    wire [15:0] f_slope     = (found == 2'd1) ? c_slope : sb_slope;
    wire [10:0] f_r_age     = (found == 2'd1) ? c_r_age : sb_r_age;
    wire [10:0] rr          = qrs_age - f_age;
    wire [14:0] rr_acc_n    = {1'b0, rr_acc} + {4'd0, rr} - {4'd0, rr_acc[13:3]};
    wire [10:0] rr_avg      = rr_acc_n[13:3];
    wire [11:0] rr_lim_n    = {1'b0, rr_avg} + {2'b00, rr_avg[10:1]} + {4'd0, rr_avg[10:3]}
                            + {6'd0, rr_avg[10:5]};

    always @(posedge clk) begin
        peak_valid <= 1'b0;
        beat_valid <= 1'b0;
        done       <= 1'b0;
        if (!rst_n) begin
            state <= S_IDLE;
            mwi_r <= 0; sq_r <= 0; ahp_r <= 0; idx <= 0;
            rising <= 1'b0; pk_max <= 0; pk_age <= 0;
            seg_sq <= 0; seg_hp <= 0; seg_hp_age <= 0;
            is_pk <= 1'b0; c_val <= 0; c_age <= 0; c_slope <= 0; c_r_age <= 0;
            spk <= 0; npk <= 0; thr1 <= 0; learn_max <= 0; learn_sum <= 0;
            have_qrs <= 1'b0; qrs_age <= 0; last_slope <= 0;
            rr_acc <= RR_ACC0; rr_lim <= RR_LIM0;
            sb_valid <= 1'b0; sb_val <= 0; sb_age <= 0; sb_slope <= 0; sb_r_age <= 0;
            found <= 2'd0;
            peak_class <= 2'd0; beat_kind <= 1'b0; beat_r_age <= 0;
        end else begin
            case (state)
            S_IDLE: if (in_valid) begin
                mwi_r <= mwi;
                sq_r  <= sq;
                ahp_r <= hp[12] ? -hp[11:0] : hp[11:0];
                state <= S_PEAK;
            end

            S_PEAK: begin
                qrs_age  <= inc11(qrs_age);
                sb_age   <= inc11(sb_age);
                sb_r_age <= inc11(sb_r_age);
                is_pk    <= confirm;
                if (rising) begin
                    if (up) begin
                        pk_max <= mwi_r; pk_age <= 6'd0;
                    end else if (confirm) begin
                        c_val <= pk_max; c_age <= pk_age_a; c_slope <= seg_sq; c_r_age <= seg_hp_age_a;
                        rising <= 1'b0; pk_max <= mwi_r; pk_age <= pk_age_a;
                    end else begin
                        pk_age <= pk_age_a;
                    end
                end else if (up) begin
                    rising <= 1'b1; pk_max <= mwi_r; pk_age <= 6'd0;
                end else begin
                    pk_max <= mwi_r; pk_age <= pk_age_a;
                end
                seg_sq <= (sq_r > seg_sq_base) ? sq_r : seg_sq_base;
                if (ahp_r > seg_hp_base) begin
                    seg_hp <= ahp_r; seg_hp_age <= 11'd0;
                end else begin
                    seg_hp <= seg_hp_base; seg_hp_age <= seg_hp_age_a;
                end
                state <= S_CLASS;
            end

            S_CLASS: begin
                if (idx < BLANK) begin
                    // filters settling: nothing to do
                end else if (idx < LEARN_END) begin
                    learn_max <= lmax_n;
                    learn_sum <= lsum_n;
                    if (idx == LEARN_END - 9'd1) begin
                        spk     <= spk_init;
                        npk     <= npk_init;
                        thr1    <= ema(npk_init, spk_init, 2'd2);
                        qrs_age <= 11'd0;              // the searchback timer starts here
                    end
                end else if (is_pk) begin
                    peak_valid <= 1'b1;
                    if (!refr_ok) begin
                        peak_class <= 2'd0;
                    end else begin
                        peak_class <= is_qrs ? 2'd1 : (twave ? 2'd3 : 2'd2);
                        spk  <= spk_c;
                        npk  <= npk_c;
                        thr1 <= ema(npk_c, spk_c, 2'd2);
                        if (is_qrs) found <= 2'd1;
                        if (take_cand) begin
                            sb_valid <= 1'b1; sb_val <= c_val; sb_age <= {5'd0, c_age};
                            sb_slope <= c_slope; sb_r_age <= c_r_age;
                        end
                    end
                end
                state <= S_SEARCH;
            end

            S_SEARCH: begin
                if (idx >= LEARN_END && sb_fire) begin
                    spk   <= spk_s;
                    thr1  <= ema(npk, spk_s, 2'd2);
                    found <= 2'd2;
                end
                state <= S_BOOK;
            end

            S_BOOK: begin
                if (found != 2'd0) begin
                    if (have_qrs) begin
                        rr_acc <= rr_acc_n[13:0];
                        rr_lim <= rr_lim_n;
                    end
                    have_qrs   <= 1'b1;
                    qrs_age    <= f_age;
                    last_slope <= f_slope;
                    sb_valid   <= 1'b0;
                    beat_valid <= 1'b1;
                    beat_kind  <= (found == 2'd2);
                    beat_r_age <= f_r_age;
                end
                found <= 2'd0;
                idx   <= (idx == LEARN_END) ? idx : idx + 9'd1;
                done  <= 1'b1;
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire

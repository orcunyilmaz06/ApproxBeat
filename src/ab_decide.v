// ApproxBeat: Pan-Tompkins decision logic (peak detector, adaptive thresholds, searchback).
//
// Bit-exact to matlab/model/ab_pt_decide.m in integer mode with the baseline parameters
// (docs/algorithm.md). One sample per in_valid, processed in the model's order:
//   PEAK            age counters; a confirmed MWI peak is classified in the same cycle
//   LRN, INIT       startup: learning window, then the initial levels
//   CLIP ... NU     level update after the classification
//   TD, TU          threshold update THR1 = NPKI + (SPKI - NPKI) >>> 2
//   SEARCH, SD, SU  searchback
//   BOOK            QRS bookkeeping (RR average, last QRS, beat output), then the peak
//                   detector and the segment maxima of sq and |hp| advance
// The peak detector advances last, so until BOOK its registers still describe the
// classified peak and need no copy (D18). Every sum is computed by one shared 23-bit
// adder/subtractor, one operation per cycle (D17); comparisons keep their own
// comparators. A sample takes 4 to 13 cycles.
// peak_valid pulses once the levels hold their values after the classification;
// beat_valid and done pulse in the cycle after BOOK. Event positions are age counters
// (samples since the event) that saturate at 2047.
`default_nettype none
`timescale 1ns / 1ps

module ab_decide #(
    parameter SQ_BITS = 16                  // word length of sq; the MWI has SQ_BITS + 5 bits
) (
    input  wire               clk,
    input  wire               rst_n,        // synchronous, active low
    input  wire               in_valid,     // mwi, sq, hp hold a new sample this cycle;
    input  wire [SQ_BITS+4:0] mwi,          // they must stay stable until done (the filter
    input  wire [SQ_BITS-1:0] sq,           // outputs do: the next sample comes after done)
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
    localparam        MW         = SQ_BITS + 5;   // MWI and level word length
    localparam        SW         = SQ_BITS;       // sq and slope word length

    localparam [3:0] S_IDLE = 4'd0,  S_PEAK = 4'd1,  S_LRN = 4'd2,     S_INIT = 4'd3,
                     S_CLIP = 4'd4,  S_LD   = 4'd5,  S_LU  = 4'd6,     S_ND   = 4'd7,
                     S_NU   = 4'd8,  S_TD   = 4'd9,  S_TU  = 4'd10,    S_SEARCH = 4'd11,
                     S_SD   = 4'd12, S_SU   = 4'd13, S_BOOK = 4'd14;
    (* fsm_encoding = "binary" *) reg [3:0] state;

    // the sample being processed: read straight from the inputs, no latch (D17)
    wire [11:0] ahp = hp[12] ? -hp[11:0] : hp[11:0];   // |hp| <= 2302
    reg  [8:0]  idx;                          // its 0-based index, saturating at 384

    // peak detector
    reg          rising;
    reg [MW-1:0] pk_max;
    reg [5:0]    pk_age;                      // <= 40 while rising
    reg [SW-1:0] seg_sq;                      // largest sq since the previous peak (slope)
    reg [11:0]   seg_hp;                      // largest |hp| since the previous peak
    reg [10:0]   seg_hp_age;

    // levels and startup
    reg [MW-1:0] spk, npk, thr1;              // THR2 = thr1 >> 1
    reg [MW-1:0] learn_max, learn_sum;

    // QRS history
    reg          have_qrs;
    reg [10:0]   qrs_age;
    reg [SW-1:0] last_slope;
    reg [13:0]   rr_acc;                      // RR average with three fraction bits
    reg [11:0]   rr_lim;

    // searchback candidate
    reg          sb_valid;
    reg [MW-1:0] sb_val;
    reg [10:0]   sb_age;
    reg [SW-1:0] sb_slope;
    reg [10:0]   sb_r_age;
    reg [1:0]    found;                       // 0 none, 1 threshold, 2 searchback
    reg          in_sb;                       // the threshold update belongs to a searchback

    reg signed [MW+1:0] t;                    // result of the shared adder kept for the next step

    function [10:0] inc11;                    // saturating age counter
        input [10:0] a;
        inc11 = (a == 11'd2047) ? a : a + 11'd1;
    endfunction

    // ---- PEAK: peak detector (comparators) ---------------------------------------------
    wire [5:0]  pk_age_a     = (pk_age == 6'd63) ? pk_age : pk_age + 6'd1;
    wire [10:0] seg_hp_age_a = inc11(seg_hp_age);
    wire        up           = mwi > pk_max;
    wire        confirm      = rising && !up && ((mwi < (pk_max >> 1)) || (pk_age_a >= PK_TIMEOUT));
    wire [SW-1:0] seg_sq_base = confirm ? {SW{1'b0}} : seg_sq;
    wire [11:0] seg_hp_base  = confirm ? 12'd0 : seg_hp;

    // the confirmed peak: the peak detector's registers, which hold still until BOOK
    wire [MW-1:0] c_val   = pk_max;
    wire [5:0]    c_age   = pk_age_a;
    wire [SW-1:0] c_slope = seg_sq;
    wire [10:0]   c_r_age = seg_hp_age_a;

    // ---- PEAK: classification (comparators), on the ages after this sample's increment --
    wire [10:0] qrs_age_i = inc11(qrs_age);
    wire signed [11:0] dt   = $signed({1'b0, qrs_age_i}) - $signed({6'd0, c_age});
    wire        refr_ok     = !have_qrs || (dt > REFRACTORY);
    wire        twave       = have_qrs && (dt < TWAVE_WIN) && (c_slope < (last_slope >> 2));
    wire        is_qrs      = (c_val > thr1) && !twave;
    wire        take_cand   = !twave && (c_val > (thr1 >> 1)) && (!sb_valid || (c_val > sb_val));
    wire        classify    = (idx >= LEARN_END) && confirm;          // a peak is classified now
    wire        cand_now    = classify && refr_ok && !is_qrs && take_cand;  // new searchback candidate
    wire [MW:0] pk_in       = ({1'b0, c_val} < t[MW:0]) ? {1'b0, c_val} : t[MW:0];  // min(peak, clip)
    wire        sb_fire     = (found == 2'd0) && sb_valid && ({1'b0, qrs_age} > rr_lim);

    // ---- the shared adder/subtractor: alu_r = alu_a +/- alu_b -------------------------
    wire signed [MW+1:0] t_s2 = t >>> 2;
    wire signed [MW+1:0] t_s3 = t >>> 3;
    reg  [MW+1:0] alu_a, alu_b;
    reg           alu_sub;
    always @* begin
        alu_a = 0; alu_b = 0; alu_sub = 1'b0;
        case (state)
        S_LRN:  begin alu_a = {2'b00, learn_sum};          alu_b = {10'd0, mwi[MW-1:8]};     end
        S_INIT: begin alu_a = {4'd0, learn_max[MW-1:2]};   alu_b = {6'd0, learn_max[MW-1:4]}; end
        S_CLIP: begin alu_a = {2'b00, spk};                alu_b = {4'd0, spk[MW-1:2]};      end
        S_LD:   begin alu_a = {1'b0, pk_in};               alu_b = {2'b00, spk};  alu_sub = 1'b1; end
        S_LU:   begin alu_a = {2'b00, spk};                alu_b = t_s3;                     end
        S_ND:   begin alu_a = {2'b00, c_val};              alu_b = {2'b00, npk};  alu_sub = 1'b1; end
        S_NU:   begin alu_a = {2'b00, npk};                alu_b = t_s3;                     end
        S_TD:   begin alu_a = {2'b00, spk};                alu_b = {2'b00, npk};  alu_sub = 1'b1; end
        S_TU:   begin alu_a = {2'b00, npk};                alu_b = t_s2;                     end
        S_SD:   begin alu_a = {2'b00, sb_val};             alu_b = {2'b00, spk};  alu_sub = 1'b1; end
        S_SU:   begin alu_a = {2'b00, spk};                alu_b = t_s2;                     end
        default: ;
        endcase
    end
    // one adder with carry-in: a + (b ^ sub) + sub, written so that only one adder is built
    wire [MW+2:0] alu_sum = {alu_a, 1'b1} + {alu_b ^ {(MW+2){alu_sub}}, alu_sub};
    wire [MW+1:0] alu_r   = alu_sum[MW+2:1];

    // ---- BOOK: RR average (narrow, own adders) -----------------------------------------
    wire [10:0] f_age    = (found == 2'd1) ? {5'd0, c_age} : sb_age;
    wire [SW-1:0] f_slope = (found == 2'd1) ? c_slope : sb_slope;
    wire [10:0] f_r_age  = (found == 2'd1) ? c_r_age : sb_r_age;
    wire [10:0] rr       = qrs_age - f_age;
    wire [14:0] rr_acc_n = {1'b0, rr_acc} + {4'd0, rr} - {4'd0, rr_acc[13:3]};
    wire [10:0] rr_avg   = rr_acc_n[13:3];
    wire [11:0] rr_lim_n = {1'b0, rr_avg} + {2'b00, rr_avg[10:1]} + {4'd0, rr_avg[10:3]}
                         + {6'd0, rr_avg[10:5]};

    always @(posedge clk) begin
        peak_valid <= 1'b0;
        beat_valid <= 1'b0;
        done       <= 1'b0;
        if (!rst_n) begin
            state <= S_IDLE;
            idx <= 0;
            rising <= 1'b0; pk_max <= 0; pk_age <= 0;
            seg_sq <= 0; seg_hp <= 0; seg_hp_age <= 0;
            spk <= 0; npk <= 0; thr1 <= 0; learn_max <= 0; learn_sum <= 0;
            have_qrs <= 1'b0; qrs_age <= 0; last_slope <= 0;
            rr_acc <= RR_ACC0; rr_lim <= RR_LIM0;
            sb_valid <= 1'b0; sb_val <= 0; sb_age <= 0; sb_slope <= 0; sb_r_age <= 0;
            found <= 2'd0; in_sb <= 1'b0; t <= 0;
            peak_class <= 2'd0; beat_kind <= 1'b0; beat_r_age <= 0;
        end else begin
            case (state)
            S_IDLE: if (in_valid) state <= S_PEAK;

            // age counters, then the classification of a confirmed peak
            S_PEAK: begin
                qrs_age <= qrs_age_i;
                // one choice per register: a flat condition keeps the multiplexers single
                if (cand_now) begin
                    sb_valid <= 1'b1; sb_val <= c_val; sb_age <= {5'd0, c_age};
                    sb_slope <= c_slope; sb_r_age <= c_r_age;
                end else begin
                    sb_age <= inc11(sb_age); sb_r_age <= inc11(sb_r_age);
                end
                if (idx < BLANK) begin                          // filters settling
                    state <= S_BOOK;
                end else if (idx < LEARN_END) begin
                    state <= S_LRN;
                end else if (!confirm) begin
                    state <= S_SEARCH;
                end else if (!refr_ok) begin
                    peak_class <= 2'd0;
                    peak_valid <= 1'b1;
                    state <= S_SEARCH;
                end else if (is_qrs) begin
                    peak_class <= 2'd1;
                    found <= 2'd1;
                    state <= S_CLIP;
                end else begin
                    peak_class <= twave ? 2'd3 : 2'd2;
                    state <= S_ND;
                end
            end

            // learning window, then the initial levels
            S_LRN: begin
                if (mwi > learn_max) learn_max <= mwi;
                learn_sum <= alu_r[MW-1:0];
                state <= (idx == LEARN_END - 9'd1) ? S_INIT : S_BOOK;
            end
            S_INIT: begin
                spk     <= alu_r[MW-1:0];
                npk     <= {1'b0, learn_sum[MW-1:1]};
                qrs_age <= 11'd0;                       // the searchback timer starts here
                state   <= S_TD;
            end

            // level update after the classification
            S_CLIP: begin t <= alu_r; state <= S_LD; end                // clip = 1.25 SPKI
            S_LD:   begin t <= alu_r; state <= S_LU; end                // min(peak, clip) - SPKI
            S_LU:   begin spk <= alu_r[MW-1:0]; state <= S_TD; end
            S_ND:   begin t <= alu_r; state <= S_NU; end                // peak - NPKI
            S_NU:   begin npk <= alu_r[MW-1:0]; state <= S_TD; end

            // THR1 = NPKI + (SPKI - NPKI) >>> 2
            S_TD: begin t <= alu_r; state <= S_TU; end
            S_TU: begin
                thr1 <= alu_r[MW-1:0];
                if (idx < LEARN_END || in_sb) begin
                    state <= S_BOOK;                            // initial levels, or after searchback
                end else begin
                    peak_valid <= 1'b1;                         // after a classification
                    state <= S_SEARCH;
                end
            end

            // searchback
            S_SEARCH: begin
                if (sb_fire) begin
                    found <= 2'd2; in_sb <= 1'b1; state <= S_SD;
                end else begin
                    state <= S_BOOK;
                end
            end
            S_SD: begin t <= alu_r; state <= S_SU; end                  // candidate - SPKI
            S_SU: begin spk <= alu_r[MW-1:0]; state <= S_TD; end

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
                in_sb <= 1'b0;
                // the peak detector and the segment maxima advance last
                if (rising) begin
                    if (up) begin
                        pk_max <= mwi; pk_age <= 6'd0;
                    end else if (confirm) begin
                        rising <= 1'b0; pk_max <= mwi; pk_age <= pk_age_a;
                    end else begin
                        pk_age <= pk_age_a;
                    end
                end else if (up) begin
                    rising <= 1'b1; pk_max <= mwi; pk_age <= 6'd0;
                end else begin
                    pk_max <= mwi; pk_age <= pk_age_a;
                end
                seg_sq <= (sq > seg_sq_base) ? sq : seg_sq_base;
                if (ahp > seg_hp_base) begin
                    seg_hp <= ahp; seg_hp_age <= 11'd0;
                end else begin
                    seg_hp <= seg_hp_base; seg_hp_age <= seg_hp_age_a;
                end
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

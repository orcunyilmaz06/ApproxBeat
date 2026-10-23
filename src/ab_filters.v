// Copyright (c) 2026 orcunyilmaz06
// SPDX-License-Identifier: Apache-2.0
//
// ApproxBeat: Pan-Tompkins filter chain (low-pass, high-pass, derivative, squarer, MWI).
//
// Bit-exact to matlab/model/ab_pt_filters.m in integer mode, with SQ_SHIFT and SQ_BITS equal
// to sq_shift and sq_bits of ab_params (docs/algorithm.md, word lengths from ab_int_widths).
// Saturation always bounds sq, so the MWI, a sum of 30, needs SQ_BITS + 5 bits.
// One ADC sample per in_valid; every stage of that sample is computed in the same clock
// cycle and registered at its end.
// The *_n wires carry the incoming sample's stage values during the in_valid cycle; the
// testbench compares them with the golden vectors (docs/golden_vectors.md).
`default_nettype none

module ab_filters #(
    parameter SQ_SHIFT = 6,                // sq = (der^2 + half an LSB) >> SQ_SHIFT (D9, D10)
    parameter SQ_BITS  = 16                // sq saturates at 2^SQ_BITS - 1 (D11)
) (
    input  wire               clk,
    input  wire               rst_n,       // synchronous, active low
    input  wire               in_valid,    // in_adu holds a new sample this cycle
    input  wire        [10:0] in_adu,      // 11-bit ADC code, 1024 = 0 mV
    output wire signed [11:0] lp,          // stage outputs of the last sample
    output wire signed [12:0] hp,
    output wire [SQ_BITS-1:0] sq,
    output reg  [SQ_BITS+4:0] mwi
);
    // Delay lines, packed; slot k holds the value of sample n-1-k.
    reg        [12*11-1:0] x_line;         // x[n-1]  .. x[n-12]
    reg signed [16:0]      y1, y2;         // low-pass recursion: y[n-1], y[n-2]
    reg        [32*12-1:0] lp_line;        // lp[n-1] .. lp[n-32]
    reg signed [16:0]      hsum;           // running sum of the last 32 lp
    reg        [4*13-1:0]  hp_line;        // hp[n-1] .. hp[n-4]
    reg [30*SQ_BITS-1:0]   sq_line;        // sq[n-1] .. sq[n-30]

    // Part-selects are unsigned in Verilog, so every slot used in arithmetic gets its own
    // signed wire first; a single unsigned operand would make the whole expression unsigned.
    // Narrow operands are sign- or zero-extended to the width of each sum on purpose.
    /* verilator lint_off WIDTHEXPAND */

    // low-pass: y = 2 y[n-1] - y[n-2] + x - 2 x[n-6] + x[n-12], lp = y >>> 5
    wire signed [10:0] x      = {~in_adu[10], in_adu[9:0]};      // in_adu - 1024
    wire signed [10:0] x6     = x_line[5*11 +: 11];
    wire signed [10:0] x12    = x_line[11*11 +: 11];
    wire signed [16:0] y      = (y1 <<< 1) - y2 + x - (x6 <<< 1) + x12;
    wire signed [11:0] lp_n   = y[16:5];

    // high-pass: hp = lp[n-16] - (sum of lp[n-31..n] >>> 5)
    wire signed [11:0] lp16   = lp_line[15*12 +: 12];
    wire signed [11:0] lp32   = lp_line[31*12 +: 12];
    wire signed [16:0] hsum_n = hsum + lp_n - lp32;
    wire signed [11:0] hmean  = hsum_n[16:5];
    wire signed [12:0] hp_n   = lp16 - hmean;

    // derivative: 2 hp[n] + hp[n-1] - hp[n-3] - 2 hp[n-4] (its 1/8 is in the sq shift)
    wire signed [12:0] hp1    = hp_line[0*13 +: 13];
    wire signed [12:0] hp3    = hp_line[2*13 +: 13];
    wire signed [12:0] hp4    = hp_line[3*13 +: 13];
    wire signed [14:0] der_n  = (hp_n <<< 1) + hp1 - hp3 - (hp4 <<< 1);

    // squarer: sq = (der^2 + half) >> SQ_SHIFT, rounded to nearest, saturated at SQ_BITS
    localparam [27:0]  HALF   = (SQ_SHIFT > 0) ? 28'd1 << (SQ_SHIFT - 1) : 28'd0;
    wire signed [29:0] der2   = der_n * der_n;                   // 0 .. 13812^2 < 2^28
    wire        [27:0] sq_r   = (der2[27:0] + HALF) >> SQ_SHIFT;
    wire [SQ_BITS-1:0] sq_n   = (|(sq_r >> SQ_BITS)) ? {SQ_BITS{1'b1}} : sq_r[SQ_BITS-1:0];

    // moving-window integrator: sum of sq[n-29..n]
    wire [SQ_BITS-1:0] sq30   = sq_line[29*SQ_BITS +: SQ_BITS];
    wire [SQ_BITS+4:0] mwi_n  = mwi + sq_n - sq30;
    /* verilator lint_on WIDTHEXPAND */

    wire _unused = &{1'b0, der2[29:28]};                         // der2 < 2^28: always 0

    assign lp = lp_line[0 +: 12];
    assign hp = hp_line[0 +: 13];
    assign sq = sq_line[0 +: SQ_BITS];

    always @(posedge clk) begin
        if (!rst_n) begin
            x_line  <= 0;
            y1      <= 0;
            y2      <= 0;
            lp_line <= 0;
            hsum    <= 0;
            hp_line <= 0;
            sq_line <= 0;
            mwi     <= 0;
        end else if (in_valid) begin
            x_line  <= {x_line[11*11-1:0], x};
            y2      <= y1;
            y1      <= y;
            lp_line <= {lp_line[31*12-1:0], lp_n};
            hsum    <= hsum_n;
            hp_line <= {hp_line[3*13-1:0], hp_n};
            sq_line <= {sq_line[29*SQ_BITS-1:0], sq_n};
            mwi     <= mwi_n;
        end
    end
endmodule

`default_nettype wire

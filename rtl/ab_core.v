// ApproxBeat core: filter chain + decision logic, ADC codes in, beat events out.
//
// in_valid presents one sample; the filters register its stage values at the end of that
// cycle, and the decision logic starts on them in the next one. Present the next sample
// only after done. Bit-exact to ab_pt_int (docs/golden_vectors.md).
`default_nettype none
`timescale 1ns / 1ps

module ab_core (
    input  wire        clk,
    input  wire        rst_n,         // synchronous, active low
    input  wire        in_valid,      // in_adu holds a new sample this cycle
    input  wire [10:0] in_adu,        // 11-bit ADC code, 1024 = 0 mV
    output wire        done,          // pulse: the sample has been processed
    output wire        beat_valid,    // pulse (with done): a QRS was declared on this sample
    output wire        beat_kind,     // 0 above threshold, 1 searchback
    output wire [10:0] beat_r_age,    // samples back to the R peak; the ADC R peak is 21 more
    output wire        peak_valid,    // pulse: an MWI peak was classified on this sample
    output wire [1:0]  peak_class     // 0 refractory, 1 QRS, 2 noise, 3 T wave
);
    wire signed [11:0] lp;
    wire signed [12:0] hp;
    wire        [15:0] sq;
    wire        [20:0] mwi;
    reg                filt_valid;    // filter outputs of the last in_valid are ready

    always @(posedge clk) filt_valid <= rst_n & in_valid;

    ab_filters u_filters (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_adu(in_adu),
        .lp(lp), .hp(hp), .sq(sq), .mwi(mwi)
    );

    ab_decide u_decide (
        .clk(clk), .rst_n(rst_n), .in_valid(filt_valid), .mwi(mwi), .sq(sq), .hp(hp),
        .done(done), .peak_valid(peak_valid), .peak_class(peak_class),
        .beat_valid(beat_valid), .beat_kind(beat_kind), .beat_r_age(beat_r_age)
    );
endmodule

`default_nettype wire

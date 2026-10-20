// Copyright (c) 2026 orcunyilmaz06
// SPDX-License-Identifier: Apache-2.0
//
// ApproxBeat on Tiny Tapeout: the Pan-Tompkins QRS detector (ab_core) behind a four-phase
// handshake, so that a host at any speed can feed it one ADC sample at a time.
//
//   host: put the sample on ui[7:0] and uio[2:0], then raise REQ (uio[3])
//   chip: processes it (4 to 13 clock cycles after REQ is synchronized), latches the
//         results and raises ACK (uio[7])
//   host: reads BEAT, KIND (uio[6:5]) and the paged byte on uo[7:0], then drops REQ
//   chip: drops ACK; the next sample may follow
//
// The sample must stay stable from REQ until ACK. The results hold until the next ACK.
// uo[7:0], selected by PAGE (uio[4]):
//   PAGE 0  R-peak age bits 7..0 (samples from the beat's R peak in the band-pass signal
//           to this sample; 0 when BEAT is 0)
//   PAGE 1  {2'b00, peak class[1:0], PEAK, R-peak age bits 10..8}; PEAK: an MWI peak was
//           classified on this sample, class 0 refractory, 1 QRS, 2 noise, 3 T wave
// Pin list and protocol: docs/info.md.
`default_nettype none
`timescale 1ns / 1ps

module tt_um_orcunyilmaz06_approxbeat (
    input  wire [7:0] ui_in,    // ADC sample bits 7..0 (11-bit code, 1024 = 0 mV)
    output wire [7:0] uo_out,   // paged result byte
    input  wire [7:0] uio_in,   // [2:0] ADC sample bits 10..8, [3] REQ, [4] PAGE
    output wire [7:0] uio_out,  // [5] KIND, [6] BEAT, [7] ACK
    output wire [7:0] uio_oe,   // uio[7:5] outputs, uio[4:0] inputs
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,
    input  wire       rst_n     // active low, synchronous: hold it for a few clocks
);
    wire [10:0] adu  = {uio_in[2:0], ui_in};
    wire        page = uio_in[4];

    // REQ comes from the host's clock domain: two flip-flops before it is used
    reg  [1:0] req_sync;
    wire       req = req_sync[1];

    localparam [1:0] H_IDLE = 2'd0, H_BUSY = 2'd1, H_ACK = 2'd2;
    reg [1:0]  hs;
    reg        start;            // in_valid of ab_core: one cycle per sample
    reg        ack;

    // results of the last sample
    reg        r_beat, r_kind, r_peak;
    reg [1:0]  r_class;
    reg [10:0] r_age;

    wire        done, beat_valid, beat_kind, peak_valid;
    wire [1:0]  peak_class;
    wire [10:0] beat_r_age;

    ab_core u_core (
        .clk(clk), .rst_n(rst_n), .in_valid(start), .in_adu(adu),
        .done(done), .beat_valid(beat_valid), .beat_kind(beat_kind), .beat_r_age(beat_r_age),
        .peak_valid(peak_valid), .peak_class(peak_class)
    );

    always @(posedge clk) begin
        start <= 1'b0;
        if (!rst_n) begin
            req_sync <= 2'b00;
            hs <= H_IDLE;
            ack <= 1'b0;
            r_beat <= 1'b0; r_kind <= 1'b0; r_peak <= 1'b0; r_class <= 2'd0; r_age <= 11'd0;
        end else begin
            req_sync <= {req_sync[0], uio_in[3]};
            case (hs)
            H_IDLE: if (req) begin
                start   <= 1'b1;
                r_peak  <= 1'b0;
                r_class <= 2'd0;
                hs      <= H_BUSY;
            end
            H_BUSY: begin
                if (peak_valid) begin
                    r_peak  <= 1'b1;
                    r_class <= peak_class;
                end
                if (done) begin
                    r_beat <= beat_valid;
                    r_kind <= beat_valid & beat_kind;
                    r_age  <= beat_valid ? beat_r_age : 11'd0;
                    ack    <= 1'b1;
                    hs     <= H_ACK;
                end
            end
            H_ACK: if (!req) begin
                ack <= 1'b0;
                hs  <= H_IDLE;
            end
            default: hs <= H_IDLE;
            endcase
        end
    end

    assign uo_out  = page ? {2'b00, r_class, r_peak, r_age[10:8]} : r_age[7:0];
    assign uio_out = {ack, r_beat, r_kind, 5'b00000};
    assign uio_oe  = 8'b1110_0000;

    wire _unused = &{ena, uio_in[7:5], 1'b0};
endmodule

`default_nettype wire

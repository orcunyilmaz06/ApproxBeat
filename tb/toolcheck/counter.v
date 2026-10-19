// Toolchain self-test: an 8-bit counter with synchronous active-low reset.
`timescale 1ns / 1ps
module counter (
    input  wire       clk,
    input  wire       rst_n,
    output reg  [7:0] q
);
    always @(posedge clk) begin
        if (!rst_n) q <= 8'd0;
        else        q <= q + 8'd1;
    end
endmodule

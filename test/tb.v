`default_nettype none
`timescale 1ns / 1ps

// Tiny Tapeout testbench: tt_um_approxbeat with named wires for the handshake outputs.
// test.py drives ui_in and uio_in. The same file runs against the gate-level netlist
// (GL_TEST), so test.py uses the pins only.
module tb ();

  initial begin
    $dumpfile("tb.fst");
    $dumpvars(1, tb);   // the pins only: the run is long, and a full dump would be large
    #1;
  end

  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  wire ack  = uio_out[7];
  wire beat = uio_out[6];
  wire kind = uio_out[5];

  tt_um_approxbeat user_project (
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

endmodule

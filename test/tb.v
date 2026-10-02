`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  // Disabled by default: the demo test simulates many frames. Build with -DDUMP_FST to enable.
`ifdef DUMP_FST
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end
`endif

  // Wire up the inputs and outputs:
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

  // Replace tt_um_example with your module name:
  tt_um_davispe1_invaders user_project (

      // Include power ports for the Gate Level test:
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

`ifndef GL_TEST
  // Frame capture for the demo test (RTL only): set cap_en and cap_id from cocotb and the
  // next full frame is written as raw uo_out bytes (640x480) to output/frame_<cap_id>.raw.
  reg        cap_en = 1'b0;
  reg  [7:0] cap_id = 8'd0;
  reg        cap_on = 1'b0;
  integer    cap_fd;
  wire [9:0] cap_x = user_project.hvsync_gen.hpos;
  wire [9:0] cap_y = user_project.hvsync_gen.vpos;

  always @(posedge clk) begin
    if (cap_en && !cap_on && cap_x == 0 && cap_y == 0) begin
      cap_fd = $fopen($sformatf("output/frame_%0d.raw", cap_id), "wb");
      cap_on <= 1'b1;
    end
    if ((cap_on || (cap_en && cap_x == 0 && cap_y == 0)) && cap_x < 640 && cap_y < 480)
      $fwrite(cap_fd, "%c", uo_out);
    if (cap_on && cap_x == 0 && cap_y == 480) begin
      $fclose(cap_fd);
      cap_on <= 1'b0;
      cap_en <= 1'b0;
    end
  end
`endif

endmodule

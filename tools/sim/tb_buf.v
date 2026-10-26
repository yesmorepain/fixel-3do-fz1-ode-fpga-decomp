// Testbench 4 (buffers): FIFO pointers and empty/full flags, overflow, 0x01 layout. Build/run: sh tools/sim/run.sh buf (~15 s).
// Build/run: sh tools/sim/run.sh s4. Same SPI/3DO tasks and clock guesses as tb_cmd.v. Internal nets are
// read as dut.nXXX (names from build/fpga_pins.v; they change if the netlist is regenerated differently).
`timescale 1ps/1ps
module tb;
  parameter real T_OSC = 83333, T_PLL = 14184, T_IOSC = 1000000, T_SCK2 = 24000, T_GAP = 72000;
  parameter real T_G = 15e9;  // section G run time (ps); one 75 Hz period + window
  reg pin_37 = 0, pll = 0, iosc = 0;
  always #(T_OSC/2) pin_37 = !pin_37;
  always #(T_PLL/2) pll = !pll;
  always #(T_IOSC/2) iosc = !iosc;
  reg pin_15 = 0, pin_16 = 1, pin_17 = 0, pin_43 = 0;
  reg pin_3 = 1, pin_46 = 1, pin_47 = 1, pin_48 = 1;
  wire pin_2, pin_4, pin_14, pin_23, pin_25, pin_34, pin_36, pin_38, pin_42, pin_45;
  tri1 pin_6, pin_9, pin_10, pin_11, pin_12, pin_13, pin_18, pin_19, pin_44;
  reg [7:0] busv = 0; reg busen = 0;
  wire [7:0] BUS = {pin_19, pin_18, pin_13, pin_12, pin_11, pin_10, pin_9, pin_6};
  assign {pin_19, pin_18, pin_13, pin_12, pin_11, pin_10, pin_9, pin_6} = busen ? busv : 8'bz;
  chip dut(.pin_37(pin_37), .sim_pll_clk(pll), .sim_osc_clk(iosc),
    .pin_2(pin_2), .pin_3(pin_3), .pin_4(pin_4), .pin_6(pin_6), .pin_9(pin_9), .pin_10(pin_10),
    .pin_11(pin_11), .pin_12(pin_12), .pin_13(pin_13), .pin_14(pin_14), .pin_15(pin_15), .pin_16(pin_16),
    .pin_17(pin_17), .pin_18(pin_18), .pin_19(pin_19), .pin_23(pin_23), .pin_25(pin_25), .pin_34(pin_34),
    .pin_36(pin_36), .pin_38(pin_38), .pin_42(pin_42), .pin_43(pin_43), .pin_44(pin_44), .pin_45(pin_45),
    .pin_46(pin_46), .pin_47(pin_47), .pin_48(pin_48));

  // internal nets (see docs/design.md): opcode register, port flags, control register
  wire [7:0] opc = {dut.n582, dut.n605, dut.n606, dut.n583, dut.n607, dut.n560, dut.n517, dut.n566};
  wire [3:0] ctl = {dut.n548, dut.n579, dut.n310, dut.n376};

  reg [7:0] rx;
  task xfer(input [7:0] tx); integer b; begin
    for (b = 7; b >= 0; b = b - 1) begin
      pin_17 = tx[b]; #(T_SCK2); pin_15 = 1; rx[b] = pin_14; #(T_SCK2); pin_15 = 0;
    end
    #(T_GAP);
  end endtask
  task cs_low; begin pin_16 = 0; #(T_SCK2); end endtask
  task cs_high; begin #(T_SCK2); pin_16 = 1; #(200000); end endtask
  integer k;
  task rdport(input [7:0] op, input integer n, input [8*20-1:0] tag); begin
    cs_low; xfer(op); $write("  %0s: port %02x ->", tag, op);
    for (k = 0; k < n; k = k + 1) begin xfer(8'hff); $write(" %02x", rx); end
    cs_high; $write("   | p2=%b p4=%b p38/44=%b%b p42=%b ctl=%h\n", pin_2, pin_4, pin_38, pin_44, pin_42, ctl);
  end endtask
  task status(input [8*20-1:0] tag); rdport(8'h03, 2, tag); endtask
  task ctrl(input [7:0] v); begin cs_low; xfer(8'h04); xfer(v); cs_high; #(1_000_000); end endtask
  task endmark; begin cs_low; xfer(8'h00); cs_high; end endtask
  task sector(input integer n, input [7:0] base); begin
    cs_low; xfer(8'h05); for (k = 0; k < n; k = k + 1) xfer(base + k); cs_high;
  end endtask

  parameter real T_STB = 200000;
  task wr3do(input [7:0] v, input cmd); begin
    pin_3 = !cmd; busv = v; busen = 1; #(T_STB/2);
    pin_47 = 0; #(T_STB); pin_47 = 1; #(T_STB/2); busen = 0; #(T_STB);
  end endtask
  reg [7:0] rd;
  task rd3do(input cmd); begin
    pin_3 = !cmd; #(T_STB/2); pin_46 = 0; #(T_STB); rd = BUS; pin_46 = 1; #(T_STB);
  end endtask
  task cmd3do(input integer n); begin
    pin_48 = 0; #(T_STB); for (k = 0; k < n; k = k + 1) wr3do(8'h11 * (k + 1), 1);
    pin_3 = 1; pin_48 = 1; #(1_000_000);
  end endtask
  task data3do(input integer n); begin
    pin_48 = 0; #(T_STB); $write("  3DO data:");
    for (k = 0; k < n; k = k + 1) begin rd3do(0); $write(" %02x", rd); end
    pin_48 = 1; #(1_000_000); $write("\n");
  end endtask
  task stat3do(input integer n); begin
    pin_48 = 0; #(T_STB); $write("  3DO status:");
    for (k = 0; k < n; k = k + 1) begin rd3do(1); $write(" %02x", rd); end
    pin_3 = 1; pin_48 = 1; #(1_000_000); $write("\n");
  end endtask
  task reset; begin pin_43 = 1; #(10_000_000); pin_43 = 0; #(5_000_000); end endtask

  // timestamped events on the handshake pins
  always @(pin_2 or pin_4 or pin_38 or pin_44 or pin_42) if (0)
    $display("      %0t ns: p2=%b p4=%b p38=%b p44=%b p42=%b", $time/1000, pin_2, pin_4, pin_38, pin_44, pin_42);
  task mark(input [8*24-1:0] t); $display("    %0t ns: %0s", $time/1000, t); endtask

  // buffer pointers (see docs/design.md); x* = other FFs feeding the flag comparators (order unknown)
  wire [2:0] cw = {dut.n23, dut.n62, dut.n63}, cr = {dut.n91, dut.n85, dut.n90};
  wire [5:0] rw = {dut.n212, dut.n425, dut.n298, dut.n396, dut.n24, dut.n302};
  wire [5:0] rr = {dut.n173, dut.n175, dut.n131, dut.n130, dut.n138, dut.n184};
  wire [10:0] sw = {dut.n170, dut.n249, dut.n395, dut.n472, dut.n246, dut.n449, dut.n485, dut.n361, dut.n486, dut.n484, dut.n482};
  wire [10:0] sr = {dut.n199, dut.n411, dut.n412, dut.n332, dut.n337, dut.n356, dut.n324, dut.n326, dut.n347, dut.n346, dut.n311};
  wire [4:0] xc56 = {dut.n55, dut.n69, dut.n70, dut.n97, dut.n100};
  wire [4:0] xc52 = {dut.n44, dut.n83, dut.n84, dut.n95, dut.n113};
  wire [7:0] xr358 = {dut.n145, dut.n203, dut.n204, dut.n205, dut.n210, dut.n291, dut.n294, dut.n355};
  wire [7:0] xr50 = {dut.n132, dut.n139, dut.n146, dut.n192, dut.n195, dut.n201, dut.n208, dut.n279};
  wire [12:0] xs456 = {dut.n129, dut.n174, dut.n260, dut.n308, dut.n377, dut.n381, dut.n386, dut.n405, dut.n422,
    dut.n450, dut.n464, dut.n473, dut.n475};
  wire [12:0] xs275 = {dut.n200, dut.n266, dut.n276, dut.n278, dut.n285, dut.n286, dut.n288, dut.n289, dut.n292,
    dut.n312, dut.n352, dut.n410, dut.n413};
  task pc; $display("    C w=%0d r=%0d n56=%b n52=%b x56=%b x52=%b", cw, cr, dut.n56, dut.n52, xc56, xc52); endtask
  task pr; $display("    R w=%0d r=%0d n358=%b n50=%b x358=%b x50=%b", rw, rr, dut.n358, dut.n50, xr358, xr50); endtask
  task ps; $display("    S w=%0d r=%0d n456=%b n275=%b x456=%b x275=%b", sw, sr, dut.n456, dut.n275, xs456, xs275); endtask
  integer i, op;
  initial begin
    #(30_000_000);
    $display("== C: command buffer");
    reset; pc;
    pin_48 = 0; #(T_STB); for (i = 0; i < 10; i = i + 1) begin wr3do(8'h11 * (i + 1), 1); pc; end
    pin_3 = 1; pin_48 = 1; #(1_000_000);
    cs_low; xfer(8'h01); $write("    0x01:");
    for (i = 0; i < 11; i = i + 1) begin xfer(8'hff); $write(" %02x[r%0d %b]", rx, cr, dut.n52); end
    $write("\n"); cs_high; pc;
    rdport(8'h01, 10, "re-read");
    cmd3do(3); pc; rdport(8'h01, 10, "3 bytes");
    $display("== C2: bytes stored vs. first byte (10 written)");
    for (op = 0; op < 6; op = op + 1) begin
      reset; pin_48 = 0; #(T_STB);
      wr3do(op == 0 ? 8'h00 : op == 1 ? 8'h10 : op == 2 ? 8'h80 : op == 3 ? 8'h87 : op == 4 ? 8'h93 : 8'hff, 1);
      for (i = 1; i < 10; i = i + 1) wr3do(8'h11 * i, 1);
      pin_3 = 1; pin_48 = 1; #(1_000_000); $write("  first %02x:", {dut.n49, dut.n67, dut.n126, dut.n46, dut.n47, dut.n37, dut.n38, dut.n48}); pc;
    end
    $display("== R: reply buffer");
    reset; pr;
    cs_low; xfer(8'h02); for (i = 0; i < 66; i = i + 1) begin xfer(i); if (i < 4 || i > 60) pr; end cs_high; pr;
    status("after 66"); stat3do(3); pr;
    reset; cs_low; xfer(8'h02); for (i = 0; i < 3; i = i + 1) xfer(8'h30 + i); cs_high;
    cs_low; xfer(8'h02); for (i = 0; i < 3; i = i + 1) xfer(8'h40 + i); cs_high; pr; stat3do(7); pr;
    $display("== S: sector buffer");
    reset; ps; for (i = 0; i < 6; i = i + 1) begin sector(1, i); ps; end
    reset; sector(2048, 0); ps; sector(1, 8'haa); ps; sector(1, 8'hbb); ps;
    data3do(3); ps; sector(1, 8'hcc); ps;
    $finish;
  end
endmodule

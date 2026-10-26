// Testbench 5 (command writes): 3DO command write side (byte counter, opcode register, GPIO21). Build/run: sh tools/sim/run.sh wr (~10 s).
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
  // opcode register (CDD7..0), one-hot byte counter (first-byte flag n51, then bytes 1..7), GPIO21 = n29
  wire [7:0] opr = {dut.n49, dut.n67, dut.n38, dut.n37, dut.n126, dut.n46, dut.n47, dut.n48};
  wire [7:0] cnt = {dut.n127, dut.n120, dut.n125, dut.n119, dut.n121, dut.n123, dut.n122, dut.n51};
  task pw; $display("    W opr=%02x cnt=%b n29=%b p42=%b cw=%0d cr=%0d n52=%b", opr, cnt, dut.n29, pin_42, cw, cr, dut.n52); endtask
  always @(pin_42) $display("      %0t ns: p42 -> %b (cnt=%b)", $time/1000, pin_42, cnt);
  task burst(input integer n, input [7:0] first); begin
    pin_48 = 0; #(T_STB); wr3do(first, 1);
    for (k = 1; k < n; k = k + 1) wr3do(8'h11 * k, 1);
    pin_3 = 1; pin_48 = 1; #(1_000_000);
  end endtask
  integer i, op; real t0;
  initial begin
    #(30_000_000);
    $display("== 0: after configuration, before any pin 43 pulse (all FFs start at 0)");
    $display("    p4=%b p44=%b p38=%b p42=%b n50=%b n275=%b", pin_4, pin_44, pin_38, pin_42, dut.n50, dut.n275); pw;
    status("0x03"); burst(7, 8'h10); pw; rdport(8'h01, 10, "0x01"); stat3do(2);
    $display("== A: 3 + 3 bytes (CDEN- high between), no 0x01 read, then 1 more");
    reset; pw; burst(3, 8'h10); pw; burst(3, 8'haa); pw; burst(1, 8'hbb); pw;
    rdport(8'h01, 10, "0x01"); pw;
    $display("== B: 3-byte command read early by 0x01, then 7-byte command");
    reset; burst(3, 8'h10); pw; rdport(8'h01, 10, "0x01 (3)"); pw;
    burst(7, 8'h10); pw; rdport(8'h01, 10, "0x01 (7)"); pw;
    burst(7, 8'h10); pw; rdport(8'h01, 10, "0x01 (7)"); pw;
    $display("== C: opcode 0x08 (and neighbours), 3 bytes written");
    for (op = 0; op < 5; op = op + 1) begin
      reset; burst(3, op == 0 ? 8'h08 : op == 1 ? 8'h09 : op == 2 ? 8'h00 : op == 3 ? 8'h18 : 8'h88); pw;
      rdport(8'h01, 10, "0x01"); pw;
    end
    $display("== D: GPIO21 vs. CDEN- and the 0x01 packet (7 bytes, CDEN- held low over the read)");
    reset; pin_48 = 0; #(T_STB); for (i = 0; i < 7; i = i + 1) wr3do(8'h11 * (i + 1), 1); pin_3 = 1; pw;
    #(2_000_000); mark("CDEN- high"); pin_48 = 1; #(2_000_000); pw;
    cs_low; xfer(8'h01); mark("after 0x01 opcode byte"); pw;
    for (i = 0; i < 10; i = i + 1) xfer(8'hff); mark("before CS high"); pw; cs_high; pw;
    $display("== E: 0x03 status read and 0x00 marker do not clear GPIO21; CDCMD- high writes ignored");
    reset; burst(7, 8'h10); status("0x03"); endmark; pw;
    pin_48 = 0; #(T_STB); wr3do(8'h55, 0); pin_48 = 1; #(1_000_000); pw;
    $display("== F: 7-byte ABORT (08 + 6), 0x01 read, next 7-byte command without / with a pin 43 (GPIO22) pulse");
    reset; burst(7, 8'h08); pw; rdport(8'h01, 10, "0x01 abort"); pw;
    burst(7, 8'h10); pw; rdport(8'h01, 10, "0x01 next"); pw;
    reset; burst(7, 8'h08); rdport(8'h01, 10, "0x01 abort"); pin_43 = 1; #(10_000_000); pin_43 = 0; #(1_000_000); pw;
    burst(7, 8'h10); pw; rdport(8'h01, 10, "0x01 next"); pw;
    $display("== H: PLL cycles from the first write strobe (n40) to n52 = 0");
    reset; pin_48 = 0; #(T_STB); fork wr3do(8'h10, 1); begin @(posedge dut.n40); t0 = $realtime; @(negedge dut.n52);
      $display("    n52 falls %0.1f PLL cycles after n40", ($realtime - t0) / T_PLL); end join
    pin_3 = 1; pin_48 = 1; #(1_000_000);
    $display("== R: one 3DO status read per PLL cycle (reply 5a a5 queued); then CDHRD- low with CDEN- high");
    reset; cs_low; xfer(8'h02); xfer(8'h5a); xfer(8'ha5); cs_high; #(1_000_000);
    pin_48 = 0; pin_3 = 0; #(T_STB/2); t0 = $realtime;
    fork begin pin_46 = 0; #(T_STB); pin_46 = 1; #(T_STB); end
      repeat (40) begin @(posedge pll); $display("    +%0.0f ns hrd=%b n254=%b n253=%b n255=%b oe=%b rr=%0d n50=%b bus=%h p4=%b",
        ($realtime - t0) / 1000, pin_46, dut.n254, dut.n253, dut.n255, dut.n82, rr, dut.n50, BUS, pin_4); end join
    pin_48 = 1; #(T_STB); pin_46 = 0; #(T_STB); $display("    CDEN- high, CDHRD- low: oe=%b bus=%h rr=%0d", dut.n82, BUS, rr);
    pin_46 = 1; #(T_STB); pin_3 = 1; pin_48 = 1;
    $display("== M: ABORT glitch missed (no 0x01), then a 7-byte command, then 0x01");
    reset; burst(7, 8'h08); pw; burst(7, 8'h10); pw; rdport(8'h01, 10, "0x01"); pw;
    burst(7, 8'h20); pw; rdport(8'h01, 10, "0x01"); pw;
    $finish;
  end
endmodule

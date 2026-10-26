// Testbench 3 (control and status): SPI port decode, status bits, control byte, 0x00 end marker.
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
  always @(pin_2 or pin_4 or pin_38 or pin_44 or pin_42) if ($time > 30_000_000)
    $display("      %0t ns: p2=%b p4=%b p38=%b p44=%b p42=%b", $time/1000, pin_2, pin_4, pin_38, pin_44, pin_42);
  task mark(input [8*24-1:0] t); $display("    %0t ns: %0s", $time/1000, t); endtask

  integer op;
  integer oc = 0, t226 = 0, t223 = 0; reg tmon = 0;
  initial begin
    #(30_000_000);
    $display("== A: read-only port decode (after reset)");
    reset; status("reset");
    for (op = 0; op < 8; op = op + 1) if (op != 2 && op != 4 && op != 5) rdport(op, 3, "idle");
    rdport(8'h0b, 3, "idle"); rdport(8'h83, 3, "idle"); rdport(8'hfb, 3, "idle"); rdport(8'hff, 3, "idle");

    $display("== B: what clears c0 (each from reset)");
    reset; ctrl(0); status("ctrl 0");
    reset; cs_low; xfer(8'h02); xfer(8'h83); cs_high; #(1_000_000); status("0x02 1B");
    stat3do(2); status("3DO read reply");
    reset; sector(4, 8'h40); #(1_000_000); status("0x05 4B");
    data3do(5); status("3DO read 5");
    reset; cmd3do(7); status("3DO 7 cmd bytes");

    $display("== C: command buffer, 8 bytes and 0x00 marker");
    reset; cmd3do(8); rdport(8'h01, 10, "read cmd 8");
    cmd3do(7); rdport(8'h01, 10, "read cmd 7"); mark("end marker"); endmark; #(1_000_000);
    cmd3do(7); rdport(8'h01, 10, "read cmd 7 again");

    $display("== D: sector write timing, 0x00 marker");
    reset; mark("0x05 16B start"); sector(16, 8'h60); mark("0x05 done"); #(3_000_000); status("no 00");
    mark("end marker"); endmark; #(3_000_000); status("after 00");
    data3do(17); status("3DO read 17");
    reset; mark("0x05 16B + status"); sector(16, 8'h70); status("before 00"); mark("end marker"); endmark;
    #(3_000_000); status("after 00");
    data3do(17); status("3DO read 17");

    $display("== E: ctrl bits on the data path");
    for (op = 0; op < 4; op = op + 1) begin
      reset; ctrl(8'h01 << op); sector(8, 8'ha0 + 8 * op); endmark; #(1_000_000); status("ctrl bit");
      data3do(9); status("after read");
    end

    $display("== F: bit 5 vs. bytes written (no 3DO reads)");
    reset; sector(2047, 0); endmark; #(1_000_000); status("2047 B");
    sector(1, 0); endmark; #(1_000_000); status("2048 B");
    sector(1, 0); endmark; #(1_000_000); status("2049 B");
    data3do(2); status("3DO read 2");

    $display("== G: ctrl bit 1 timer (osc cycles)");
    reset; ctrl(2); sector(16, 8'hc0); endmark; tmon = 1; #(T_G); tmon = 0;
    status("ctrl 2, T_G later"); data3do(17); status("after read");
    $finish;
  end
  // osc-cycle counter and timer monitor for section G
  always @(posedge pin_37) oc = oc + 1;
  always @(posedge dut.n226) if (tmon) begin $display("      n226 pulse at osc %0d (+%0d)", oc, oc - t226); t226 = oc; end
  always @(pin_38 or pin_44) if (tmon) $display("      p38(GPIO20)=%b p44(CDDTEN-)=%b at osc %0d", pin_38, pin_44, oc);
  always @(dut.n223) if (tmon) begin $display("      n223=%b at osc %0d (+%0d)", dut.n223, oc, oc - t223); t223 = oc; end
endmodule

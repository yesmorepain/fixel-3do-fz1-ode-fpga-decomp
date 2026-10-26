// Testbench: drive the RP2040 SPI packet ports into the bitstream netlist and report which pins react.
// Build/run: sh tools/sim/run.sh   (+vcd writes build/sim/tb_spi.vcd)
// SPI as in the firmware: mode 0, MSB first, CS (pin16) by GPIO, SCK pin15 20.83 MHz + byte gap, SI pin17, SO pin14.
// Clocks: pin37 osc 12 MHz (board marking), PLL 70.5 MHz; guesses: internal osc 1 MHz, unknown inputs idle high, pin43 = reset pulse.
`timescale 1ps/1ps
module tb;
  parameter real T_OSC = 83333, T_PLL = 14184, T_IOSC = 1000000, T_SCK2 = 24000, T_GAP = 72000;
  // RP2040 at 125 MHz sys clock: "30 MHz" = 20.83 MHz (T_SCK2 = 24000); PL022 mode 0 idles SCK ~1.5 periods
  // between bytes (T_GAP ~ 72000). Override with: iverilog -P tb.T_SCK2=24000 -P tb.T_GAP=72000
  parameter IN_IDLE = 1'b1;

  reg pin_37 = 0, pll = 0, iosc = 0;
  always #(T_OSC/2) pin_37 = !pin_37;
  always #(T_PLL/2) pll = !pll;
  always #(T_IOSC/2) iosc = !iosc;

  reg pin_15 = 0, pin_16 = 1, pin_17 = 0, pin_43 = 0;
  reg pin_3 = IN_IDLE, pin_46 = IN_IDLE, pin_47 = IN_IDLE, pin_48 = IN_IDLE;
  wire pin_2, pin_4, pin_14, pin_23, pin_25, pin_34, pin_36, pin_38, pin_42, pin_45;
  tri1 pin_6, pin_9, pin_10, pin_11, pin_12, pin_13, pin_18, pin_19, pin_44;

  chip dut(.pin_37(pin_37), .sim_pll_clk(pll), .sim_osc_clk(iosc),
    .pin_2(pin_2), .pin_3(pin_3), .pin_4(pin_4), .pin_6(pin_6), .pin_9(pin_9), .pin_10(pin_10),
    .pin_11(pin_11), .pin_12(pin_12), .pin_13(pin_13), .pin_14(pin_14), .pin_15(pin_15), .pin_16(pin_16),
    .pin_17(pin_17), .pin_18(pin_18), .pin_19(pin_19), .pin_23(pin_23), .pin_25(pin_25), .pin_34(pin_34),
    .pin_36(pin_36), .pin_38(pin_38), .pin_42(pin_42), .pin_43(pin_43), .pin_44(pin_44), .pin_45(pin_45),
    .pin_46(pin_46), .pin_47(pin_47), .pin_48(pin_48));

  // pins watched (SPI inputs excluded); bit i = WATCH[i]
  localparam N = 22;
  integer pinno [0:N-1];
  wire [N-1:0] P = {pin_48, pin_47, pin_46, pin_45, pin_44, pin_43, pin_42, pin_38, pin_36, pin_34, pin_25,
                    pin_23, pin_19, pin_18, pin_14, pin_13, pin_12, pin_11, pin_10, pin_9, pin_6, pin_4};
  initial begin
    pinno[0]=4; pinno[1]=6; pinno[2]=9; pinno[3]=10; pinno[4]=11; pinno[5]=12; pinno[6]=13; pinno[7]=14;
    pinno[8]=18; pinno[9]=19; pinno[10]=23; pinno[11]=25; pinno[12]=34; pinno[13]=36; pinno[14]=38;
    pinno[15]=42; pinno[16]=43; pinno[17]=44; pinno[18]=45; pinno[19]=46; pinno[20]=47; pinno[21]=48;
  end
  wire pin2_w = pin_2;  // pin 2 tracked separately to keep the vector short
  integer cnt [0:N]; reg [N-1:0] Pq; reg p2q; integer i;
  task clear; begin for (i = 0; i <= N; i = i + 1) cnt[i] = 0; Pq = P; p2q = pin_2; end endtask
  always @(P) begin
    for (i = 0; i < N; i = i + 1) if (P[i] !== Pq[i]) cnt[i] = cnt[i] + 1;
    Pq = P;
  end
  always @(pin_2) begin if (pin_2 !== p2q) cnt[N] = cnt[N] + 1; p2q = pin_2; end
  // event log for pins other than the SPI ones and the SCK copies (14, 23, 36), after power-up
  reg [N-1:0] Pl; reg p2l; integer j;
  always @(P or pin_2) if ($time > 30_000_000) begin
    if (pin_2 !== p2l) $display("      %0t ns: p2 -> %b", $time/1000, pin_2);
    for (j = 0; j < N; j = j + 1)
      if (P[j] !== Pl[j] && pinno[j] != 14 && pinno[j] != 23 && pinno[j] != 36)
        $display("      %0t ns: p%0d -> %b", $time/1000, pinno[j], P[j]);
    Pl = P; p2l = pin_2;
  end else begin Pl = P; p2l = pin_2; end

  task report(input [8*24-1:0] name); begin
    $write("[%0t ns] %0s: toggles", $time/1000, name);
    if (cnt[N]) $write(" p2=%0d", cnt[N]);
    for (i = 0; i < N; i = i + 1) if (cnt[i]) $write(" p%0d=%0d", pinno[i], cnt[i]);
    $write("\n    levels p2=%b", pin_2);
    for (i = 0; i < N; i = i + 1) $write(" p%0d=%b", pinno[i], P[i]);
    $write("\n");
  end endtask

  // SPI master, mode 0: SI changes on falling SCK, both sides sample on rising SCK
  reg [7:0] rx;
  task xfer(input [7:0] tx); integer b; begin
    for (b = 7; b >= 0; b = b - 1) begin
      pin_17 = tx[b]; #(T_SCK2);
      pin_15 = 1; rx[b] = pin_14; #(T_SCK2);
      pin_15 = 0;
    end
    #(T_GAP);
  end endtask
  task cs_low; begin pin_16 = 0; #(T_SCK2); end endtask
  task cs_high; begin #(T_SCK2); pin_16 = 1; #(200000); end endtask
  task show_rx; begin $write(" %02x", rx); end endtask

  integer k;
  task status; begin
    cs_low; xfer(8'h03); $write("    0x03 rx:"); for (k = 0; k < 3; k = k + 1) begin xfer(8'hff); show_rx; end
    $write("\n"); cs_high;
  end endtask

  initial begin
    if ($test$plusargs("vcd")) begin $dumpfile("build/sim/tb_spi.vcd"); $dumpvars(0, tb); end
    clear; #(30_000_000); report("power-up 30us");
    clear; pin_43 = 1; #(10_000_000); pin_43 = 0; #(5_000_000); report("pin43 pulse 10us");

    clear; status; report("0x03 status");

    clear; cs_low; xfer(8'h01); $write("    0x01 rx:");
    for (k = 0; k < 10; k = k + 1) begin xfer(8'hff); show_rx; end
    $write("\n"); cs_high; cs_low; xfer(8'h00); cs_high; #(2_000_000); report("0x01 read cmd + 0x00");

    clear; cs_low; xfer(8'h04); xfer(8'h02); cs_high; #(2_000_000); report("0x04 ctrl=2");
    clear; cs_low; xfer(8'h04); xfer(8'h01); cs_high; #(2_000_000); report("0x04 ctrl=1");
    clear; cs_low; xfer(8'h04); xfer(8'h00); cs_high; #(2_000_000); report("0x04 ctrl=0");

    clear; cs_low; xfer(8'h02); xfer(8'h10); xfer(8'h55); xfer(8'haa); xfer(8'h28); cs_high;
    #(2_000_000); report("0x02 reply 4B");

    clear; cs_low; xfer(8'h05); for (k = 0; k < 16; k = k + 1) xfer(k); cs_high;
    cs_low; xfer(8'h00); cs_high; #(2_000_000); report("0x05 16B + 0x00");
    clear; status; report("0x03 status");

    clear; cs_low; xfer(8'h05); for (k = 0; k < 2048; k = k + 1) xfer(k ^ (k >> 8)); cs_high;
    status; cs_low; xfer(8'h00); cs_high; #(5_000_000); report("0x05 2048B + 0x00");
    clear; status; #(50_000_000); report("0x03 status, idle 50us");
    $finish;
  end
endmodule

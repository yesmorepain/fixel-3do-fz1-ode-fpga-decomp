// Randomised stimulus for the co-simulation (tools/sim/cosim.sh rnd): netlist vs. clean HDL.
// Three independent processes: RP2040 SPI packets (all opcodes, random lengths, timing and data), 3DO bus
// traffic (command writes, reply/sector reads, reads with CDEN- high, CDCMD- changes) and rare GPIO22 pulses.
// The oscillator is sped up (T_OSC) so the 75 Hz window comes round often. Options: vvp +seed=N; -P tb.T_RUN=ps.
`timescale 1ps/1ps
module tb;
  integer SEED = 1;   // +seed=N on the vvp command line
  integer seedarg;
  function integer getseed(input integer dummy); begin
    if ($value$plusargs("seed=%d", seedarg)) getseed = seedarg; else getseed = 1; end endfunction
  parameter real T_RUN = 4e9, T_OSC = 1000, T_PLL = 14184, T_IOSC = 1000000;
  reg pin_37 = 0, pll = 0, iosc = 0;
  always #(T_OSC/2) pin_37 = !pin_37;
  always #(T_PLL/2) pll = !pll;
  always #(T_IOSC/2) iosc = !iosc;
  reg pin_15 = 0, pin_16 = 1, pin_17 = 0, pin_43 = 0;
  reg pin_3 = 1, pin_46 = 1, pin_47 = 1, pin_48 = 1;
  wire pin_2, pin_4, pin_14, pin_23, pin_25, pin_34, pin_36, pin_38, pin_42, pin_45;
  tri1 pin_6, pin_9, pin_10, pin_11, pin_12, pin_13, pin_18, pin_19, pin_44;
  reg [7:0] busv = 0; reg busen = 0;
  assign {pin_19, pin_18, pin_13, pin_12, pin_11, pin_10, pin_9, pin_6} = busen ? busv : 8'bz;
  chip dut(.pin_37(pin_37), .sim_pll_clk(pll), .sim_osc_clk(iosc),
    .pin_2(pin_2), .pin_3(pin_3), .pin_4(pin_4), .pin_6(pin_6), .pin_9(pin_9), .pin_10(pin_10),
    .pin_11(pin_11), .pin_12(pin_12), .pin_13(pin_13), .pin_14(pin_14), .pin_15(pin_15), .pin_16(pin_16),
    .pin_17(pin_17), .pin_18(pin_18), .pin_19(pin_19), .pin_23(pin_23), .pin_25(pin_25), .pin_34(pin_34),
    .pin_36(pin_36), .pin_38(pin_38), .pin_42(pin_42), .pin_43(pin_43), .pin_44(pin_44), .pin_45(pin_45),
    .pin_46(pin_46), .pin_47(pin_47), .pin_48(pin_48));

  integer seed_spi, seed_bus, seed_rst;
  function integer rs(input integer lo, input integer hi); rs = lo + {$random(seed_spi)} % (hi - lo + 1); endfunction
  function integer rb(input integer lo, input integer hi); rb = lo + {$random(seed_bus)} % (hi - lo + 1); endfunction
  function integer rr(input integer lo, input integer hi); rr = lo + {$random(seed_rst)} % (hi - lo + 1); endfunction

  // ---- RP2040 SPI ---------------------------------------------------------------------------------------
  integer n, b, i, half, gap, op, len, spi_packets = 0;
  reg [7:0] tx;
  task xfer(input [7:0] v); begin
    for (b = 7; b >= 0; b = b - 1) begin
      pin_17 = v[b]; #(half); pin_15 = 1; #(half); pin_15 = 0;
    end
    #(gap);
  end endtask
  initial begin
    SEED = getseed(0); seed_spi = SEED * 3 + 1;
    #(40_000_000);
    forever begin
      #(rs(2_000, 300_000));
      half = rs(16_000, 40_000);
      gap = rs(20_000, 150_000);
      case (rs(0, 9))
        0, 1: op = 8'h01;
        2, 3: op = 8'h02;
        4: op = 8'h03;
        5: op = 8'h04;
        6, 7: op = 8'h05;
        8: op = 8'h00;
        default: op = rs(0, 255);
      endcase
      case (op)
        8'h01: len = 10;
        8'h02: len = rs(1, 70);
        8'h04: len = rs(1, 2);
        8'h05: len = (rs(0, 9) == 0) ? rs(1900, 2100) : rs(1, 40);
        default: len = rs(0, 4);
      endcase
      pin_16 = 0; #(rs(20_000, 60_000));
      xfer(op);
      for (i = 0; i < len; i = i + 1) xfer(rs(0, 255));
      #(rs(10_000, 40_000)); pin_16 = 1;
      spi_packets = spi_packets + 1;
    end
  end

  // ---- 3DO bus --------------------------------------------------------------------------------------------
  integer k, cnt, bus_ops = 0;
  task strobe_wr(input [7:0] v); begin
    busv = v; busen = 1; #(rb(30_000, 120_000));
    pin_47 = 0; #(rb(100_000, 400_000)); pin_47 = 1;
    #(rb(30_000, 120_000)); busen = 0;
  end endtask
  task strobe_rd; begin
    #(rb(30_000, 120_000));
    pin_46 = 0; #(rb(100_000, 400_000)); pin_46 = 1;
    #(rb(30_000, 150_000));
  end endtask
  initial begin
    seed_bus = getseed(0) * 7 + 2;
    #(40_000_000);
    forever begin
      #(rb(2_000, 200_000));
      case (rb(0, 9))
        0, 1, 2: begin   // command write burst, 1..9 bytes; first byte sometimes 0x08
          pin_3 = 0; pin_48 = 0; #(rb(20_000, 100_000));
          cnt = rb(1, 9);
          for (k = 0; k < cnt; k = k + 1)
            strobe_wr((k == 0 && rb(0, 3) == 0) ? 8'h08 : rb(0, 255));
          pin_48 = 1; pin_3 = rb(0, 1);
        end
        3, 4: begin      // status reads
          pin_3 = 0; pin_48 = 0; cnt = rb(1, 12);
          for (k = 0; k < cnt; k = k + 1) strobe_rd;
          pin_48 = 1;
        end
        5, 6: begin      // data reads
          pin_3 = 1; pin_48 = 0; cnt = rb(1, 60);
          for (k = 0; k < cnt; k = k + 1) strobe_rd;
          pin_48 = 1;
        end
        7: begin         // reads with CDEN- high (drive without pointer step)
          pin_3 = rb(0, 1); cnt = rb(1, 3);
          for (k = 0; k < cnt; k = k + 1) strobe_rd;
        end
        8: begin         // writes with CDEN- high or CDCMD- high (ignored)
          pin_3 = rb(0, 1); pin_48 = pin_3 ? rb(0, 1) : 1;
          strobe_wr(rb(0, 255)); pin_48 = 1;
        end
        default: pin_3 = rb(0, 1);
      endcase
      bus_ops = bus_ops + 1;
    end
  end

  // ---- GPIO22 pulses: one after configuration, then rare ones ---------------------------------------------
  integer resets = 0;
  initial begin
    seed_rst = getseed(0) * 11 + 3;
    #(30_000_000); pin_43 = 1; #(10_000_000); pin_43 = 0;
    forever begin
      #(rr(50_000_000, 400_000_000));
      pin_43 = 1; #(rr(20_000, 10_000_000)); pin_43 = 0;
      resets = resets + 1;
    end
  end

  initial begin
    #(T_RUN);
    $display("tb_rnd: seed %0d, %0d SPI packets, %0d bus operations, %0d resets", SEED, spi_packets, bus_ops, resets);
    $finish;
  end
endmodule

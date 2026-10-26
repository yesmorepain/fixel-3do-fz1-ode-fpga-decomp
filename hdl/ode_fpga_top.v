// FZ-1 ODE FPGA, clean equivalent HDL: top level (iCE5LP4K-SG48 pins, PLL, output enables).
//
// NOT TESTED ON HARDWARE. Reconstructed from Fixel's official bitstream (update.ode rev 1.0) and checked only in
// simulation against the decoded netlist. Nothing here has been built into a bitstream that ran on an ODE.
// Unofficial reconstruction of Fixel's design (licence "TBD"); not affiliated with or endorsed by Fixel.
//
// Pin numbers are SG48 package pins; signal names from the 3DO CD-bus documents and the RP2040 firmware.
// Pins 23 and 36 copy SCK and pins 25 and 34 are constant 1 (their use on the board is unknown).
module ode_fpga_top (
    input  wire pin_37,                       // oscillator (GBIN)
    // RP2040
    input  wire pin_15,                       // SPI SCK
    input  wire pin_16,                       // SPI SS
    input  wire pin_17,                       // SPI SI (RP2040 TX)
    output wire pin_14,                       // SPI SO (RP2040 RX)
    output wire pin_42,                       // GPIO21: command ready
    output wire pin_38,                       // GPIO20: sector FIFO empty / data not offered
    input  wire pin_43,                       // GPIO22: reset pulse
    output wire pin_23, pin_36,               // SCK copies
    output wire pin_25, pin_34,               // constant 1
    // 3DO CD bus (through the board's level shifters)
    input  wire pin_48,                       // CDEN-
    input  wire pin_47,                       // CDHWR-
    input  wire pin_46,                       // CDHRD-
    input  wire pin_3,                        // CDCMD-
    inout  wire pin_6, pin_9, pin_10, pin_11, pin_12, pin_13, pin_18, pin_19,   // CDD0-7
    output wire pin_4,                        // CDSTEN-
    output wire pin_44,                       // CDDTEN-
    output wire pin_2,                        // CDMDCHG
    output wire pin_45                        // CDWAIT- (constant 1: inference)
);
    // PLL: SIMPLE feedback, DIVR 0, DIVF 46, DIVQ 3 -> f_osc x 47 / 8 (70.5 MHz from 12 MHz)
    wire clk;
    SB_PLL40_CORE #(
        .FEEDBACK_PATH("SIMPLE"), .PLLOUT_SELECT("GENCLK"),
        .DIVR(4'b0000), .DIVF(7'b0101110), .DIVQ(3'b011), .FILTER_RANGE(3'b001)
    ) pll (
        .REFERENCECLK(pin_37), .PLLOUTGLOBAL(clk), .PLLOUTCORE(), .LOCK(),
        .RESETB(1'b1), .BYPASS(1'b0), .EXTFEEDBACK(1'b0), .DYNAMICDELAY(8'h00),
        .LATCHINPUTVALUE(1'b0), .SDI(1'b0), .SCLK(1'b0), .SDO());

    // The original clocks its output-enable power-up registers from an internal clock that IceStorm's u4k
    // database calls SMCCLK; no toolchain primitive exposes it, so the oscillator is used here. Effect (guess):
    // the same, outputs are enabled within the first clock after configuration.
    wire clk_oe = pin_37;

    wire [7:0] cdd_in = {pin_19, pin_18, pin_13, pin_12, pin_11, pin_10, pin_9, pin_6};
    wire [7:0] cdd_out;
    wire cdd_drive, oe, so, gpio21, gpio20, cdsten_n, cddten_n, cdmdchg;

    ode_fpga_core core (
        .clk_osc(pin_37), .clk(clk), .clk_oe(clk_oe), .rst(pin_43),
        .spi_sck(pin_15), .spi_ss_n(pin_16), .spi_mosi(pin_17), .spi_miso(so),
        .cmd_ready(gpio21), .data_free(gpio20),
        .cden_n(pin_48), .cdhwr_n(pin_47), .cdhrd_n(pin_46), .cdcmd_n(pin_3),
        .cdd_in(cdd_in), .cdd_out(cdd_out), .cdd_drive(cdd_drive),
        .cdsten_n(cdsten_n), .cddten_n(cddten_n), .cdmdchg(cdmdchg), .oe_ready(oe));

    wire bus_oe = oe & cdd_drive;
    assign {pin_19, pin_18, pin_13, pin_12, pin_11, pin_10, pin_9, pin_6} = bus_oe ? cdd_out : 8'bz;
    assign pin_14 = oe ? so       : 1'bz;
    assign pin_42 = oe ? gpio21   : 1'bz;
    assign pin_38 = oe ? gpio20   : 1'bz;
    assign pin_4  = oe ? cdsten_n : 1'bz;
    assign pin_44 = oe ? cddten_n : 1'bz;
    assign pin_2  = oe ? cdmdchg  : 1'bz;
    assign pin_45 = oe ? 1'b1     : 1'bz;
    assign pin_25 = oe ? 1'b1     : 1'bz;
    assign pin_34 = oe ? 1'b1     : 1'bz;
    assign pin_23 = oe ? pin_15   : 1'bz;
    assign pin_36 = oe ? pin_15   : 1'bz;
endmodule

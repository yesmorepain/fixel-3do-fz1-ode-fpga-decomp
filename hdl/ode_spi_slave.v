// FZ-1 ODE FPGA, clean equivalent HDL: SPI slave to the RP2040 (packet ports 0x01-0x06).
//
// NOT TESTED ON HARDWARE. Reconstructed from Fixel's official bitstream (update.ode rev 1.0) and checked only in
// simulation against the decoded netlist. Unofficial reconstruction of Fixel's design (licence "TBD"); not
// affiliated with or endorsed by Fixel.
//
// SPI mode 0, MSB first. The first byte of a packet (SS low) is the opcode; only bits 2-0 select a port, and an
// opcode with bits 7-2 all set (0xFC-0xFF, also the idle value) selects nothing:
//   001 command read (0x01)   010 reply write (0x02)   100 control write (0x04)
//   101 sector data write (0x05)   110 port 6 (reads 00, no other effect)   others: no port, reads status
// Every byte the RP2040 clocks in is shifted out of the transmit register, which is loaded at SS falling and
// after each byte. Byte 1 of every packet is therefore the status byte (the port flags register one cycle later).
module ode_spi_slave (
    input  wire       clk,          // PLL clock
    input  wire       rst,          // GPIO22 pulse (used synchronously here)
    input  wire       sck,
    input  wire       ss_n,
    input  wire       mosi,
    output wire       miso,
    output wire [7:0] rx_byte,      // receive shift register (a complete byte while `strobe` is high)
    output wire       strobe,       // one clk cycle per received byte (opcode included)
    output wire       ss_fall,      // SS falling edge (clk domain, combinational)
    output wire       byte_edge,    // byte done or SS falling: transmit load / command FIFO read step
    output reg        port_cmd   = 1'b0,
    output reg        port_reply = 1'b0,
    output reg        port_ctrl  = 1'b0,
    output reg        port_data  = 1'b0,
    output reg        port_6     = 1'b0,
    input  wire [7:0] cmd_byte,     // command FIFO output (H register), sent in 0x01 packets
    input  wire [7:0] status        // status byte, sent by every other port except 6
);
    // ---- SCK domain: receive shift register and bit counter -----------------------------------------------
    reg [7:0] rx = 8'h00;
    always @(posedge sck)
        if (!ss_n) rx <= {rx[6:0], mosi};
    assign rx_byte = rx;

    // one-hot bit counter on the falling edge, reset (async) at SS falling and when a byte completes
    wire      bitcnt_rst;
    reg [8:0] bitcnt = 9'd0;
    always @(negedge sck or posedge bitcnt_rst)
        if (bitcnt_rst)  bitcnt <= 9'd1;
        else if (!ss_n)  bitcnt <= {bitcnt[7:0], 1'b0};
    wire bits_done = bitcnt[8];

    // ---- clk domain: synchronisers and edge detection -----------------------------------------------------
    reg ss_s1 = 1'b0, ss_s2 = 1'b0, done_s1 = 1'b0, done_s2 = 1'b0, ss_fall_d = 1'b0;
    always @(posedge clk) begin
        ss_s1     <= ss_n;
        ss_s2     <= ss_s1;
        done_s1   <= bits_done & ~ss_n;
        done_s2   <= done_s1;
        ss_fall_d <= ss_fall;
    end
    assign ss_fall      = ss_s2 & ~ss_s1;
    wire   ss_edge      = ss_s2 ^ ss_s1;
    wire   done_rise    = done_s1 & ~done_s2;
    assign bitcnt_rst   = done_rise | ss_fall;
    assign byte_edge    = done_rise | ss_fall;
    assign strobe       = done_rise & ~ss_fall & ~ss_fall_d;
    wire   byte_in      = done_rise & ~ss_fall_d;          // as strobe, but also during an SS fall

    // ---- opcode register and port decoder -----------------------------------------------------------------
    reg       first = 1'b0;                                 // next byte is the opcode
    reg [7:0] opcode = 8'h00;
    always @(posedge clk) begin
        if (rst | ss_fall)        first <= 1'b1;
        else if (byte_in)         first <= 1'b0;
        if (rst | ss_edge)        opcode <= 8'hff;
        else if (first & byte_in) opcode <= rx;
    end
    wire no_port = &opcode[7:2];
    always @(posedge clk) begin
        port_cmd   <= ~no_port & (opcode[2:0] == 3'b001);
        port_reply <= ~no_port & (opcode[2:0] == 3'b010);
        port_ctrl  <= ~no_port & (opcode[2:0] == 3'b100);
        port_data  <= ~no_port & (opcode[2:0] == 3'b101);
        port_6     <= ~no_port & (opcode[2:0] == 3'b110);
    end

    // ---- transmit shift register (falling SCK, asynchronous parallel load) --------------------------------
    // tx_load ends on the clock edge that sets the port flags, so bit 4 of byte 1 of a 0x01 packet races between
    // status bit 4 (0) and H bit 4: on hardware the result depends on routing delays (the firmware ignores it).
    reg tx_load = 1'b0;                                     // transmit load pulse, one cycle after the edge
    always @(posedge clk)
        tx_load <= done_rise | ss_fall;
    wire [7:0] tx_byte = port_cmd ? cmd_byte : port_6 ? 8'h00 : status;
    ode_aload_shift tx (.clk_n(sck), .load(tx_load), .d(tx_byte), .q_msb(miso));
endmodule

// 8-bit left shift register clocked on the falling edge with an asynchronous, level-sensitive parallel load.
// Built the way iCEcube2 implements an async load on iCE40 (no such flip-flop exists): per bit one flip-flop
// with async set, one with async reset, and a latch that remembers which of the two holds the loaded value.
// Shifts on every falling edge, also while SS is high; a 0 enters at bit 0.
module ode_aload_shift (
    input  wire       clk_n,
    input  wire       load,
    input  wire [7:0] d,
    output wire       q_msb
);
    reg  [7:0] set_ff = 8'h00, clr_ff = 8'h00;
`ifdef ICE40_LUT_LATCH
    wire [7:0] sel;
`else
    reg  [7:0] sel;                                         // latch: transparent while load is high
`endif
    wire [7:0] q    = (sel & set_ff) | (~sel & clr_ff);
    wire [7:0] next = {q[6:0], 1'b0};
    wire [7:0] aset = {8{load}} & d;
    wire [7:0] aclr = {8{load}} & ~d;
    genvar k;
    generate for (k = 0; k < 8; k = k + 1) begin : bit_
        always @(negedge clk_n or posedge aset[k])
            if (aset[k]) set_ff[k] <= 1'b1;
            else             set_ff[k] <= next[k];
        always @(negedge clk_n or posedge aclr[k])
            if (aclr[k]) clr_ff[k] <= 1'b0;
            else         clr_ff[k] <= next[k];
`ifdef ICE40_LUT_LATCH
        // build (tools/build/build.sh): one LUT whose output feeds back into it, as in the original
        // (O = load ? d : sel, I0 = d, I1 = sel, I2 = load); the iCE40 fabric has no latch cell
        SB_LUT4 #(.LUT_INIT(16'h00ac)) sel_lut (.O(sel[k]), .I0(d[k]), .I1(sel[k]), .I2(load), .I3(1'b0));
`else
        always @*
            if (load) sel[k] = d[k];
`endif
    end endgenerate
    assign q_msb = q[7];
endmodule

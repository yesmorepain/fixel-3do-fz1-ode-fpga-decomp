// FZ-1 ODE FPGA, clean equivalent HDL: 3DO CD-bus side (command writes from the 3DO, status/data reads).
//
// NOT TESTED ON HARDWARE. Reconstructed from Fixel's official bitstream (update.ode rev 1.0) and checked only in
// simulation against the decoded netlist. Unofficial reconstruction of Fixel's design (licence "TBD"); not
// affiliated with or endorsed by Fixel.

// Command bytes written by the 3DO (CDHWR- falling with CDEN- and CDCMD- low).
// A one-hot counter counts accepted bytes; cmd_ready (GPIO21) rises after the 7th byte, or after the 1st byte when
// that byte is 0x08 (ABORT). While cmd_ready is high, further write strobes are ignored. The counter restarts on
// GPIO22, or once cmd_ready is high and the command FIFO is empty (it has been read by an SPI 0x01 packet).
// CDEN- low is all that qualifies a strobe: bursts are not delimited by CDEN- going high.
module ode_cmd_in (
    input  wire clk,
    input  wire rst,              // GPIO22 pulse
    input  wire cdhwr_n,
    input  wire cden_n,
    input  wire cdcmd_n,
    input  wire [7:0] cdd,
    input  wire fifo_empty,       // command FIFO empty (read side)
    output wire wr_clk,           // accepted write strobe: the command FIFO's write clock
    output wire cmd_ready
);
    reg hwr_s1 = 1'b0, hwr_s2 = 1'b0;
    always @(posedge clk) begin
        hwr_s1 <= cdhwr_n;
        hwr_s2 <= hwr_s1;
    end
    // falling edge of CDHWR-; CDEN- and CDCMD- are sampled directly (not synchronised)
    wire wr_strobe = hwr_s2 & ~hwr_s1 & ~cdcmd_n & ~cden_n;

    reg [7:0] count  = 8'h00;     // one-hot: bit n = n bytes accepted; all zero until the first GPIO22 pulse
    reg [7:0] opcode = 8'h00;     // first byte of the command; only the 0x08 test uses it
    assign cmd_ready = count[7] | (count[1] & (opcode == 8'h08));
    assign wr_clk    = wr_strobe & ~cmd_ready;
    wire   restart   = rst | (cmd_ready & fifo_empty);

    always @(posedge clk)
        if (restart)     count <= 8'h01;
        else if (wr_clk) count <= {count[6:0], 1'b0};

    always @(posedge wr_strobe or posedge rst)
        if (rst)           opcode <= 8'h00;
        else if (count[0]) opcode <= cdd;
endmodule

// Reads by the 3DO (CDHRD- falling with CDEN- low): CDCMD- low reads the reply FIFO, high the sector FIFO.
// The data bus is driven from CDHRD- falling to CDHRD- rising (synchronised), whatever CDEN- is.
module ode_cd_read (
    input  wire       clk,
    input  wire       cdhrd_n,
    input  wire       cden_n,
    input  wire       cdcmd_n,
    output wire       reply_rd,   // reply FIFO read strobe (combinational)
    output wire       data_rd,    // sector FIFO read strobe (registered strobe, live CDCMD-)
    input  wire [7:0] reply_q,
    input  wire [7:0] data_q,
    output reg  [7:0] cdd_out = 8'h00,
    output reg        drive = 1'b0
);
    reg hrd_s1 = 1'b0, hrd_s2 = 1'b0, rd_cen = 1'b0;
    wire hrd_fall = hrd_s2 & ~hrd_s1;
    wire hrd_rise = ~hrd_s2 & hrd_s1;
    always @(posedge clk) begin
        hrd_s1 <= cdhrd_n;
        hrd_s2 <= hrd_s1;
        rd_cen <= hrd_fall & ~cden_n;
        if (hrd_fall)      drive <= 1'b1;
        else if (hrd_rise) drive <= 1'b0;
    end
    assign reply_rd = hrd_fall & ~cdcmd_n & ~cden_n;
    assign data_rd  = rd_cen & cdcmd_n;

    // output register on the falling clock edge, from a live CDCMD- select of the two RAM outputs
    always @(negedge clk)
        cdd_out <= cdcmd_n ? data_q : reply_q;
endmodule

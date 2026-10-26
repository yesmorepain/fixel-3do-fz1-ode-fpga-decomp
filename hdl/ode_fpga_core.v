// FZ-1 ODE FPGA, clean equivalent HDL: core (everything except the PLL and the pads).
//
// NOT TESTED ON HARDWARE. Reconstructed from Fixel's official bitstream (update.ode rev 1.0) and checked only in
// simulation against the decoded netlist. Unofficial reconstruction of Fixel's design (licence "TBD"); not
// affiliated with or endorsed by Fixel.
//
// Data paths:
//   3DO command bytes  -> command FIFO (8)    -> SPI 0x01 (RP2040)       GPIO21 = command ready
//   SPI 0x02 (reply)   -> reply FIFO (64)     -> 3DO reads, CDCMD- low   CDSTEN- low while not empty
//   SPI 0x05 (sector)  -> sector FIFO (2048)  -> 3DO reads, CDCMD- high  CDDTEN- (= GPIO20) low while not empty
//   SPI 0x04 (control) -> ctrl[3:0]: bit 0 drives CDMDCHG low, bit 1 limits CDDTEN- to the 75 Hz window,
//                         bits 2-3 are only echoed in the status byte
//   status byte (SPI 0x03 or byte 1 of any packet): {sector empty, reply empty, sector full, 0, ctrl[3:0]}
// GPIO22 (rst, high pulse) clears all FIFOs, the command byte counter and the control register. It is needed
// once after configuration: until then the command byte counter does not run.
module ode_fpga_core (
    input  wire       clk_osc,      // oscillator pin (12 MHz, marked on the board)
    input  wire       clk,          // PLL output (osc x 47/8)
    input  wire       clk_oe,       // clock of the output-enable power-up registers (see ode_fpga_top)
    input  wire       rst,          // RP2040 GPIO22
    // RP2040 SPI
    input  wire       spi_sck,
    input  wire       spi_ss_n,
    input  wire       spi_mosi,
    output wire       spi_miso,
    output wire       cmd_ready,    // RP2040 GPIO21
    output wire       data_free,    // RP2040 GPIO20 (same signal as CDDTEN-)
    // 3DO CD bus
    input  wire       cden_n,
    input  wire       cdhwr_n,
    input  wire       cdhrd_n,
    input  wire       cdcmd_n,
    input  wire [7:0] cdd_in,
    output wire [7:0] cdd_out,
    output wire       cdd_drive,
    output wire       cdsten_n,
    output wire       cddten_n,
    output wire       cdmdchg,
    output reg        oe_ready = 1'b0   // all outputs are tri-stated until the first clk_oe edge
);
    always @(posedge clk_oe) oe_ready <= 1'b1;

    // ---- SPI slave --------------------------------------------------------------------------------------
    wire [7:0] rx_byte, cmd_byte, status;
    wire       strobe, ss_fall, byte_edge;
    wire       port_cmd, port_reply, port_ctrl, port_data, port_6;
    ode_spi_slave spi (
        .clk(clk), .rst(rst), .sck(spi_sck), .ss_n(spi_ss_n), .mosi(spi_mosi), .miso(spi_miso),
        .rx_byte(rx_byte), .strobe(strobe), .ss_fall(ss_fall), .byte_edge(byte_edge),
        .port_cmd(port_cmd), .port_reply(port_reply), .port_ctrl(port_ctrl), .port_data(port_data),
        .port_6(port_6), .cmd_byte(cmd_byte), .status(status));

    // control register and status snapshot (the status flags hold while a control byte is being stored)
    wire ctrl_wr = port_ctrl & strobe;
    reg [3:0] ctrl = 4'h0;
    reg sec_empty_s = 1'b0, reply_empty_s = 1'b0, sec_full_s = 1'b0;
    wire sec_empty, reply_empty, sec_full;
    always @(posedge clk or posedge rst)
        if (rst) begin
            ctrl <= 4'h0; sec_empty_s <= 1'b0; reply_empty_s <= 1'b0; sec_full_s <= 1'b0;
        end else begin
            if (ctrl_wr) ctrl <= rx_byte[3:0];
            if (!ctrl_wr) begin
                sec_empty_s   <= sec_empty;
                reply_empty_s <= reply_empty;
                sec_full_s    <= sec_full;
            end
        end
    assign status = {sec_empty_s, reply_empty_s, sec_full_s, 1'b0, ctrl};

    // ---- command FIFO: 3DO -> RP2040 --------------------------------------------------------------------
    // Both sides are reset by GPIO22 and at the end of every 0x01 packet (read or not, the FIFO is emptied).
    reg port_cmd_d = 1'b0;
    always @(posedge clk) port_cmd_d <= port_cmd;
    wire cmd_rst = rst | (port_cmd_d & ~port_cmd);
    wire cmd_rd  = port_cmd & byte_edge;
    wire cmd_wclk, cmd_full, cmd_empty;
    wire [2:0] cmd_waddr, cmd_raddr;
    wire [7:0] cmd_q;
    ode_cmd_in cmdin (
        .clk(clk), .rst(rst), .cdhwr_n(cdhwr_n), .cden_n(cden_n), .cdcmd_n(cdcmd_n), .cdd(cdd_in),
        .fifo_empty(cmd_empty), .wr_clk(cmd_wclk), .cmd_ready(cmd_ready));
    ode_fifo_ptr #(.AW(3)) cmd_ptr (
        .wclk(cmd_wclk), .wrst(cmd_rst), .winc(1'b1), .waddr(cmd_waddr), .wfull(cmd_full),
        .rclk(clk), .rrst(cmd_rst), .rinc(cmd_rd), .raddr(cmd_raddr), .rempty(cmd_empty));
    ode_ram512x8 cmd_ram (
        .wclk(cmd_wclk), .wclke(1'b1), .we(~cmd_full), .waddr({6'b0, cmd_waddr}), .wdata(cdd_in),
        .rclk(clk), .rclke(cmd_rd), .raddr({6'b0, cmd_raddr}), .rdata(cmd_q));
    // H: holds the RAM output of the previous read step, so a 0x01 packet returns status, a stale byte,
    // the 7 command bytes and 00
    reg [7:0] hold = 8'h00;
    always @(posedge clk) if (cmd_rd) hold <= cmd_q;
    assign cmd_byte = hold;

    // ---- reply FIFO: RP2040 -> 3DO status bytes ---------------------------------------------------------
    wire reply_rd, reply_full;
    wire [5:0] reply_waddr, reply_raddr;
    wire [7:0] reply_q;
    ode_fifo_ptr #(.AW(6)) reply_ptr (
        .wclk(clk), .wrst(rst), .winc(port_reply & strobe), .waddr(reply_waddr), .wfull(reply_full),
        .rclk(clk), .rrst(rst), .rinc(reply_rd), .raddr(reply_raddr), .rempty(reply_empty));
    ode_ram512x8 reply_ram (
        .wclk(clk), .wclke(port_reply & strobe), .we(~reply_full), .waddr({3'b0, reply_waddr}),
        .wdata(rx_byte), .rclk(clk), .rclke(reply_rd), .raddr({3'b0, reply_raddr}), .rdata(reply_q));

    // ---- sector FIFO: RP2040 -> 3DO data ----------------------------------------------------------------
    wire data_rd;
    wire [10:0] sec_waddr, sec_raddr;
    wire [7:0] sec_q;
    ode_fifo_ptr #(.AW(11)) sec_ptr (
        .wclk(clk), .wrst(rst), .winc(port_data & strobe), .waddr(sec_waddr), .wfull(sec_full),
        .rclk(clk), .rrst(rst), .rinc(data_rd), .raddr(sec_raddr), .rempty(sec_empty));
    ode_ram2048x8 sec_ram (
        .wclk(clk), .wclke(port_data & strobe), .we(~sec_full), .waddr(sec_waddr), .wdata(rx_byte),
        .rclk(clk), .rclke(data_rd), .raddr(sec_raddr), .rdata(sec_q));

    // ---- 3DO reads and handshake outputs ----------------------------------------------------------------
    ode_cd_read cdrd (
        .clk(clk), .cdhrd_n(cdhrd_n), .cden_n(cden_n), .cdcmd_n(cdcmd_n), .reply_rd(reply_rd),
        .data_rd(data_rd), .reply_q(reply_q), .data_q(sec_q), .cdd_out(cdd_out), .drive(cdd_drive));

    wire window;
    ode_pacer pacer (.clk_osc(clk_osc), .window(window));

    assign cdsten_n  = reply_empty | port_reply;                    // not while a 0x02 packet is in progress
    assign cddten_n  = sec_empty | port_data | (ctrl[1] & ~window); // not during 0x05; ctrl bit 1: window only
    assign data_free = cddten_n;
    assign cdmdchg   = ~ctrl[0];
endmodule

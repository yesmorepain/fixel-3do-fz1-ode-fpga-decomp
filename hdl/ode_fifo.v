// FZ-1 ODE FPGA, clean equivalent HDL: FIFO pointer logic and block-RAM wrappers.
//
// NOT TESTED ON HARDWARE. Reconstructed from Fixel's official bitstream (update.ode rev 1.0) and checked only in
// simulation against the decoded netlist. Unofficial reconstruction of Fixel's design (licence "TBD"); not
// affiliated with or endorsed by Fixel.
//
// All three buffers (command 8 bytes, reply 64, sector 2048) use the same dual-clock FIFO pointer scheme
// (binary + Gray pointers with one wrap bit, two-flop synchronisers, registered full and empty flags), even where
// both sides run on the same clock. A write or read when full or empty is ignored (the pointer does not move).
module ode_fifo_ptr #(
    parameter AW = 3                       // address bits; depth = 2**AW
) (
    input  wire          wclk,
    input  wire          wrst,             // async reset of the write side
    input  wire          winc,
    output wire [AW-1:0] waddr,
    output reg           wfull  = 1'b0,
    input  wire          rclk,
    input  wire          rrst,             // async reset of the read side
    input  wire          rinc,
    output wire [AW-1:0] raddr,
    output reg           rempty = 1'b0     // powers up 0 (all iCE40 flip-flops do); a reset sets it
);
    reg  [AW:0] wbin = 0, wgray = 0, wq1_rgray = 0, wq2_rgray = 0;
    reg  [AW:0] rbin = 0, rgray = 0, rq1_wgray = 0, rq2_wgray = 0;
    wire [AW:0] wbin_next  = wbin + {{AW{1'b0}}, winc & ~wfull};
    wire [AW:0] wgray_next = (wbin_next >> 1) ^ wbin_next;
    wire [AW:0] rbin_next  = rbin + {{AW{1'b0}}, rinc & ~rempty};
    wire [AW:0] rgray_next = (rbin_next >> 1) ^ rbin_next;

    always @(posedge wclk or posedge wrst)
        if (wrst) begin
            wbin <= 0; wgray <= 0; wq1_rgray <= 0; wq2_rgray <= 0; wfull <= 1'b0;
        end else begin
            wbin      <= wbin_next;
            wgray     <= wgray_next;
            wq1_rgray <= rgray;
            wq2_rgray <= wq1_rgray;
            wfull     <= wgray_next == {~wq2_rgray[AW:AW-1], wq2_rgray[AW-2:0]};
        end

    always @(posedge rclk or posedge rrst)
        if (rrst) begin
            rbin <= 0; rgray <= 0; rq1_wgray <= 0; rq2_wgray <= 0; rempty <= 1'b1;
        end else begin
            rbin      <= rbin_next;
            rgray     <= rgray_next;
            rq1_wgray <= wgray;
            rq2_wgray <= rq1_wgray;
            rempty    <= rgray_next == rq2_wgray;
        end

    assign waddr = wbin[AW-1:0];
    assign raddr = rbin[AW-1:0];
endmodule

// 512 x 8 block RAM (one SB_RAM40_4K), registered read.
module ode_ram512x8 (
    input  wire       wclk, wclke, we,
    input  wire [8:0] waddr,
    input  wire [7:0] wdata,
    input  wire       rclk, rclke,
    input  wire [8:0] raddr,
    output wire [7:0] rdata
);
    wire [15:0] rd;
    SB_RAM40_4K #(.READ_MODE(1), .WRITE_MODE(1)) ram (
        .WADDR({2'b00, waddr}), .RADDR({2'b00, raddr}), .MASK(16'h0000),
        .WDATA({1'b0, wdata[7], 1'b0, wdata[6], 1'b0, wdata[5], 1'b0, wdata[4],
                1'b0, wdata[3], 1'b0, wdata[2], 1'b0, wdata[1], 1'b0, wdata[0]}),
        .RDATA(rd), .WE(we), .WCLKE(wclke), .WCLK(wclk), .RE(1'b1), .RCLKE(rclke), .RCLK(rclk));
    assign rdata = {rd[14], rd[12], rd[10], rd[8], rd[6], rd[4], rd[2], rd[0]};
endmodule

// 2048 x 8 block RAM: four SB_RAM40_4K in 2048 x 2 mode sharing one address (the original uses the EBR address
// cascade for this; separate address wiring is equivalent).
module ode_ram2048x8 (
    input  wire        wclk, wclke, we,
    input  wire [10:0] waddr,
    input  wire [7:0]  wdata,
    input  wire        rclk, rclke,
    input  wire [10:0] raddr,
    output wire [7:0]  rdata
);
    genvar k;
    generate for (k = 0; k < 4; k = k + 1) begin : ram_
        wire [15:0] rd;
        SB_RAM40_4K #(.READ_MODE(3), .WRITE_MODE(3)) ram (
            .WADDR(waddr), .RADDR(raddr), .MASK(16'h0000),
            .WDATA({4'b0, wdata[2*k+1], 7'b0, wdata[2*k], 3'b0}),
            .RDATA(rd), .WE(we), .WCLKE(wclke), .WCLK(wclk), .RE(1'b1), .RCLKE(rclke), .RCLK(rclk));
        assign rdata[2*k+1:2*k] = {rd[11], rd[3]};
    end endgenerate
endmodule

// 75 Hz pacing window: a counter on the oscillator clock wraps every 160,001 cycles (1/75 s if the oscillator is
// 12 MHz oscillator), and `window` is high for 2048 cycles after each wrap.
module ode_pacer (
    input  wire clk_osc,
    output reg  window = 1'b0
);
    reg [18:0] count = 19'd0;
    always @(posedge clk_osc) begin
        count <= (count == 19'd160000) ? 19'd0 : count + 19'd1;
        if (count == 19'd0)  window <= 1'b1;
        else if (count[11])  window <= 1'b0;
    end
endmodule

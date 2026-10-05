//============================================================================
//
//  Sharp MZ printer port to the MiSTer UART (OSD Printer: UART).
//
//  The MZ-700 (I/O FE/FF) and the MZ-800/1500 (Z80 PIO: port B data, PA7 RDP, PA0 RDA) drive a parallel
//  printer with the same handshake (MZ-800 Technical Reference Manual, 7 Printer interface; MZ-700 BASIC
//  1Z-013B at 2871): wait for RDA low, put the byte on the data port, raise RDP, wait for RDA high, drop
//  RDP. This module is the printer: it takes the byte on the rising edge of RDP and answers RDA = RDP
//  (an acknowledge for every strobe), held high while its buffer is full. The bytes are sent out of the
//  MiSTer UART, 8N1 at the speed chosen in Main's UART menu (9600 if none), for the printer daemon on
//  the HPS (mister_printerd: Epson text and graphics to PDF).
//
//  Copyright (C) 2026 SharpMZ MiSTer contributors. GPL v2 or later.
//
//============================================================================

module mz_printer #(parameter CLK_HZ = 70937600)
(
	input             clk,
	input             reset,
	input             enable,          // OSD Printer: UART
	input             rdp,             // strobe from the machine, active high (MZ standard)
	input       [7:0] data,
	output            rda,             // to the machine: high = busy / acknowledge
	input      [31:0] uart_speed,      // from hps_io (0 = not set)
	output reg        txd = 1'b1,
	output     [15:0] count            // bytes taken since reset (for the OSD / debugging)
);

// 512-byte FIFO.
reg  [7:0] fifo[512];
reg  [9:0] wp = 0, rp = 0;
wire [9:0] used = wp - rp;
wire       full = used[9];
wire       empty = (wp == rp);

reg        rdp_l = 0;
reg [15:0] taken = 0;
assign count = taken;
assign rda   = enable & (rdp | full);

always @(posedge clk) begin
	rdp_l <= rdp;
	if (reset) begin
		wp    <= 0;
		taken <= 0;
	end
	else if (enable & rdp & ~rdp_l & ~full) begin
		fifo[wp[8:0]] <= data;
		wp    <= wp + 1'd1;
		taken <= taken + 1'd1;
	end
end

// UART transmitter, 8N1. The bit time is a fractional accumulator (adds the baud rate every clock, a bit
// ends when it passes CLK_HZ), so any speed Main offers works without a divider.
wire [31:0] baud = (uart_speed == 0 || uart_speed > CLK_HZ / 4) ? 32'd9600 : uart_speed;
reg  [31:0] acc = 0;
reg   [3:0] bitn = 0;                   // 0 idle, 1 start, 2-9 data, 10 stop
reg   [7:0] sh = 0;
wire [32:0] acc_next = acc + baud;
wire        bit_end = acc_next >= CLK_HZ;

always @(posedge clk) begin
	if (reset | ~enable) begin
		txd  <= 1'b1;
		bitn <= 0;
		rp   <= wp;                     // drop what is queued
	end
	else if (bitn == 0) begin
		if (~empty) begin
			sh   <= fifo[rp[8:0]];
			rp   <= rp + 1'd1;
			acc  <= 0;
			bitn <= 1;
			txd  <= 1'b0;               // start bit
		end
	end
	else if (bit_end) begin
		acc <= acc_next[31:0] - CLK_HZ;
		if (bitn == 10) begin
			bitn <= 0;
		end
		else begin
			bitn <= bitn + 1'd1;
			if (bitn == 9) txd <= 1'b1; // stop bit
			else begin
				txd <= sh[0];
				sh  <= {1'b0, sh[7:1]};
			end
		end
	end
	else acc <= acc_next[31:0];
end

endmodule

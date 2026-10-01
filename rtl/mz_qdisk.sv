//============================================================================
//
//  Sharp MZ-1500 / MZ-800 Quick Disk (MZ-1F11 drive behind a Z80 SIO at F4-F7).
//
//  The SIO is modelled at byte level, after mz800emu's hw-generic/qdisk (qdisk.c):
//    F4 data A  - bytes from the drive (sequential read of the disk stream)
//    F5 data B  - reads FF
//    F6 ctrl A  - RR0: b0 byte available, b2 Tx buffer empty, b3 DCD (disk present),
//                 b4 hunt (sync search in progress), b5 CTS (not write protected); RR1 b6 CRC error
//    F7 ctrl B  - WR5 b7 is the drive motor; turning it off rewinds the head (head home).
//                 RR0 reads FF, as mz800emu (its head-home bit is never returned).
//  The disk turns: while the motor runs a byte passes the head every BYTE_CLKS clocks (about 79 us, so
//  a 48 KB file loads in about 4 s as on the real drive), whether the CPU reads it or not. A WR3 write
//  with b0 (Rx enable) and b4 (enter hunt) watches the passing bytes for WR6, WR7; with b1 (sync load
//  inhibit) further sync characters are dropped, then each byte goes to the receive buffer (RR0 b0) and
//  a data read takes it. mz800emu instead advances the disk only when the CPU reads, which works for its
//  cleaned-up .mzq images but not for real dumps: after each block they carry trailing sync bytes and a
//  gap that the drive spins past while the BIOS handles the block.
//
//  The disk is the raw byte stream of the medium: a .mzq (mz800emu) or a .qdf (16-byte "-QD format-"
//  header, skipped), read through two 512-byte sector buffers with prefetch. If a sector is late the
//  disk waits for it.
//
//  Read only for now: CTS reports write protect and data writes are ignored.
//
//  Copyright (C) 2026 SharpMZ MiSTer contributors. GPL v2 or later.
//
//============================================================================

module mz_qdisk
(
	input         clk_sys,
	input         reset,
	input         enable,         // The machine has the drive (MZ-1500; MZ-800 with an image mounted)

	// Z80 I/O
	input   [7:0] io_addr,
	input         io_rd,
	input         io_wr,
	input   [7:0] io_dout,        // CPU data out
	output  [7:0] io_din,
	output        io_oe,

	// MiSTer image slot
	input         img_mounted,
	input  [63:0] img_size,
	output reg [31:0] sd_lba,
	output reg    sd_rd,
	output        sd_wr,
	input         sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	output        busy            // motor on (LED)
);

assign sd_wr       = 0;
assign sd_buff_din = 8'hFF;

localparam [16:0] QD_MAX    = 17'd89826;         // mz800emu QDISK_IMAGE_MAX_SIZE
parameter         BYTE_CLKS = 5583;              // clk_sys clocks per byte (70.9 MHz, ~101.6 kbit/s)

wire sel   = enable & (io_addr[7:2] == 6'b111101); // F4-F7
assign io_oe = sel & io_rd;

// ---------------------------------------------------------------------------------------------
// Image
// ---------------------------------------------------------------------------------------------
reg        mounted = 0;
reg [19:0] size    = 0;                          // image size (bytes)
reg  [4:0] base    = 0;                          // 16 for a .qdf
reg        base_known = 0;

// Two sector buffers, selected by the sector number's bit 0.
reg  [7:0] buf_ram[1024];
reg  [7:0] buf_q;
reg  [9:0] buf_raddr;
always @(posedge clk_sys) begin
	if (sd_ack & sd_buff_wr) buf_ram[{sd_lba[0], sd_buff_addr}] <= sd_buff_dout;
	buf_q <= buf_ram[buf_raddr];
end

reg  [1:0] valid = 0;
reg [10:0] tag[2];                               // sector number held by each buffer

// ---------------------------------------------------------------------------------------------
// SIO state
// ---------------------------------------------------------------------------------------------
reg  [7:0] wa[8], wb[8];                         // write registers, channel A / B
reg  [2:0] pa, pb;                               // register pointers
reg  [7:0] rb2;                                  // channel B interrupt vector (RR2)
reg        hunt = 0;                             // RR0 b4, channel A
reg        head_home = 1;
reg [16:0] pos = 0;                              // position in the disk stream (after the header)

wire       motor = wb[5][7];
assign busy = mounted & motor;

// The byte at pos: absolute offset, sector, buffer.
wire [19:0] abs     = {3'd0, pos} + base;
wire [10:0] sector  = abs[19:9];
wire        b_sel   = sector[0];
wire        in_img  = abs < size;
wire        hit     = valid[b_sel] & (tag[b_sel] == sector);

reg  [7:0] head_byte;                            // byte at pos, once fetched
reg        head_ok = 0;                          // head_byte is current
reg  [1:0] fetch = 0;
reg [16:0] head_pos;

// The byte under the head (FF past the end of the image or the medium).
wire [7:0] next_byte = (in_img & (pos <= QD_MAX)) ? head_byte : 8'hFF;
wire       spinning  = mounted & motor & base_known;

reg  [7:0] rx_buf;
reg        rx_avail = 0;                         // RR0 b0
reg        overrun  = 0;                         // RR1 b5
reg        strip    = 0;                         // dropping sync characters after hunt (WR3 b1)
reg [12:0] tick     = 0;

wire [7:0] rr0_a = {2'b00, 1'b0 /* CTS: write protected */, hunt, mounted, 1'b1, 1'b0, rx_avail};
wire [7:0] rr1_a = {1'b0, pos > QD_MAX, overrun, 5'd0};

// ---------------------------------------------------------------------------------------------
// CPU access and the turning disk
// ---------------------------------------------------------------------------------------------
reg        rd_last = 0, wr_last = 0;
reg  [7:0] rd_data;
assign io_din = rd_data;

reg [7:0] last_b;                                // hunt: previous byte
reg       consume;                               // the head moved on to the next byte

always @(posedge clk_sys) begin
	rd_last <= io_rd & sel;
	wr_last <= io_wr & sel;
	consume <= 0;

	// --- the disk: one byte every BYTE_CLKS while the motor runs (waits for a late sector) ---
	if (~spinning) tick <= BYTE_CLKS[12:0];
	else if (tick != 0) tick <= tick - 1'd1;
	else if ((head_ok | ~in_img | (pos > QD_MAX)) & ~consume) begin
		tick    <= BYTE_CLKS[12:0];
		consume <= 1;
		if (hunt) begin
			last_b <= next_byte;
			if (last_b == wa[6] && next_byte == wa[7]) begin hunt <= 0; strip <= wa[3][1]; end
		end
		else if (wa[3][0]) begin                                // Rx enabled
			if (strip && (next_byte == wa[6] || next_byte == wa[7])) begin end
			else begin
				strip   <= 0;
				rx_buf  <= next_byte;
				if (rx_avail) overrun <= 1;
				rx_avail <= 1;
			end
		end
	end

	// --- reads (on the first clock of the cycle) ---
	if (io_rd & sel & ~rd_last) begin
		case (io_addr[1:0])
			2'd0: begin                                     // data A
				head_home <= 0;
				rd_data   <= rx_avail ? rx_buf : 8'hFF;
				rx_avail  <= 0;
			end
			2'd1: rd_data <= 8'hFF;                         // data B
			2'd2: begin                                     // ctrl A
				case (pa[1:0])
					2'd0: rd_data <= rr0_a;
					2'd1: rd_data <= rr1_a;
					default: rd_data <= 8'h00;
				endcase
				pa <= 0;
			end
			2'd3: begin                                     // ctrl B
				rd_data <= (pb == 0) ? 8'hFF : (pb[1:0] == 2'd2) ? rb2 : 8'h00;
				pb <= 0;
			end
		endcase
	end

	// --- writes ---
	if (io_wr & sel & ~wr_last) begin
		if (io_addr[1]) begin                               // control
			if (~io_addr[0]) begin                          // channel A
				wa[pa] <= io_dout;
				if (pa == 0) begin
					pa <= io_dout[2:0];
					if (io_dout[5:3] == 3'd3) begin wa[1] <= 0; wa[2] <= 0; wa[3] <= 0; wa[4] <= 0; wa[5] <= 0; wa[6] <= 0; wa[7] <= 0; hunt <= 0; rx_avail <= 0; end
					if (io_dout[5:3] == 3'd6) overrun <= 0;     // error reset
				end
				else begin
					if (pa == 3 && io_dout[4] && io_dout[0]) begin hunt <= 1; last_b <= 8'h00; rx_avail <= 0; end
					pa <= 0;
				end
			end
			else begin                                      // channel B
				wb[pb] <= io_dout;
				if (pb == 0) begin
					pb <= io_dout[2:0];
					if (io_dout[5:3] == 3'd3) begin wb[1] <= 0; wb[2] <= 0; wb[3] <= 0; wb[4] <= 0; wb[5] <= 0; wb[6] <= 0; wb[7] <= 0; end
				end
				else begin
					if (pb == 2) rb2 <= io_dout;
					if (pb == 5 && ~io_dout[7]) begin pos <= 0; head_home <= 1; hunt <= 0; rx_avail <= 0; end   // motor off: rewind
					pb <= 0;
				end
			end
		end
		// data writes ignored (write protected)
	end

	if (consume) pos <= pos + 1'd1;

	if (reset) begin
		wa[0] <= 0; wa[1] <= 0; wa[2] <= 0; wa[3] <= 0; wa[4] <= 0; wa[5] <= 0; wa[6] <= 0; wa[7] <= 0;
		wb[0] <= 0; wb[1] <= 0; wb[2] <= 0; wb[3] <= 0; wb[4] <= 0; wb[5] <= 0; wb[6] <= 0; wb[7] <= 0;
		pa <= 0; pb <= 0; hunt <= 0; pos <= 0; head_home <= 1; rx_avail <= 0; overrun <= 0;
	end
	if (img_mounted) begin pos <= 0; head_home <= 1; hunt <= 0; rx_avail <= 0; end
end

// ---------------------------------------------------------------------------------------------
// Fetch the byte at pos from the buffers (2 clocks); invalidate when pos moves.
// ---------------------------------------------------------------------------------------------
always @(posedge clk_sys) begin
	if (consume | img_mounted | reset | (head_pos != pos)) begin
		head_ok <= 0;
		fetch   <= 0;
	end
	else if (~head_ok & hit) begin
		case (fetch)
			2'd0: begin buf_raddr <= {b_sel, abs[8:0]}; fetch <= 2'd1; end
			2'd1: fetch <= 2'd2;
			2'd2: begin head_byte <= buf_q; head_ok <= 1; fetch <= 0; end
		endcase
	end
	head_pos <= pos;
end

// ---------------------------------------------------------------------------------------------
// Sector loading: keep the current sector and the next one in the buffers while the motor runs.
// Sector 0 is read at mount to see whether there is a .qdf header.
// ---------------------------------------------------------------------------------------------
reg  [1:0] ld_state = 0;
reg [10:0] ld_sector;

wire [10:0] want0 = base_known ? sector : 11'd0;
wire [10:0] want1 = sector + 1'd1;
wire        need0 = ~(valid[want0[0]] & tag[want0[0]] == want0);
wire        need1 = base_known & ({want1, 9'd0} < size) & ~(valid[want1[0]] & tag[want1[0]] == want1);

reg  [1:0] hdr_cnt;
reg [23:0] hdr;

always @(posedge clk_sys) begin
	case (ld_state)
		2'd0: if (mounted & (motor | ~base_known)) begin
			if (need0) begin ld_sector <= want0; ld_state <= 2'd1; end
			else if (need1 & motor) begin ld_sector <= want1; ld_state <= 2'd1; end
		end
		2'd1: begin
			sd_lba <= {21'd0, ld_sector};
			valid[ld_sector[0]] <= 0;
			sd_rd <= 1;
			ld_state <= 2'd2;
		end
		2'd2: if (sd_ack) begin sd_rd <= 0; ld_state <= 2'd3; end
		2'd3: if (~sd_ack) begin
			valid[ld_sector[0]] <= 1;
			tag[ld_sector[0]]   <= ld_sector;
			ld_state <= 2'd0;
		end
	endcase

	// Header check on the first bytes of sector 0 as they arrive.
	if (sd_ack & sd_buff_wr & ~base_known & ld_sector == 0 && sd_buff_addr < 3) begin
		hdr <= {hdr[15:0], sd_buff_dout};
		if (sd_buff_addr == 2) begin
			base       <= ({hdr[15:0], sd_buff_dout} == 24'h2D5144) ? 5'd16 : 5'd0;   // "-QD"
			base_known <= 1;
		end
	end

	if (img_mounted) begin
		mounted    <= |img_size;
		size       <= |img_size[63:20] ? 20'hFFFFF : img_size[19:0];
		valid      <= 0;
		base_known <= 0;
		base       <= 0;
		ld_state   <= 0;
		sd_rd      <= 0;
	end
end

endmodule

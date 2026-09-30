//=======================================================================================================
//
// Name:            sharpmz.sv
// Created:         June 2018
// Author(s):       Philip Smart
// Description:     Sharp MZ series compatible logic.
//
//                  MiSTer top level for the emulator (rtl/sharpmz.vhd): OSD, configuration and downloads.
//                  The sys/ directory is expected to be the stock Template_MiSTer sys drop-in.
//
// Copyright:       (C) 2018 Sorgelig
//                  (C) 2018 Philip Smart <philip.smart@net2net.org>
//
// History:         June 2018 - Initial creation.
//
//=======================================================================================================
// This source file is free software: you can redistribute it and-or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//=======================================================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

`ifdef MISTER_DUAL_SDRAM
assign {SDRAM2_DQ, SDRAM2_A, SDRAM2_BA, SDRAM2_CLK, SDRAM2_nWE, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nCS} = 'Z;
`endif

`ifdef MISTER_FB
assign FB_EN = 0;
assign FB_FORMAT = 0;
assign FB_WIDTH = 0;
assign FB_HEIGHT = 0;
assign FB_BASE = 0;
assign FB_STRIDE = 0;
assign FB_FORCE_BLANK = 0;
`ifdef MISTER_FB_PALETTE
assign FB_PAL_CLK = 0;
assign FB_PAL_ADDR = 0;
assign FB_PAL_DOUT = 0;
assign FB_PAL_WR = 0;
`endif
`endif

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

`include "build_id.v"

localparam CONF_STR =
{
	"SharpMZ;;",
	"-;",
	"P1,Machine;",
	"P1O[3:1],Model,MZ80A,MZ80K,MZ80C,MZ1200,MZ700,MZ80B,MZ2000,MZ800;",
	"P1O[6:4],CPU Speed,Default,+1,+2,+3,+4,+5,+6,+7;",
	"P1O[30],Boot Reset,Off,On;",
	"P1O[32],MZ-800 Mode,MZ-700,MZ-800;",
	"-;",
	"P2,Tape;",
	"P2F1,MZF,Load Tape to CMT;",
	"P2F2,MZF,Load Direct to RAM;",
	"P2S0,MZTMZF,Tape Image;",
	"P2T[31],Rewind Tape Image;",
	"P2O[25:24],Tape Buttons,Auto,Off,Play,Record;",
	"P2O[23:21],Fast Tape,Default,Off,2x,4x,8x,16x,32x,Default;",
	"P2O[27:26],Sharp ASCII Name,Off,On Save,On Load,Both;",
	"P2O[20],Audio Source,Sound,Tape;",
	"-;",
	"P3,Display;",
	"P3O[8:7],Display Type,Default,Mono 80x25,Colour 40x25,Colour 80x25;",
	"P3O[16],Video,On,Off;",
	"P3O[17],Graphics,On,Off;",
	"P3O[18],VRAM Wait,Off,On;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"P5,Floppy;",
	"P5S1,DSK,Drive A;",
	"P5S2,DSK,Drive B;",
	"P5O[34:33],Floppy Interface,Auto,On,Off;",
	"-;",
	"P4,ROM and RAM;",
	"P4O[28],User ROM,Off,On;",
	"P4O[29],FDC ROM,Off,On;",
	"P4F3,ROMBIN,Load System ROM,0x000000;",
	"P4F4,ROMBIN,Load System RAM,0x100000;",
	"P4F5,ROMBIN,Load Keymap,0x200000;",
	"P4F6,ROMBIN,Load CGROM,0x500000;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"v,5;",
	"V,v",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

// 70.9376 MHz = 4 x the 17.7344 MHz MZ-700 crystal. rtl/clkgen.vhd derives all
// machine clock enables from it (CLK_HZ must match).
wire clk_sys;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

/////////////////  HPS  ///////////////////////////

wire forced_scandoubler;
wire [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;

wire        hps_ioctl_download;
wire        hps_ioctl_upload;
wire [15:0] hps_ioctl_index;
wire        hps_ioctl_wr;
wire        hps_ioctl_rd;
wire [26:0] hps_ioctl_addr;
wire  [7:0] hps_ioctl_dout;
wire  [7:0] hps_ioctl_din;
wire [31:0] hps_ioctl_file_ext;

// Image slots: S0 tape image, S1/S2 floppy drives A/B.
wire  [2:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire [31:0] sd_lba[3];
wire  [2:0] sd_rd;
wire  [2:0] sd_wr;
wire  [2:0] sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[3];
wire        sd_buff_wr;

wire        tape_active;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.buttons(buttons),
	.status(status),
	.status_in(128'd0),
	.status_set(1'b0),
	.status_menumask(16'd0),
	.forced_scandoubler(forced_scandoubler),
	.video_rotated(1'b0),
	.new_vmode(1'b0),

	.ps2_key(ps2_key),
	.ps2_kbd_led_status(3'd0),
	.ps2_kbd_led_use(3'd0),

	.ioctl_download(hps_ioctl_download),
	.ioctl_upload(hps_ioctl_upload),
	.ioctl_index(hps_ioctl_index),
	.ioctl_wr(hps_ioctl_wr),
	.ioctl_rd(hps_ioctl_rd),
	.ioctl_addr(hps_ioctl_addr),
	.ioctl_dout(hps_ioctl_dout),
	.ioctl_din(hps_ioctl_din),
	.ioctl_file_ext(hps_ioctl_file_ext),
	.ioctl_upload_req(1'b0),
	.ioctl_upload_index(8'd0),
	.ioctl_wait(tape_active),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_blk_cnt('{6'd0, 6'd0, 6'd0}),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.info_req(1'b0),
	.info(8'd0)
);

/////////////////  CONFIG ADAPTER  ////////////////

function automatic [2:0] mz_model_code(input [2:0] menu_sel);
	begin
		case(menu_sel)
			3'd0: mz_model_code = 3'd3; // MZ80A
			3'd1: mz_model_code = 3'd0; // MZ80K
			3'd2: mz_model_code = 3'd1; // MZ80C
			3'd3: mz_model_code = 3'd2; // MZ1200
			3'd4: mz_model_code = 3'd4; // MZ700
			3'd5: mz_model_code = 3'd6; // MZ80B
			3'd6: mz_model_code = 3'd7; // MZ2000
			default: mz_model_code = 3'd5; // MZ800
		endcase
	end
endfunction

function automatic [2:0] mz_display_type(input [1:0] menu_sel, input [2:0] model);
	begin
		case(menu_sel)
			2'd0: begin
				case(model)
					3'd4,
					3'd5: mz_display_type = 3'd2; // MZ700/MZ800 default to colour 40x25.
					3'd6,
					3'd7: mz_display_type = 3'd1; // MZ80B/MZ2000 default to mono 80x25.
					default: mz_display_type = 3'd0; // MZ80K/C/1200/A default to mono 40x25.
				endcase
			end
			2'd1: mz_display_type = 3'd1; // Mono 80x25.
			2'd2: mz_display_type = 3'd2; // Colour 40x25.
			default: mz_display_type = 3'd3; // Colour 80x25.
		endcase
	end
endfunction

function automatic [1:0] mz_tape_buttons(input [1:0] menu_sel);
	begin
		case(menu_sel)
			2'd0: mz_tape_buttons = 2'b11; // Auto.
			2'd1: mz_tape_buttons = 2'b00; // Off.
			2'd2: mz_tape_buttons = 2'b01; // Play.
			default: mz_tape_buttons = 2'b10; // Record.
		endcase
	end
endfunction

function automatic [2:0] mz_fast_tape(input [2:0] menu_sel);
	begin
		case(menu_sel)
			3'd0: mz_fast_tape = 3'b110; // Core default.
			3'd1: mz_fast_tape = 3'b000; // Off/original speed.
			3'd2: mz_fast_tape = 3'b001; // 2x.
			3'd3: mz_fast_tape = 3'b010; // 4x.
			3'd4: mz_fast_tape = 3'b011; // 8x.
			3'd5: mz_fast_tape = 3'b100; // 16x.
			3'd6: mz_fast_tape = 3'b101; // 32x where supported.
			default: mz_fast_tape = 3'b110; // Core default.
		endcase
	end
endfunction

wire [2:0] cfg_model = mz_model_code(status[3:1]);
wire [2:0] cfg_display = mz_display_type(status[8:7], cfg_model);
wire [1:0] cfg_tape_buttons = mz_tape_buttons(status[25:24]);
wire [2:0] cfg_fast_tape = mz_fast_tape(status[23:21]);
wire [7:0] cfg_userrom = status[28] ? (8'd1 << cfg_model) : 8'd0;
wire [7:0] cfg_fdcrom  = status[29] ? (8'd1 << cfg_model) : 8'd0;

wire [7:0] cfg_reg0_model   = {5'd0, cfg_model};
wire [7:0] cfg_reg1_display = {1'b0, status[18], status[17], status[16], 1'b0, cfg_display};  // PCG is software controlled (E010-E012).
wire [7:0] cfg_reg2_display = 8'd3;                    // Native timing (the video is native-only).
wire [7:0] cfg_reg3_display = {5'd0, status[32], 2'b00};   // 2: MZ-800 rear mode switch (0 = MZ-700, as mz800emu's default; 1 = MZ-800).
wire [7:0] cfg_reg4_cpu     = {status[30], 4'd0, status[6:4]};
wire [7:0] cfg_reg5_audio   = {7'd0, status[20]};
wire [7:0] cfg_reg6_cmt     = {1'b0, status[27], status[26], cfg_tape_buttons, cfg_fast_tape};
wire [7:0] cfg_reg8_userrom = cfg_userrom;
wire [7:0] cfg_reg9_fdcrom  = cfg_fdcrom;

/////////////////  DOWNLOAD ROUTING  //////////////

localparam [5:0] FILE_TAPE_CMT    = 6'd1;
localparam [5:0] FILE_TAPE_DIRECT = 6'd2;
localparam [24:0] IOCTL_SYSRAM_BASE = 25'h0100000;

reg hps_ioctl_download_d = 0;
reg [5:0] active_file_slot = 0;
reg [15:0] mzf_size = 0;
reg [15:0] mzf_load_addr = 0;
reg [7:0] direct_load_reset_ctr = 0;

always @(posedge clk_sys) begin
	hps_ioctl_download_d <= hps_ioctl_download;

	if(!hps_ioctl_download_d && hps_ioctl_download) begin
		active_file_slot <= hps_ioctl_index[5:0];
		mzf_size <= 0;
		mzf_load_addr <= 0;
	end

	if(hps_ioctl_download_d && !hps_ioctl_download && active_file_slot == FILE_TAPE_DIRECT) begin
		direct_load_reset_ctr <= 8'd64;
	end
	else if(direct_load_reset_ctr != 0) begin
		direct_load_reset_ctr <= direct_load_reset_ctr - 1'd1;
	end

	if(hps_ioctl_download && hps_ioctl_wr && active_file_slot == FILE_TAPE_DIRECT) begin
		case(hps_ioctl_addr)
			27'd18: mzf_size[7:0] <= hps_ioctl_dout;
			27'd19: mzf_size[15:8] <= hps_ioctl_dout;
			27'd20: mzf_load_addr[7:0] <= hps_ioctl_dout;
			27'd21: mzf_load_addr[15:8] <= hps_ioctl_dout;
			default: begin end
		endcase
	end
end

wire        direct_load_active = hps_ioctl_download && active_file_slot == FILE_TAPE_DIRECT;
wire [26:0] mzf_direct_end = 27'd128 + {11'd0, mzf_size};
wire        mzf_direct_wr_valid = active_file_slot != FILE_TAPE_DIRECT ||
                                  hps_ioctl_addr < 27'd128 ||
                                  mzf_size == 16'd0 ||
                                  hps_ioctl_addr < mzf_direct_end;

function automatic [24:0] mz_ioctl_addr_map(
	input [5:0] slot,
	input [26:0] addr,
	input [15:0] load_addr
);
	begin
		case(slot)
			FILE_TAPE_CMT:
				mz_ioctl_addr_map = (addr < 27'd128) ? (25'h0400000 + addr[24:0])
				                                      : (25'h0410000 + (addr[24:0] - 25'd128));
			FILE_TAPE_DIRECT:
				mz_ioctl_addr_map = (addr < 27'd128) ? (IOCTL_SYSRAM_BASE + 25'h0010F0 + addr[24:0])
				                                      : (IOCTL_SYSRAM_BASE + {9'd0, load_addr} + (addr[24:0] - 25'd128));
			default:
				mz_ioctl_addr_map = addr[24:0];
		endcase
	end
endfunction

wire [24:0] hps_ioctl_addr_mapped = mz_ioctl_addr_map(active_file_slot, hps_ioctl_addr, mzf_load_addr);

wire [31:0] mz_ioctl_din;

assign hps_ioctl_din = mz_ioctl_din[7:0];

/////////////////  TAPE IMAGE  ////////////////////

wire [13:0] cmt_status;
wire [24:0] tape_addr;
wire        tape_wr;
wire  [7:0] tape_dout;
wire        tape_mounted, tape_full;
wire  [7:0] tape_record;

tape_image tape_image
(
	.clk(clk_sys),
	.reset(reset),

	.img_mounted(img_mounted[0]),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba[0]),
	.sd_rd(sd_rd[0]),
	.sd_wr(sd_wr[0]),
	.sd_ack(sd_ack[0]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din[0]),
	.sd_buff_wr(sd_buff_wr),

	.rewind(status[31]),
	.host_busy(hps_ioctl_download),
	.cmt_status(cmt_status),

	.active(tape_active),
	.bus_addr(tape_addr),
	.bus_wr(tape_wr),
	.bus_dout(tape_dout),
	.bus_din(mz_ioctl_din[7:0]),

	.mounted(tape_mounted),
	.tape_full(tape_full),
	.record_no(tape_record)
);

// Core download bus: the tape engine, an OSD download, or parked on an unused address. The CMT clears
// its record-ready flag whenever the bus points at its buffers, so it must not idle there.
wire        mz_ioctl_wr   = tape_active ? tape_wr   : (hps_ioctl_wr && mzf_direct_wr_valid);
wire [24:0] mz_ioctl_addr = tape_active ? tape_addr : hps_ioctl_download ? hps_ioctl_addr_mapped : 25'h1000000;
wire  [7:0] mz_ioctl_dout = tape_active ? tape_dout : hps_ioctl_dout;

/////////////////  RESET  /////////////////////////

wire reset = RESET | ~pll_locked;
wire warm_reset = status[0] | buttons[1] | direct_load_active | (direct_load_reset_ctr != 0);

////////////////  Machine  ////////////////////////

wire audio_l_emu;
wire audio_r_emu;
// 1-bit sound (8253 or tape signal, per the Audio Source option) at half scale; the framework's
// DC blocker centres it. Full scale was harsh and sat at a large DC offset.
wire [13:0] audio_psg;                              // MZ-800 PSG mix (0 on other models).
assign AUDIO_L = {1'b0, audio_l_emu, 14'd0} + {2'b00, audio_psg};
assign AUDIO_R = {1'b0, audio_r_emu, 14'd0} + {2'b00, audio_psg};
assign AUDIO_S = 0;
assign AUDIO_MIX = 0;

wire clk_video_in;
wire [7:0] R_emu;
wire [7:0] G_emu;
wire [7:0] B_emu;
wire hblank_emu;
wire vblank_emu;
wire hsync_emu;
wire vsync_emu;
wire [7:0] main_leds;

// Floppy disk interface (MZ-700/MZ-800), drives A/B on image slots S1/S2.
wire [7:0] ext_io_addr, ext_io_dout, ext_io_din;
wire       ext_io_rd, ext_io_wr, ext_io_oe, ext_int_n, ext_ce_cpu;
wire       fdd_busy;
wire [31:0] fdc_lba[2];
wire [7:0]  fdc_buff_din[2];

mz_fdc mz_fdc
(
	.clk_sys(clk_sys),
	.reset(reset),
	.ce_cpu(ext_ce_cpu),
	.model_ok(cfg_model == 3'b100 || cfg_model == 3'b101),
	.mode(status[34:33]),

	.io_addr(ext_io_addr),
	.io_rd(ext_io_rd),
	.io_wr(ext_io_wr),
	.io_dout(ext_io_dout),
	.io_din(ext_io_din),
	.io_oe(ext_io_oe),
	.int_n(ext_int_n),

	.img_mounted(img_mounted[2:1]),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(fdc_lba),
	.sd_rd(sd_rd[2:1]),
	.sd_wr(sd_wr[2:1]),
	.sd_ack(sd_ack[2:1]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(fdc_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.busy(fdd_busy)
);
assign sd_lba[1] = fdc_lba[0];
assign sd_lba[2] = fdc_lba[1];
assign sd_buff_din[1] = fdc_buff_din[0];
assign sd_buff_din[2] = fdc_buff_din[1];

sharpmz sharp_mz
(
	// System clock; the core runs everything on it with clock enables.
	.CLKMASTER(clk_sys),
	.CLKSYS(),
	.CLKVID(clk_video_in),
	.CLKIOP(),

	.COLD_RESET(reset),
	.WARM_RESET(warm_reset),

	.MAIN_LEDS(main_leds),

	.PS2_KEY(ps2_key),

	.VGA_HB_O(hblank_emu),
	.VGA_VB_O(vblank_emu),
	.VGA_HS_O(hsync_emu),
	.VGA_VS_O(vsync_emu),
	.VGA_R_O(R_emu),
	.VGA_G_O(G_emu),
	.VGA_B_O(B_emu),

	.AUDIO_L_O(audio_l_emu),
	.AUDIO_R_O(audio_r_emu),
	.AUDIO_PSG_O(audio_psg),

	.CMT_STATUS(cmt_status),
	.EXT_IO_ADDR(ext_io_addr),
	.EXT_IO_RD(ext_io_rd),
	.EXT_IO_WR(ext_io_wr),
	.EXT_IO_DOUT(ext_io_dout),
	.EXT_IO_DIN(ext_io_din),
	.EXT_IO_OE(ext_io_oe),
	.EXT_INT_n(ext_int_n),
	.EXT_CE_CPU(ext_ce_cpu),

	// Machine configuration from the OSD.
	.CFG_MODEL(cfg_reg0_model),
	.CFG_DISPLAY(cfg_reg1_display),
	.CFG_DISPLAY2(cfg_reg2_display),
	.CFG_DISPLAY3(cfg_reg3_display),
	.CFG_CPU(cfg_reg4_cpu),
	.CFG_AUDIO(cfg_reg5_audio),
	.CFG_CMT(cfg_reg6_cmt),
	.CFG_USERROM(cfg_reg8_userrom),
	.CFG_FDCROM(cfg_reg9_fdcrom),

	// ROM, keymap and tape downloads.
	.IOCTL_DOWNLOAD(hps_ioctl_download),
	.IOCTL_UPLOAD(hps_ioctl_upload),
	.IOCTL_CLK(clk_sys),
	.IOCTL_WR(mz_ioctl_wr),
	.IOCTL_RD(hps_ioctl_rd),
	.IOCTL_ADDR(mz_ioctl_addr),
	.IOCTL_DOUT({24'd0, mz_ioctl_dout}),
	.IOCTL_DIN(mz_ioctl_din)
);

assign LED_USER = hps_ioctl_download;
assign LED_DISK = {1'b0, tape_active | cmt_status[4] | fdd_busy};    // Tape image, CMT or floppy activity.

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = clk_video_in;

assign VGA_R  = R_emu;
assign VGA_G  = G_emu;
assign VGA_B  = B_emu;
assign VGA_VS = vsync_emu;
assign VGA_HS = hsync_emu;
assign VGA_DE = ~(vblank_emu | hblank_emu);

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

endmodule

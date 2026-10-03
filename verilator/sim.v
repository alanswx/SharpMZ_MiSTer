`timescale 1ns/1ns
//
// Simulation top for the SharpMZ core.
//
// The core (rtl/sharpmz.vhd and everything below it) is supplied as a Verilog
// netlist produced by "ghdl synth" -- see the Makefile. Its RAMs and ROMs are
// black boxes filled by rtl_v/dpram.v and rtl_v/dprom.v.
//
// This stands in for sharpmz.sv: the C++ harness drives the configuration
// inputs and the ioctl bus, including the MZF address mapping that sharpmz.sv
// does on hardware.
//
module top(
   input         clk_sys /*verilator public_flat*/,
   input         reset /*verilator public_flat*/,
   input         warm_reset /*verilator public_flat*/,

   output [7:0]  VGA_R /*verilator public_flat*/,
   output [7:0]  VGA_G /*verilator public_flat*/,
   output [7:0]  VGA_B /*verilator public_flat*/,
   output        VGA_HS /*verilator public_flat*/,
   output        VGA_VS /*verilator public_flat*/,
   output        VGA_HB /*verilator public_flat*/,
   output        VGA_VB /*verilator public_flat*/,
   output        ce_pix /*verilator public_flat*/,

   output        AUDIO_L /*verilator public_flat*/,
   output        AUDIO_R /*verilator public_flat*/,
   output [13:0] AUDIO_PSG /*verilator public_flat*/,

   input         ioctl_download,
   input         ioctl_wr,
   input         ioctl_rd,
   input  [24:0] ioctl_addr,
   input  [7:0]  ioctl_dout,
   output [7:0]  ioctl_din,

   input  [10:0] ps2_key,
   input  [5:0]  joy0,           // joystick 1, MiSTer order (5 fire 2, 4 fire 1, 3 up, 2 down, 1 left, 0 right)
   input         joy_1x03,       // MZ-1X03 joysticks connected (MZ-700/1500)
   input         ramdisk_en,     // MZ-800 64 KB RAM disk

   // Machine configuration, as sharpmz.sv derives it from the OSD status bits.
   input  [7:0]  cfg_model,
   input  [7:0]  cfg_display,
   input  [7:0]  cfg_display2,
   input  [7:0]  cfg_display3,
   input  [7:0]  cfg_cpu,
   input  [7:0]  cfg_audio,
   input  [7:0]  cfg_cmt,

   output [15:0] cpu_pc /*verilator public_flat*/,
   output        cpu_ce /*verilator public_flat*/,
   output        cpu_m1_n /*verilator public_flat*/,
   output        dbg_io_wr /*verilator public_flat*/,
   output [7:0]  dbg_io_port /*verilator public_flat*/,
   output [7:0]  dbg_io_data /*verilator public_flat*/,
   output [3:0]  dbg_m8_dmd /*verilator public_flat*/,
   output [7:0]  leds /*verilator public_flat*/,
   output        dbg_sysreset /*verilator public_flat*/,
   output [5:0]  dbg_delay /*verilator public_flat*/,
   output        dbg_rm /*verilator public_flat*/,
   output        dbg_warm /*verilator public_flat*/,
   output        dbg_wait_n /*verilator public_flat*/,
   output        dbg_vwait_n /*verilator public_flat*/,
   output [70:0] dbg_config /*verilator public_flat*/,

   // Tape image slot (hps_io S0), driven by the harness.
   input         img_mounted,
   input         img_readonly,
   input  [63:0] img_size,
   output [31:0] sd_lba,
   output        sd_rd,
   output        sd_wr,
   input         sd_ack,
   input  [8:0]  sd_buff_addr,
   input  [7:0]  sd_buff_dout,
   output [7:0]  sd_buff_din,
   input         sd_buff_wr,
   input         tape_rewind,
   // Floppy drive A (hps_io S1); the sd_buff_* bus above is shared, as in hps_io.
   input         fdd_mounted,
   input         fdd_readonly,
   input  [63:0] fdd_size,
   output [31:0] fdd_lba,
   output        fdd_rd,
   output        fdd_wr,
   input         fdd_ack,
   output [7:0]  fdd_buff_din,
   input  [1:0]  fdc_mode,
   // Quick Disk (hps_io S3); shares sd_buff_*.
   input         qd_mounted,
   input  [63:0] qd_size,
   output [31:0] qd_lba,
   output        qd_rd,
   output        qd_wr,
   input         qd_ack,
   input         qd_readonly,
   output [7:0]  qd_buff_din,
   output        fdd_busy /*verilator public_flat*/,
   output        tape_active /*verilator public_flat*/,
   output        tape_full /*verilator public_flat*/,
   output [7:0]  tape_record /*verilator public_flat*/,
   output [13:0] cmt_status /*verilator public_flat*/,
   output [7:0]  dbg_cmt_ctrl /*verilator public_flat*/,
   output [31:0] dbg_cmt_debug /*verilator public_flat*/,
   output [31:0] dbg_rcv /*verilator public_flat*/,
   output [31:0] dbg_rcv_sum /*verilator public_flat*/,
   output        dbg_pc1 /*verilator public_flat*/,
   output        dbg_readbit /*verilator public_flat*/,
   output        dbg_snd_en /*verilator public_flat*/,
   output        dbg_snd /*verilator public_flat*/,
   output        dbg_bde /*verilator public_flat*/,
   output [2:0]  dbg_map /*verilator public_flat*/,
   output        dbg_memwr /*verilator public_flat*/,
   output [15:0] dbg_addr /*verilator public_flat*/,
   output [7:0]  dbg_wdata /*verilator public_flat*/,
   output [1:0]  dbg_cse /*verilator public_flat*/,

   // Backdoor reads of internal memories for --ascii-end and --dump-mem.
   input  [11:0] vram_addr,
   output [7:0]  vram_q,
   input  [15:0] sysram_addr,
   output [7:0]  sysram_q
);

   wire [31:0] din32;
   wire [24:0] tape_addr;
   wire        tape_wr;
   wire [7:0]  tape_dout;
   wire        tape_mounted;

   tape_image tape(
      .clk(clk_sys), .reset(reset | warm_reset),
      .img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
      .sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
      .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
      .rewind(tape_rewind), .host_busy(ioctl_download), .cmt_status(cmt_status),
      .active(tape_active), .bus_addr(tape_addr), .bus_wr(tape_wr), .bus_dout(tape_dout), .bus_din(din32[7:0]),
      .mounted(tape_mounted), .tape_full(tape_full), .record_no(tape_record)
   );

   // Same bus mux as sharpmz.sv.
   wire        mz_wr   = ioctl_download ? ioctl_wr   : tape_active & tape_wr;     // as sharpmz.sv: downloads first
   wire [24:0] mz_addr = ioctl_download ? ioctl_addr : tape_active ? tape_addr : 25'h1000000;
   wire [7:0]  mz_dout = ioctl_download ? ioctl_dout : tape_dout;
   wire        clksys_out, clkiop_unused;

   wire [7:0]  ext_io_addr, ext_io_dout, ext_io_din;
   wire        ext_io_rd, ext_io_wr, ext_io_oe, ext_int_n, ext_ce_cpu;
   wire [31:0] fdc_lba[2];
   wire [1:0]  fdc_rd, fdc_wr;
   wire [7:0]  fdc_buff_din[2];
   wire        fdc_present;
   wire [7:0]  fdc_io_din, qd_io_din;
   wire        fdc_io_oe, qd_io_oe, qd_busy;
   assign ext_io_oe  = fdc_io_oe | qd_io_oe;
   assign ext_io_din = fdc_io_oe ? fdc_io_din : qd_io_din;

   mz_qdisk qd(
      .clk_sys(clk_sys), .reset(reset | warm_reset),
      .enable(cfg_display3[3] | (cfg_model[2:0] == 3'b101 & qd_mounted_l)),       // MZ-1500; MZ-800 with an image
      .io_addr(ext_io_addr), .io_rd(ext_io_rd), .io_wr(ext_io_wr), .io_dout(ext_io_dout),
      .io_din(qd_io_din), .io_oe(qd_io_oe),
      .img_mounted(qd_mounted), .img_readonly(qd_readonly), .img_size(qd_size),
      .sd_lba(qd_lba), .sd_rd(qd_rd), .sd_wr(qd_wr), .sd_ack(qd_ack),
      .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(qd_buff_din), .sd_buff_wr(sd_buff_wr),
      .busy(qd_busy)
   );
   reg qd_mounted_l = 0;
   always @(posedge clk_sys) if (qd_mounted) qd_mounted_l <= |qd_size;

   mz_fdc fdc(
      .clk_sys(clk_sys), .reset(reset | warm_reset), .ce_cpu(ext_ce_cpu),
      .model_ok(cfg_model[2] == 1'b1), .mode(fdc_mode), .crc_report(1'b0),                          // MZ-700, MZ-800, MZ-80B, MZ-2000
      .io_addr(ext_io_addr), .io_rd(ext_io_rd), .io_wr(ext_io_wr), .io_dout(ext_io_dout),
      .io_din(fdc_io_din), .io_oe(fdc_io_oe), .int_n(ext_int_n),
      .img_mounted({1'b0, fdd_mounted}), .img_readonly(fdd_readonly), .img_size(fdd_size),
      .sd_lba(fdc_lba), .sd_rd(fdc_rd), .sd_wr(fdc_wr), .sd_ack({1'b0, fdd_ack}),
      .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(fdc_buff_din), .sd_buff_wr(sd_buff_wr),
      .busy(fdd_busy), .present(fdc_present)
   );
   assign fdd_lba = fdc_lba[0];
   assign fdd_rd = fdc_rd[0];
   assign fdd_wr = fdc_wr[0];
   assign fdd_buff_din = fdc_buff_din[0];

   sharpmz core(
      .CLKMASTER      (clk_sys),
      .COLD_RESET     (reset),
      .WARM_RESET     (warm_reset),
      .PS2_KEY        (ps2_key),
      .JOY0           (joy0),
      .JOY1           (6'd0),
      .JOY_1X03       (joy_1x03),
      .RAMDISK_EN     (ramdisk_en),
      .CFG_MODEL      (cfg_model),
      .CFG_DISPLAY    (cfg_display),
      .CFG_DISPLAY2   (cfg_display2),
      .CFG_DISPLAY3   (cfg_display3),
      .CFG_CPU        (cfg_cpu),
      .CFG_AUDIO      (cfg_audio),
      .CFG_CMT        (cfg_cmt),
      .CFG_USERROM    (cfg_display3[3] ? 8'h10 : 8'h00),                               // MZ-1500: E800-EFFF is always ROM
      .CFG_FDCROM     (((fdc_present & cfg_model[2:0] == 3'b100) | cfg_display3[3]) ? 8'h10 : 8'h00),   // MZ-700 FD ROM with the interface; MZ-1500 F000 ROM
      .IOCTL_DOWNLOAD (ioctl_download),
      .IOCTL_UPLOAD   (1'b0),
      .IOCTL_CLK      (clk_sys),
      .IOCTL_WR       (mz_wr),
      .IOCTL_RD       (ioctl_rd),
      .IOCTL_ADDR     (mz_addr),
      .IOCTL_DOUT     ({24'd0, mz_dout}),
      .CLKSYS         (clksys_out),
      .CLKVID         (ce_pix),
      .CLKIOP         (clkiop_unused),
      .MAIN_LEDS      (leds),
      .VGA_HB_O       (VGA_HB),
      .VGA_VB_O       (VGA_VB),
      .VGA_HS_O       (VGA_HS),
      .VGA_VS_O       (VGA_VS),
      .VGA_R_O        (VGA_R),
      .VGA_G_O        (VGA_G),
      .VGA_B_O        (VGA_B),
      .AUDIO_L_O      (AUDIO_L),
      .AUDIO_R_O      (AUDIO_R),
      .AUDIO_PSG_O    (AUDIO_PSG),
      .AUDIO_PSG_R_O  (),
      .CMT_STATUS     (cmt_status),
      .CMT_CTRL       (dbg_cmt_ctrl),
      .CMT_DEBUG      (dbg_cmt_debug),
      .EXT_IO_ADDR    (ext_io_addr),
      .EXT_IO_RD      (ext_io_rd),
      .EXT_IO_WR      (ext_io_wr),
      .EXT_IO_DOUT    (ext_io_dout),
      .EXT_IO_DIN     (ext_io_din),
      .EXT_IO_OE      (ext_io_oe),
      .EXT_INT_n      (ext_int_n),
      .EXT_CE_CPU     (ext_ce_cpu),
      .IOCTL_DIN      (din32)
   );

   assign ioctl_din = din32[7:0];

   // Debug taps into the netlist; ghdl keeps register and port names.
   assign cpu_pc = core.cpu0.u0.pc;
   assign cpu_ce = core.clkgen0.ckencpui;
   assign cpu_m1_n = core.cpu0.u0.m1_n;
   assign dbg_io_wr = ~core.t80_iorq_n & ~core.t80_wr_n;
   mz800_border bdr(.clk(clk_sys), .ce_pix(ce_pix), .enable(1'b1), .hblank(VGA_HB), .vblank(VGA_VB), .bcol(4'd1),
                    .r_in(8'd0), .g_in(8'd0), .b_in(8'd0), .r_out(), .g_out(), .b_out(), .de(dbg_bde));
   assign dbg_snd_en = core.mz80hw.sound_enable;        // 8253 GATE0 (E008 bit 0)
   assign dbg_snd    = core.mz80hw.sound_pulse_x2;      // 8253 OUT0
   assign dbg_memwr  = ~core.t80_mreq_n & ~core.t80_wr_n;
   assign dbg_addr   = core.t80_a16;
   assign dbg_wdata  = core.t80_do;
   assign dbg_cse    = {core.mz80hw.cs_e_ni, core.mz80hw.cs_e2_n};
   assign dbg_map    = {core.mz80hw.mz_gram_enable, core.mz80hw.mz_high_ram_inhibit, core.mz80hw.mz_high_ram_enable};
   assign dbg_io_port = core.t80_a16[7:0];
   assign dbg_io_data = core.t80_do;
   assign dbg_m8_dmd = core.mz80hw.m8_dmd;
   assign dbg_sysreset = core.mz_system_reset;
   assign dbg_delay = core.ctrl0.delay;
   assign dbg_rm = core.ctrl0.reset_machine;
   assign dbg_warm = core.ctrl0.warm_reset;
   assign dbg_wait_n = core.t80_wait_n;
   assign dbg_vwait_n = core.video_wait_n;
   assign dbg_config = core.config_v;
   // CMT record FSM: {rcv_ram_state, rcv_state, recseq, type, error, try, success, done, ready_set}
   assign dbg_rcv = {15'd0, core.tape0.rcv_ram_state, core.tape0.rcv_state, core.tape0.recseq,
                     core.tape0.rcv_type, core.tape0.rcv_error, core.tape0.rcv_ram_try,
                     core.tape0.rcv_ram_success, core.tape0.rcv_done, core.tape0.record_ready_set};
   assign dbg_rcv_sum = {core.tape0.rcv_ram_checksum, core.tape0.rcv_checksum};
   assign dbg_pc1 = core.mz80hw.i8255_pc_o[1];
   assign dbg_readbit = core.tape0.readbit;

   // v2 VideoController VRAM: four byte lanes, byte address = lane + 4 * index.
   wire [7:0] vl0 = core.video0.vc.vram0.lanes_n1_ram.mem[vram_addr[11:2]];
   wire [7:0] vl1 = core.video0.vc.vram0.lanes_n2_ram.mem[vram_addr[11:2]];
   wire [7:0] vl2 = core.video0.vc.vram0.lanes_n3_ram.mem[vram_addr[11:2]];
   wire [7:0] vl3 = core.video0.vc.vram0.lanes_n4_ram.mem[vram_addr[11:2]];
   assign vram_q = vram_addr[1:0] == 2'd0 ? vl0 : vram_addr[1:0] == 2'd1 ? vl1 : vram_addr[1:0] == 2'd2 ? vl2 : vl3;
   assign sysram_q = core.sysram.mem[sysram_addr];

endmodule

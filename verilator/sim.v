`timescale 1ns/1ns
//
// Simulation top for the SharpMZ core.
//
// The core (rtl/sharpmz.vhd and everything below it) is supplied as a Verilog
// netlist produced by "ghdl synth" -- see the Makefile. Its RAMs and ROMs are
// black boxes filled by rtl_v/dpram.v and rtl_v/dprom.v.
//
// This stands in for sharpmz.sv + bridge.vhd: the C++ harness drives the ioctl
// bus directly, including the config register writes and MZF address mapping
// that sharpmz.sv does on hardware.
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

   input         ioctl_download,
   input         ioctl_wr,
   input         ioctl_rd,
   input  [24:0] ioctl_addr,
   input  [7:0]  ioctl_dout,
   output [7:0]  ioctl_din,

   input  [10:0] ps2_key,

   output [15:0] cpu_pc /*verilator public_flat*/,
   output        cpu_ce /*verilator public_flat*/,
   output        cpu_m1_n /*verilator public_flat*/,
   output [7:0]  leds /*verilator public_flat*/,
   output        dbg_sysreset /*verilator public_flat*/,
   output [5:0]  dbg_delay /*verilator public_flat*/,
   output        dbg_rm /*verilator public_flat*/,
   output        dbg_warm /*verilator public_flat*/,
   output        dbg_wait_n /*verilator public_flat*/,
   output        dbg_vwait_n /*verilator public_flat*/,
   output [70:0] dbg_config /*verilator public_flat*/,

   // Backdoor reads of internal memories for --ascii-end and --dump-mem.
   input  [11:0] vram_addr,
   output [7:0]  vram_q,
   input  [15:0] sysram_addr,
   output [7:0]  sysram_q
);

   wire [31:0] din32;
   wire        clksys_out, clkiop_unused;

   sharpmz core(
      .CLKMASTER      (clk_sys),
      .COLD_RESET     (reset),
      .WARM_RESET     (warm_reset),
      .PS2_KEY        (ps2_key),
      .IOCTL_DOWNLOAD (ioctl_download),
      .IOCTL_UPLOAD   (1'b0),
      .IOCTL_CLK      (clk_sys),
      .IOCTL_WR       (ioctl_wr),
      .IOCTL_RD       (ioctl_rd),
      .IOCTL_ADDR     (ioctl_addr),
      .IOCTL_DOUT     ({24'd0, ioctl_dout}),
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
      .IOCTL_DIN      (din32)
   );

   assign ioctl_din = din32[7:0];

   // Debug taps into the netlist; ghdl keeps register and port names.
   assign cpu_pc = core.cpu0.u0.pc;
   assign cpu_ce = core.clkgen0.ckencpui;
   assign cpu_m1_n = core.cpu0.u0.m1_n;
   assign dbg_sysreset = core.mz_system_reset;
   assign dbg_delay = core.ctrl0.delay;
   assign dbg_rm = core.ctrl0.reset_machine;
   assign dbg_warm = core.ctrl0.warm_reset;
   assign dbg_wait_n = core.t80_wait_n;
   assign dbg_vwait_n = core.video_wait_n;
   assign dbg_config = core.config_v;

   assign vram_q   = core.video0.vram0.mem[vram_addr];
   assign sysram_q = core.sysram.mem[sysram_addr];

endmodule

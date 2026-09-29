# SharpMZ → standard MiSTer core: TODO

Goal: make SharpMZ a normal MiSTer 8-bit computer core. That means a stock `sys/`, one PLL in `emu`, clock enables instead of derived clocks, native video through the framework scaler, and standard hps_io file handling, with no custom Main_MiSTer support.

Strategy: keep **v1 (this repo)** as the base for Phases 0–3. Use the author's **v2** code (`refs/tranZPUter`, GPLv3) as a per-module donor from Phase 4 on. v2 is not a drop-in replacement: it's built around a K64F management CPU (IOP bus, `iointr`) and a real host MZ-700 (`arbiter`, `cmt_hw`, host keyboard and sound), all of which would have to be stripped out.

## Current state

- [x] `sys/` is stock Template_MiSTer. It lags upstream only in `ascal.vhd`, `hps_io.sv` and `yc_out.sv`.
- [x] Core type is 0xA4 (standard). Main's `support/sharpmz/sharpmz.cpp` only runs for 0xA7, so it's inactive.
- [x] `sharpmz.sv` uses standard hps_io and CONF_STR.
- [x] References collected in `refs/` (gitignored; see `refs/README.md`): mz800emu, tranZPUter v2, sharpmz.net docs. `software/` (gitignored) holds the Waveform tape sets.
- [ ] Still non-standard: internal clocking, the config-register adapter, the in-core VGA upscaler and OSD, signal-as-clock logic, dead code, and tape save/queue/APSS.

## Decisions (2026-09-28)

- **Turbo:** 1A, cap turbo. One clk_sys of ~64–71 MHz with clean integer clock enables, max turbo ~28–35 MHz. Revisit full speed later only as an experiment.
- **MZ-800:** 2C, implement it using v2 (`mz80k_hw` bank switching, SN76489, VideoController graphics), verified against mz800emu.
- **Tape images:** 3A, ship a blank `.mzt` for now. Revisit an upstream Main PR (3C) later.
- **Video:** 4, adopt v2 `VideoController` (native timing only, rewired onto clk_sys CEs).
- **ROMs:** 5A, keep embedding the Sharp ROMs in the RBF (no change).
- **Clocks:** convert everything to clean clock enables on one clk_sys, integer dividers wherever possible.
- **Builds:** Quartus 17.0 in the Apple container (`~/dev2/apple-containers-example/scripts/quartus-core-apple.sh`).
- **Verification:** Verilator sim of the core, plus mz800emu extended with a matching headless CLI (branch `headless-cli` in `refs/mz800emu`).

## Phase 0: Baseline and verification harness

- [x] Build the current core and record resources, timing and fitter warnings. Build with `~/dev2/apple-containers-example/scripts/quartus-core-apple.sh /Users/alans/dev2/SharpMZ_MiSTer` (Quartus 17.0 in an Apple container; `QUARTUS_FIT_THREADS=8`).
- [ ] Capture reference screenshots and behaviour per model (80K, 80C, 1200, 80A, 700, 80B, 2000).
- [x] Simulation, following the VideoBrain_MiSTer pattern (`../VideoBrain_MiSTer/verilator`): `ghdl synth --out=verilog` → Verilator plus the shared ImGui/SDL `sim/` harness, graphical and headless.
  - [x] `sim.v` stands in for `sharpmz.sv` (ioctl ROM/MZF loading, ps2_key, video/audio capture).
  - [x] Sim-only replacements: the clock generator (altera_pll can't be simulated, so do the Phase 1 CE clkgen first, or a counter stub for the baseline) and the altsyncram `dpram`/`dprom` (inferred or Verilog RAM, with a MIF→hex script).
  - [x] GHDL flags: `-fsynopsys` (std_logic_unsigned/arith), `--work=pkgs` for the package files.
  - [x] Headless options: `--mzf`, `--type`, `--stop-at-frame`, `--screenshot`, `--ascii-end` (VRAM → text), `--frame-log` hash for regressions.
  - [ ] Pure-GHDL unit testbenches: CE generator done (`make test-clkgen`); still to do: `cmt.vhd` (pulse timings vs `refs/docs/sharpmz.net/mz700/tapeproc.md` and mz-archive `.wav`) and i8254. The Quartus `altera_mf.vhd` in the container install can supply the altsyncram models there.
- [ ] Test software set: `rtl/software/mzf/*.mzf` (ramtest, tapecheck, sharpmz-test, …) plus mz-archive `.mzf`/`.wav` pairs.
- [ ] WAV→MZF converter in `tools/`, based on mz800emu `src/libs/wav`, `mztape` and `cmt_stream`, for the Waveform sets in `software/` (MZ-700, MZ-2200).

## Phase 1: Clocks

Status: new `clkgen.vhd` (accumulator CEs, `CLK_HZ` = 70.9376 MHz) and the emu `pll` are in. Template SDC, old PLLs deleted, ioctl moved onto clk_sys. The MZ-700 boots to the monitor in simulation. Timing closes with no false paths. Hardware test pending.

- [x] Add a standard `pll` in `emu` for clk_sys and remove `rtl/clkgen.vhd`'s three chained PLLs (50 → 448 → 56.75 MHz …) and `rtl/pll*`/`rtl/submodules`.
  - Model the divider layout on v2 `emuMZ/clkgen.vhd` (one PLL at 127.9/113.5 MHz, register dividers, debug tree removed), but generate clock enables directly rather than sampling divided clocks.
- [x] Clock-enable generators (fractional where needed) running on clk_sys:
  - [x] CPU base: 2 MHz (80K/C/1200/80A), 3.546875 MHz (700/800), 4 MHz (80B/2000), plus turbo multiples.
  - [x] Pixel: 8 MHz, 8.867 MHz, 16 MHz, 17.734 MHz (80-column colour).
  - [x] Peripheral (2 MHz), sound (2 MHz / 895 kHz; 1.1 MHz for MZ-800 PSG), RTC (31.25 kHz etc.) for the i8254.
- [x] Remove the ripple-divider clocks and the debug clock tree (1 MHz … 0.1 Hz).
- [x] Convert logic that uses a signal as a clock into clk_sys edge detection:
  - [x] `video.vhd`: `falling_edge(T80_MREQ_n)`
  - [x] `mz80c.vhd`: `CURSOR_CLK`, `SOUND_PULSE_X2`, `CS_ESWP_n`
  - [x] `z8420/Interrupt.vhd`: `INTA`, `FETCH`, `INTR`; also `z8420.vhd`'s falling-edge register process moved to the rising edge
  - [x] i8254 `CLK0`/`CLK1` from `CKSOUND`/`CKRTC`: already edge-detected inside the i8254; now registered square waves on clk_sys
  - [x] ioctl logic moved from `IOCTL_CLK` onto clk_sys
- [ ] Fix the tape `PLAY_READY` "1 second" counter (hardcoded 32,000,000 cycles).
- [x] Rewrite `sharpmz.sdc` to the Template SDC.
- [x] Close timing. With the edge fixes, every domain meets setup/hold/recovery/removal/pulse width on the Template SDC (core clock +1.66 ns setup, +0.25 ns hold) and 0 clock-multiplexer warnings (baseline had 147). ALMs 11,182 (27%), RAM blocks 493/553 (89%), PLLs 3/6. Test RBF: `output_files/SharpMZ_standard-core_phase1.rbf`.
- [ ] PLL reconfiguration to 64 MHz for the MZ-80K/80A/80B family, so their 2/4/8/16 MHz enables are exact too (at 70.9376 MHz they are fractional, ±1 clock of jitter).

## Findings so far

- **Baseline build (master):** Quartus 17.0 crashes in synthesis (internal error in `sta_scc.cpp`) because of the old `sharpmz.sdc`. With that SDC emptied: 10,947 ALMs (26%), 3.94 Mbit block RAM (70%), 487/553 RAM blocks (88%), 5/6 PLLs, worst setup slack -25.8 ns (every domain fails). The qsf is identical to Template's.
- **MZ-700 sound pitch bug:** v1 fed the 8253 counter 0 about 1 MHz. The real clock is 1.1088 MHz (17.7344/16), so pitch was ~10% low. Fixed in the new clkgen.
- **MZ-80B RTC speed never selected:** `mctrl.vhd` tested `REGISTER_MODEL = "110" and REGISTER_MODEL = "111"`, which is always false. Fixed (`or`).
- **Reset one-shot:** `mctrl.vhd`'s `delay` counter only ended reset by wrapping 63→0; the `elsif delay >= 63` branch was unreachable. Fixed to stop explicitly at 63.
- **`DEBUG_ENABLE = 1`** in `config_pkg.vhd`: debug LED/sampling logic is in the release build. Remove in Phase 5.
- **VHDL conformance:** added `when others` to 19 case statements and `init_file => ""` for `null` (no behaviour change). Split `clkgen_pkg`/`mctrl_pkg` into their own files (circular dependency).
- **GHDL 5.1 bug:** `ghdl synth --out=verilog` drops port-alias assignments (`SIG <= in_port;` where SIG only feeds instances). `verilator/fix_port_aliases.py` restores them from the VHDL netlist. It hit the ioctl bus, ps2_key and the 8255/PIO keyboard inputs.
- **MZ-80B Z80 PIO interrupt never fires:** `z8420.vhd` connects `RST_n` (active low) to `Interrupt`'s active-high `RESET`, so the interrupt logic is held in reset during normal operation. Kept as-is (behaviour-preserving refactor); verify against MZ-80B software before enabling.
- **Tape lead-in:** the core plays the full 22,000-pulse long gap (~10–11 s, matching real hardware), so a `.mzf` loaded from the monitor takes ~1,050 frames. mz800emu generates a much shorter lead-in, so compare tape-load *results* rather than frame numbers. Check its option for a real-length gap.
- **Model coverage in simulation (after Phase 2 config change):** MZ-80K (SP-1002), MZ-80C (MZ_MONITOR 4.4), MZ-1200 (SP-1002), MZ-80A (SA-1510) and MZ-700 (1Z-013A) boot to their monitor prompts. MZ-80B shows "IPL is looking for a program" (correct). **MZ-2000 shows a black screen**: its ROM slot (0x17800) holds the MZ-80B IPL (`IPL.rom`), not a real MZ-2000 IPL. The CPU loops between 0038h and 1038h (RST 38h with the bank-swap bit toggling), and it counts only 33,280 T-states per frame (MZ-80B: 66,560 = 4 MHz at 60 Hz), so either its CPU runs at 2 MHz or its frame rate doubles. Check on hardware whether master behaves the same, and look at v2's MZ-2000 handling.
- **Tape record decoder never worked (MZ-700):** `cmt.vhd` sampled recorded pulses 1302 T-states after the rising edge, from the documented "368 µs read point". Measured in simulation and confirmed against the 1Z-013A listing, the monitor writes pulses with a 676 T-state (short) or 1300 T-state (long) high phase and reads its own tapes ~960–990 T-states after the edge. The documented µs figures assume 18 T-states per delay-loop iteration (`DEC A; JP NZ` is really 14). The sample landed at the very end of a long pulse, so every bit decoded as 0 and SAVE never produced a file. Now 988. mz800emu agrees on CPU timing (70,886.5 T-states/frame, no per-access wait states). Checked from the ROMs: SP-1002/SA-1510 (MZ-80K/80A) write 480/940 T-state pulses and sample at 681 T, so 736 is fine; the MZ-800 path (1020) also falls between the 1Z-013A pulse widths. **Still to check: the MZ-80B IPL (1020 @ 4 MHz, different tape format).**
- **MZ-2000 ran at 2 MHz:** `mctrl.vhd`'s CPU speed selection tested `= "110" or ... = "110"` (twice MZ-80B), so the MZ-2000 fell through to the 2 MHz default. Fixed in both branches; it now runs at 4 MHz.
- **Sim speed:** ~1.6M clk_sys cycles/s, about 1/44 real time. A 100-frame boot takes ~90 s.

## Phase 2: Config and I/O

Status: config bus and bridge removed; timing still closes (worst setup +0.54 ns on HDMI), 10,947 ALMs, 481/553 RAM blocks. Test RBF: `output_files/SharpMZ_standard-core_phase2.rbf`. MZ-700 tape load regression passes in simulation.

- [x] Remove the fake config bus (status → ioctl writes to 0x1000000+ in `sharpmz.sv`) and wire OSD status straight into the `mctrl` CONFIG vector. `mctrl` now takes `CFG_*` inputs; model/display/boot-reset changes reset the machine via change detection. The Main-era read-back registers (CMT2 APSS status, READ_STATUS, registers 10–12, debug registers) are gone; Phase 3 redoes APSS in the core.
- [x] Remove `bridge.vhd` (STORM/NEO430 remnants) and instantiate `sharpmz` directly. Also removed `jtag_uart_0`, `sysid`, `spi_master`.
- [ ] ROM, keymap and CGROM loading through standard ioctl indexes. Defaults depend on the embedded-ROM decision.
- [ ] Direct-to-RAM MZF load: behaves like the legacy driver (program in RAM, run it with the monitor's `J` command). Optional: auto-run via keyboard injection or a CPU jump. Verify in simulation.
- [x] Rename the "Map Header" OSD option to what it does (now "Sharp ASCII Name"): Sharp ASCII ↔ ASCII filename conversion (`CMTASCII_IN`/`OUT`).
- [x] Expose audio source (status[20]) in the OSD (Tape page: Sound / Tape).

## Phase 3: Tape (restore what the legacy Main driver did)

Status: tape image slot working in simulation. Loading from an MZT runs the program and queues the next record; the monitor's SAVE writes a byte-exact MZF into a blank image. Timing closes (core clock +1.93 ns); 11,687 ALMs, 482/553 RAM blocks. Test RBF: `output_files/SharpMZ_standard-core_phase3.rbf`.

The old `sharpmz.cpp` handled save, a 5-entry tape queue and MZ-80B APSS. The core's `cmt.vhd` still decodes records into header + data (= MZF), but nothing reads it now. v2's `cmt.vhd` doesn't help here: it hands file I/O to its management CPU through interrupts.

- [ ] Keep `F` quick-load of `.mzf` to CMT and direct-to-RAM.
- [x] Add an `S` tape-image slot (`MZF MZT`), CoCo2/3 style: `rtl/tape_image.sv`, OSD Tape page "Tape Image" (S0) and "Rewind Tape Image" (T[31]).
  - [x] **Load:** mounting copies the first record into the CMT buffer. When the CMT drops PLAY_READY after playing (motor stopped), the next record follows, which replaces the old 5-entry queue.
  - [x] **Save:** on `RECORD_READY` the header and data are read back from the CMT buffer and appended after the last record. Sector writes go through a one-sector write-back cache. If the image is read-only or too small, the save is skipped and `tape_full` is set.
  - [x] **MZ-80B/2000 APSS:** seek forward/back moves one record (8-deep history for back); eject rewinds.
  - [x] **OSD:** Rewind. LED_DISK shows tape image access and CMT activity.
  - [ ] Show tape status (record number, tape full) somewhere visible, e.g. the OSD info line.
- [x] Blank tape image: `tools/make_blank_tape.py` (zero-filled; a zero attribute byte marks the end of the tape). Document it in the README.
- [x] Park the core download bus on an unused address when idle. `cmt.vhd` clears RECORD_READY whenever the address points at its buffers, and after an OSD tape download the address used to stay there, so recordings could be lost on hardware too.
- [x] Verify SAVE from the monitor (MZ-700, `S120012FF1200`): the image holds a correct MZF (attribute, name, load/exec, and data identical to RAM).
- [x] Verify reload of a saved tape: mounting the image written by SAVE and typing `L` prints `LOADING TEST`, loads without a checksum error and auto-runs it. (The RAM init MIF preloads the author's SHARPMZ TESTER at 1200h, so that's what the saved bytes contained.)
- [ ] Verify SAVE from BASIC, MZ-80K/80A/80B saves, and APSS on the MZ-80B.
- [ ] MZ-80K: `LOAD` of `3-D MAZE.MZF` reads the header and data (no checksum error) and runs it, but the screen afterwards looks like garbage (`verilator/out/tape/k_load`). Check against real hardware or an MZ-80K emulator; it may just be the program's start-up screen.
- [ ] Check the playback waveform against mz-archive `.wav` recordings.

## Phase 4: Video

Detailed port plan: `docs/video-port-plan.md` (clock domains, decode hazards, what to strip, BRAM budget, step order).

Status: the v2 VideoController is in (`rtl/vc/`, selected by `VIDEO_V2 = 1` in `config_pkg.vhd`; v1 `video.vhd` is still there for comparison).
- Clocks: both video PLLs, the FFCLK switch and the gated `VID_CLK` are gone. Everything runs on `SYS_CLK` with a `VID_CE` enable at 2x the dot clock chosen by `CLOCKSEL`; `CE_PIXEL` is exported.
- RAMs: `rtl/vc/vc_rams.vhd` rebuilds the v2 RAM entities on `rtl/dpram`. The CG ROM is v1's 32 KB `combined_cgrom.mif`, banked per model and loaded over ioctl at 0x500000. The palette RAMs are replaced by a fixed LUT (on/off, MZ-800 IRGB).
- Fixes to v2: 50 Hz timing rows restored (568/1136 x 312), with a `VIDEO_50HZ` input (MZ-700/800) replacing the management CPU's mode register. The config is applied after reset (it was skipped when the model didn't change after reset), and the 80-column/colour flags follow the config instead of toggling.
- Wrapper `rtl/vc/video_vc.vhd`: CONFIG translation to the v2 layout, MREQ gated by the machine's decode, v1 VRAM wait states.
- Verified in simulation: MZ-80K/80C/1200/80A/700 boot tests pass. MZ-700 is 50 Hz (70,886 T-states per frame, same as v1 and mz800emu); MZ-80A is green mono; the MZ-80B IPL screen renders.
- Quartus: timing closes on every domain (core clock +1.80 ns after removing the OSD-size dividers and the A0–BF controller registers). 12,310 ALMs, 403/553 RAM blocks (was 482). After removing v1: 12,329 ALMs, 403/553 RAM blocks, core clock +2.61 ns. Test RBF: `output_files/SharpMZ_standard-core_phase4.rbf`.
- Done since:
  - **v1 removed:** `video.vhd` deleted, the "Video Timing" OSD option removed (native only), and the unused pixel enable removed from clkgen.
  - **Read path:** the controller's emulator-mode read path now follows the data while RD is active; it used to latch once, 4 clocks in, which races the CPU at turbo speed.
  - **Unreachable host logic left in place:** GPU, OSD buffers, palette registers, VGA/composite paths. With the A0–BF registers disabled and no direct addressing, Quartus removes them (VideoController: 1,120 ALMs, 84 M10K). Keeping the text close to upstream makes it easier to pick up the author's future fixes.
  - **MZ-80B/2000 decode kept as v2 had it:** VideoController snoops the PPI/PIO writes while the core's own 8255/Z80 PIO models run, the same arrangement as the author's v2 emulator build. MREQ is still gated by the machine decode.
  - **Framebuffer graphics extension dropped for now:** the author's add-on bitmap graphics for the MZ-700/80A (v1: I/O ports 00–07 by default; v2: B8–BD). It's not original Sharp hardware and v1's default ports could clash with expansion hardware. It could come back on v2's ports as an OSD option.
- [ ] Verify the MZ-80B GRAM and 40/80 column switching with real MZ-80B software (none available in `software/` yet).
- [ ] MZ-2000 colour GRAM (C000–FFFF) isn't in v1's memory decode, so the MREQ gate blocks it; fix together with the MZ-2000 IPL.

- [ ] **Evaluate v2 `VideoController`** before investing in v1 `video.vhd`:
  - [ ] Port its native timing tables (MONO40/80, COLOUR40/80 at 60 Hz and 50 Hz) and the character/graphics/OSD layered renderer.
  - [ ] MZ-80B 320x200 and MZ-2000 640x200 GRAM (complete in v2).
  - [ ] Replace its host-bus I/O ports (0xA0–0xBF) and own PLLs with CEs on clk_sys.
  - [ ] Check BRAM fit on the Cyclone V 5CSEBA6 (v2 targets the EP4CE75/115).
- [ ] Output native machine timing only, with a regular `CE_PIXEL` and correct blanking.
- [ ] Remove the in-core 640x480/800x600 modes and the `Video Timing` option.
- [ ] Remove the legacy menu and status framebuffers (`FB_ADDR_MENU`/`FB_ADDR_STATUS`, 0x320000/0x322000).
- [ ] Use `video_mixer` (scandoubler, `VGA_SL` scanlines, `forced_scandoubler`) and `video_freak` (aspect, integer scaling).

## Phase 5: Cleanup and polish

- [x] `DEBUG_ENABLE = 0` (debug LED/sampling logic out of the build).
- [x] OSD cleanup: removed the PCG ROM/RAM option (software controls the PCG via E010–E012; the config bit collided with v2's blend register) and the unused `J,Fire`; config version bumped to 5.
- [x] Delete dead RTL: i8253/, mz80b FDC/video/misc files, mz80c cmt/video, unused T80 variants, clk_div, memory_hw.tcl; files.qip lists only what's built.
- [x] Update `sys/` to the latest Template_MiSTer (identical to upstream 3ea1134, Aug 2026).
- [x] Audio level: the 1-bit output drove AUDIO_L/R at full scale signed (0 / −32768). Now unsigned half scale, centred by the framework's DC blocker.
- [ ] Audio mixing (sound + tape together, volume), v2 `snd.vhd` style, and the MZ-800 PSG later.
- [ ] Keyboard (waiting for hardware feedback): adopt v2 `keymatrix.vhd` per-model maps (MZ-80K, MZ-2000, …) in place of the ROM-loaded keymap, keeping a PS/2 path only.
- [ ] Joystick mapping (currently `J,Fire` only), `LED_DISK` on tape activity.
- [x] README rewrite: models and status, menu, tape image and saving, known issues, design, build/sim.
- [ ] Release RBF `releases/SharpMZ_YYYYMMDD.rbf` after hardware testing.

## Phase 6: Verification

- [ ] Timing closes with no blanket false paths.
- [ ] Simulation regression: boot each model, compare against the Phase 0 baseline.
- [ ] MZ-700/800 behaviour against `refs/mz800emu` (CPU timing, 8253 sound, video).
- [ ] Hardware test per model: boot, keyboard, MZF load, tape save/reload, sound, 40/80 columns, turbo speeds.

## Later: v2 donor features

- [ ] **Floppy:** v2 `fdd.vhd` + `wd1793.vhd` (MB8866/WD1773). It caches one sector and has its management CPU fetch sectors, which maps onto hps_io `S` slots (`sd_lba`/`sd_rd`/`sd_wr`). Covers the MZ-80B/2000 and MZ-700/800 FD units.
- [ ] **MZ-800** (plan: `docs/mz800-plan.md`). The machine logic is written in v1's `mz80c.vhd` following mz800emu; v2's `mz80k_hw.vhd` is used as a reference only.
  - [x] Clocks: MZ-700 CPU (70,886.5 T/frame, same as mz800emu) and sound clocks.
  - [x] 16 KB ROM (1Z-013B, CG, IPL/9Z-504M from mz800emu) at 0x1C000 of the combined ROM; MZ-800 CG in the CG ROM slot (`tools/add_mz800_rom.py`).
  - [x] Memory map register, bank ports E0-E6 with the IN side effects, 700/800 mode maps, E000-E00F ports / 1A / FF, prohibited mode, D0-D7 in 800 mode, IN CE status, rear mode switch on the OSD.
  - [x] IPL screen and 9Z-504M monitor match mz800emu (tests `boot_mz800`, `mon_mz800`).
  - [x] 320x200 graphics planes and palette match mz800emu (`gfx_mz800`). Colours use mz800emu's palette.
  - [x] SN76489 PSG at F2 on a fixed 3.547 MHz enable, mixed into the 16-bit audio (`psg_mz800`, 439.8 Hz).
  - [x] 700 mode CG-RAM at C000 (PCG), read/write (`pcg_mz800`).
  - [x] Tape loading from the IPL (`C`) runs ramtest as mz800emu does (`tape_mz800`). The CMT had been using MZ-80B timings for the MZ-800.
  - [x] Rear mode switch: bit 1 of IN CE = 1 is MZ-800 (the IPL switches to MZ-800 graphics before starting a loaded program). Default MZ-700, as mz800emu.
  - [x] 640x200 (2 and 4 colours), 320x200 frame B and 16 colours (MZ-1R25 VRAM expansion on, as mz800emu), all write modes (SINGLE/EXOR/OR/RESET/REPLACE/PSET), RF reads and colour search, hardware scroll: all match mz800emu (`tests/mz800/compare_emu.sh`, `m800_*` tests). Fixed on the way: frame gating in SINGLE/EXOR/OR/RESET, 640x200 plane III render for the first bank, 16-colour palette index, frame A colour search, and the half-word read in `vc_rams` (a v2 bug too).
  - [ ] Border colour (CF register 6): the core outputs only the 320x200/640x200 area, so the border isn't visible.
  - [ ] Z80 PIO at FC-FF (interrupts, printer), joystick reads (F0/F1 return FF).
  - [ ] VideoController IN CE read returns the mode register (not used: the machine side answers CE reads).
  - [ ] Real software: run MZ-800 titles from `software/`.
  - [x] All v2 video modes lost the leftmost pixel (horizontal blank started at count 1); the 40/80 column rows now start at 0.
- [ ] **MZ-1500, MZ-2200:** config slots exist in v2 (dual PSG on the MZ-1500; the MZ-2200 is MZ-2000-family).
- [ ] Machine options from v2 `mctrl`: RAM installed, GRAM I/II/III, PCG, MZ-1R25.
- [ ] Remove `support/sharpmz/` from Main_MiSTer upstream once no 0xA7 builds are in use.

## References

See `refs/README.md`: sharpmz.net docs (`refs/docs/sharpmz.net/INDEX.md`), `refs/mz800emu`, `refs/tranZPUter` (v2; live design in `FPGA/SW700/v1.3/MZ700/emuMZ/*.vhd`, `VideoController/`, `coreMZ_emuMZ.vhd`; `emuMZ/common/` is stale v1), mz-archive.co.uk, `software/` Waveform sets, Main `sharpmz.cpp`, and the CoCo2/CoCo3 `Cassette_Write.sv`.

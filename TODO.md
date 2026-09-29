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
- [ ] Check the playback waveform against mz-archive `.wav` recordings.

## Phase 4: Video

Detailed port plan: `docs/video-port-plan.md` (clock domains, decode hazards, what to strip, BRAM budget, step order).

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

- [ ] Delete dead RTL: `jtag_uart_0`, `sysid`, `spi_master`, `i8253/`, `mz80c/cmt.vhd`, `mz80c/mz80c_video.vhd`, unused `mz80b/` FDC files, `mz80b_dummy`, unused T80 variants, and `DEBUG_ENABLE` blocks. Trim `files.qip`.
- [ ] Update `sys/` to the latest Template_MiSTer.
- [ ] Audio: replace the 1-bit output with v2 `snd.vhd`-style mixing (volume, channel blend, sound + tape audio) into the 16-bit `AUDIO_L/R`.
- [ ] Keyboard: adopt v2 `keymatrix.vhd` per-model maps (MZ-80K, MZ-2000, …) in place of the ROM-loaded keymap, keeping a PS/2 path only.
- [ ] Joystick mapping (currently `J,Fire` only), `LED_DISK` on tape activity.
- [ ] README rewrite (menu, tape usage, ROMs, blank tape); release naming `SharpMZ_YYYYMMDD.rbf`.

## Phase 6: Verification

- [ ] Timing closes with no blanket false paths.
- [ ] Simulation regression: boot each model, compare against the Phase 0 baseline.
- [ ] MZ-700/800 behaviour against `refs/mz800emu` (CPU timing, 8253 sound, video).
- [ ] Hardware test per model: boot, keyboard, MZF load, tape save/reload, sound, 40/80 columns, turbo speeds.

## Later: v2 donor features

- [ ] **Floppy:** v2 `fdd.vhd` + `wd1793.vhd` (MB8866/WD1773). It caches one sector and has its management CPU fetch sectors, which maps onto hps_io `S` slots (`sd_lba`/`sd_rd`/`sd_wr`). Covers the MZ-80B/2000 and MZ-700/800 FD units.
- [ ] **MZ-800:** v2 `mz80k_hw.vhd` bank switching (ROM/RAM/CG/VRAM enables), `sn76489_audio` PSG and joystick strobes; plus MZ-800 graphics modes (check VideoController coverage). Verify against mz800emu.
- [ ] **MZ-1500, MZ-2200:** config slots exist in v2 (dual PSG on the MZ-1500; the MZ-2200 is MZ-2000-family).
- [ ] Machine options from v2 `mctrl`: RAM installed, GRAM I/II/III, PCG, MZ-1R25.
- [ ] Remove `support/sharpmz/` from Main_MiSTer upstream once no 0xA7 builds are in use.

## References

See `refs/README.md`: sharpmz.net docs (`refs/docs/sharpmz.net/INDEX.md`), `refs/mz800emu`, `refs/tranZPUter` (v2; live design in `FPGA/SW700/v1.3/MZ700/emuMZ/*.vhd`, `VideoController/`, `coreMZ_emuMZ.vhd`; `emuMZ/common/` is stale v1), mz-archive.co.uk, `software/` Waveform sets, Main `sharpmz.cpp`, and the CoCo2/CoCo3 `Cassette_Write.sv`.

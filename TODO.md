# SharpMZ standard core: status and TODO

Goal: SharpMZ as a normal MiSTer 8-bit computer core. It has a stock `sys/`, one PLL, clock enables in place of derived clocks, native video through the framework scaler, and standard hps_io files. Main_MiSTer needs no Sharp-specific support. Branch `standard-core` on `alanswx/SharpMZ_MiSTer`.

Design notes are in `docs/design.md`, and the simulation and tests in `verilator/README.md`.

## Status

| Area | State |
|---|---|
| Framework | Done. Stock Template_MiSTer `sys/`, core type 0xA4, standard CONF_STR and hps_io with image slots S0 (tape) and S1/S2 (floppy). Main's `support/sharpmz` (0xA7) is unused. |
| Clocks | Done. One 70.9376 MHz clk_sys with accumulator clock enables (`rtl/clkgen.vhd`); no signal-as-clock logic. Turbo is capped at clk_sys/2. |
| Video | Done. The author's v2 VideoController on clk_sys (`rtl/vc/`), native timing only (MZ-700/800 50 Hz, the others 60 Hz), scaled by the framework. |
| Tape | Done. MZF to CMT, direct to RAM, and a Tape Image slot (`rtl/tape_image.sv`) that loads multi-program MZTs, saves into a blank image and does MZ-80B APSS. |
| MZ-80K/80C/1200/80A/700 | Working in simulation. MZ-700 is also tested on hardware. |
| MZ-800 | Working in simulation against mz800emu: IPL, 9Z-504M monitor, memory map, MZ-700/800 modes, all graphics modes, PSG, Z80 PIO, tape, floppy and CP/M. 12 native games and 84 of 94 disk images match mz800emu. |
| Floppy | MZ-700/800 interface (`rtl/mz_fdc.sv`) with two drives from Extended DSK images. CP/M 1.3, 1.4, 2.3 and 4.1 boot in simulation. MZ-700: the MZ-1E05 ROM at F000 comes with the interface; `J F000` boots a disk made by `tools/make_boot_disk.py`. MZ-80B: the IPL boots SB-6511 Disk BASIC and CP/M 2.2 from the idealine.info images. |
| MZ-80B | Boots to the IPL; little software tested. |
| MZ-2000 | Not working: no MZ-2000 IPL ROM. |
| FPGA | Latest build meets timing (core clock +2.0 ns): 17,965 ALMs (43%), 434/553 RAM blocks. |
| Regression | `make test`: 23 tests plus 2 disk tests (see `verilator/README.md`). All pass. |

## Open work

### Next
- [ ] Hardware test of the current build: the MZ-800 (graphics tests, PSG, tape from the IPL) and the floppy (CP/M 4.1).
- [ ] Floppy writes: copy a file on a writable image and check it in mz800emu; drive B; turbo speeds.
- [ ] 8253: the CP/M 1.x loader waits for counter 2's first clock (the first 1 s pulse of counter 1): about 1 s here, as the 8253 datasheet gives, and 2 s in mz800emu. Only the boot pause differs; confirm on hardware.

### MZ-800
- [ ] Border colour (CF register 6): only the 320x200/640x200 area is output.
- [ ] Joysticks (F0/F1 read FF), printer port.
- [ ] RAM disk board (ports E8-EF, CP/M drive E:).
- [ ] 1.44 MB disk images (`_Vzor144`, `_Vzor_Nova`): `wd1793.sv` addresses 1 MB.
- [ ] Turbo-loader tapes (header types 00/08/76, exec below the load address).

### Other models
- [ ] MZ-700 floppy on hardware; MZ-2Z009 Disk BASIC (loads from tape) on a blank disk.
- [ ] MZ-2000 floppy: the interface is enabled, but the MZ-2000 model has no IPL to boot it; try the MZ-2200 IPL (`software/idealine/mz-2x00/mz2200ipl`).
- [ ] MZ-80B SB-7010 (DISK29) loads and stops at its monitor's `*` prompt; find out how FDOS is started from there.
- [ ] wd1793: EDSK sector error flags (ST1/ST2) are ignored, so a sector dumped with a CRC error reads as good data. DISK37/38 are bad dumps: the IPL loads corrupt code and hangs instead of reporting a loading error.
- [ ] MZ-80K/80A floppy interface ROMs and the SA-6510 boot disk (`software/idealine/`).
- [ ] MZ-2000: needs a real IPL ROM dump, then its colour GRAM (C000-FFFF) in the memory decode.
- [ ] MZ-80B: GRAM and 40/80 column switching with real software; SAVE and APSS.
- [ ] MZ-80A (probably 80K/1200 too): the cursor keys type 4/6/8/2 and Backspace types `/`. It needs the MZ-80A key matrix.
- [ ] MZ-80K: 3-D MAZE loads and runs but the screen looks garbled; check whether that's the program.

### Core and polish
- [ ] Audio mixing: sound and tape together, volume.
- [ ] Joystick mapping in the OSD.
- [ ] Show tape status (record number, tape full) in the OSD.
- [ ] Tape PLAY_READY "one second" counter is hard-coded to 32,000,000 cycles.
- [ ] Optional 64 MHz clock for the MZ-80K/80A/80B family, so their clock enables are exact (±1 clk_sys jitter now).
- [ ] Unit testbenches for `cmt.vhd` and the i8254.
- [ ] WAV to MZF converter for the Waveform sets in `software/`.
- [ ] Release RBF `releases/SharpMZ_YYYYMMDD.rbf` after hardware testing.
- [ ] Later: MZ-1500 and MZ-2200 models, v2 machine options (RAM size, GRAM, MZ-1R25), and removing `support/sharpmz/` from Main_MiSTer.

## Known issues
- Changing the model doesn't reset MZ-800 characters redefined through C000; the IPL restores the font on the next boot.
- The author's framebuffer graphics extension (bitmap graphics for the MZ-700/80A) isn't included.

## Hardware test log
- **2026-09-29, MZ-700:** Galactic Invaders loads from tape and plays (SHIFT fires, SPACE pauses as the game intends). This found the keymap bugs fixed in `cbb1c04`.

## Bugs found and fixed
Each has a commit; this list is for context.
- **MZ-700 tape record decoder:** never decoded (sample point 1302 T; the monitor reads at ~990 T), so SAVE never produced a file.
- **MZ-700 sound pitch:** ~10% low (8253 clock 1 MHz instead of 1.1088 MHz).
- **ROM banks:** the User ROM (E800) and FDC ROM (F000) banks were never selected (the monitor clauses caught those addresses first), and the MZ-2000's banks were decoded as a second MZ-80B set.
- **mctrl:** MZ-80B RTC speed never selected; MZ-2000 ran at 2 MHz; the reset one-shot only ended by wrapping.
- **GHDL 5.1** drops port-alias assignments in Verilog output (`verilator/fix_port_aliases.py`).
- **v2 VideoController:**
  - wrong 50 Hz timing rows;
  - leftmost pixel lost;
  - MZ-800 frame gating in the write modes;
  - 640x200 plane III;
  - 16-colour palette index;
  - frame-A colour search;
  - half-word RAM read (also in the author's v2).
- **Keyboard:** extended keys never reached their keymap entries; MZ-700 map errors (4 typed C, missing keys).
- **Floppy:** `wd1793.sv` Force Interrupt status.
- **i8255:** a mode set didn't clear the outputs, so CP/M 1.x on the MZ-800 took endless 8253 interrupts.
- **wd1793.sv:** an EDSK image with an unformatted track before the first formatted one was never parsed.
- **VideoController:** 640x200 hardware scroll overflowed 14 bits with large offsets, so CP/M 4.1 drew text over itself after scrolling a while.

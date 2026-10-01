# SharpMZ standard core: status and TODO

Goal: SharpMZ as a normal MiSTer 8-bit computer core. It has a stock `sys/`, one PLL, clock enables in place of derived clocks, native video through the framework scaler, and standard hps_io files. Main_MiSTer needs no Sharp-specific support. Branch `standard-core` on `alanswx/SharpMZ_MiSTer`.

Design notes are in `docs/design.md`, and the simulation and tests in `verilator/README.md`.

## Status

| Area | State |
|---|---|
| Framework | Done. Stock Template_MiSTer `sys/`, core type 0xA4, standard CONF_STR and hps_io with image slots S0 (tape) and S1/S2 (floppy). Main's `support/sharpmz` (0xA7) is unused. The tape and floppy entries are on the OSD's first page so MGL files can load them. |
| Clocks | Done. One 70.9376 MHz clk_sys with accumulator clock enables (`rtl/clkgen.vhd`); no signal-as-clock logic. Turbo is capped at clk_sys/2. |
| Video | Done. The author's v2 VideoController on clk_sys (`rtl/vc/`), native timing only (MZ-700/800 50 Hz, the others 60 Hz), scaled by the framework. |
| Tape | Done. MZF to CMT, direct to RAM, and a Tape Image slot (`rtl/tape_image.sv`) that loads multi-program MZTs, saves into a blank image and does MZ-80B APSS. |
| MZ-80K/80C/1200/80A/700 | Working in simulation. On hardware: all boot; MZ-700 tape and floppy (`J F000`) work. |
| MZ-800 | Working in simulation against mz800emu: IPL, 9Z-504M monitor, memory map, MZ-700/800 modes, all graphics modes, PSG, Z80 PIO, tape, floppy and CP/M. 12 native games and 84 of 94 disk images match mz800emu. On hardware: graphics tests, games from tape images (Cauldron II, Cybernoid), CP/M games from disk. |
| Floppy | MZ-700/800 interface (`rtl/mz_fdc.sv`) with two drives from Extended DSK images. CP/M 1.3, 1.4, 2.3 and 4.1 boot in simulation. MZ-700: the MZ-1E05 ROM at F000 comes with the interface; `J F000` boots a disk made by `tools/make_boot_disk.py`. MZ-80B: the IPL boots SB-6511 Disk BASIC and CP/M 2.2 from the idealine.info images. |
| MZ-80B | Boots the IPL; loads SB-5520 BASIC from a tape image and SB-6511 Disk BASIC / CP/M 2.2 from floppy (sim and hardware). |
| MZ-2000 | Real IPL (MAME mz20ipl.bin) and MZ-2000 character ROM with katakana (MAME font.bin, hand-made, BAD_DUMP). Loads Gang Man and Zero Fighter (colour) from tape and boots a TF-DOS D88 disk with Japanese text, in the sim and on hardware. |
| FPGA | Latest build (b4004ff) meets timing (core clock +2.2 ns): about 17,600 ALMs (42%), 434/553 RAM blocks. Built on cottageubuntu (Quartus 17.0.2). |
| Regression | `make test`: 23 tests plus 2 disk tests (see `verilator/README.md`). All pass. |

## Open work

### Next
- [ ] Sound tests for the other models: MZ-80K/80A note table (does the MZ-80K need the counter 0 divide-by-2?), MZ-800 PSG channels and noise, beeper vs PSG level (mz800emu mixes them equally; ours is 4x louder), MZ-80B/2000 PC2.
- [ ] Tape saves into a growing image instead of a pre-made blank tape: needs a Main change, proposed in `docs/main-growable-images.md` (with an RTL-only alternative through Main's save files).
- [ ] Astro1: mz800emu rings the monitor bell (6 frames of 880 Hz) when the game restarts the monitor; the sim shows only the PC0 step. beep_mz800 shows the path works, so check the game's timing.
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
- [ ] MZ-2000: MZ-80B CP/M (DISK01) on the MZ-2000 stays black; recheck now that NST resets the CPU.
- [ ] MZ-2000 character ROM is MAME's hand-made font.bin; a real dump of the IX0286PA (also the Japanese MZ-80B font) would replace it.
- [ ] More MZ-2000 tapes from `software/mz2200` (Super Doors, Itasandrias, Project A, ...); Ice Block's MZT is malformed.
- [ ] MZ-80B SB-7010 (DISK29) loads and stops at its monitor's `*` prompt; find out how FDOS is started from there.
- [ ] wd1793: EDSK sector error flags (ST1/ST2) are ignored, so a sector dumped with a CRC error reads as good data. DISK37/38 are bad dumps: the IPL loads corrupt code and hangs instead of reporting a loading error.
- [ ] MZ-80K/80A floppy interface ROMs and the SA-6510 boot disk (`software/idealine/`).
- [ ] MZ-2000: its colour GRAM (C000-FFFF) in the memory decode; a real MZ-2000 IPL dump if one turns up.
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
- **2026-09-30, all models (`tools/mister_test.py`):** T01-T06 boot screens correct on every model (MZ-2000 on the MZ-2200 IPL). T07 MZ-700 tape, T08 MZ-700 floppy, T09/T10 MZ-800 graphics tests pass. T11/T12 MZ-800 games load from tape images (Cauldron II, Cybernoid) after the tape image fix. The user played MZ-800 CP/M games from disk (sound fixed in `11f2d8b`). T13-T18 on b4004ff: MZ-800 CP/M 4.1 (DIR), CP/M 1.3 and the Hry file manager boot from floppy; MZ-80B boots SB-6511 Disk BASIC and CP/M 2.2; the MZ-2000 loads MZ-80B CP/M and stays blank, as in the sim. T19/T20 play the BELL and 440 Hz tone (by ear).
- **2026-10-01, MZ-80B/2000 (clean build 9b9001e):** T21 MZ-80B SB-5520 BASIC from tape, T22 Gang Man, T23 TF-DOS D88 with katakana, T24 Zero Fighter in colour. All match the sim.

## Bugs found and fixed
Each has a commit; this list is for context.
- **MZ-80B/2000 NST:** PC1 going high must reset the CPU (the IPL's jump into RAM); the core carried on at 0008 inside the loaded program (Zero Fighter crashed).
- **Stale FPGA ROM contents:** a Quartus incremental build kept the old character ROM after only the MIF changed; builds are now clean (`rm -rf db incremental_db`).
- **MZ-80B/2000 tape never played:** GHDL lost the CMT state process's writes to CMT_BUS_OUTi (the vector was split between the process and concurrent assignments), so the APSS deck never left reset; and the deck needed PLAY high with STOP low, which the MZ-2200 IPL never does. Now registered bits and edge-triggered commands, as MAME.
- **Tape image hang (hardware):** mounting a tape image froze Main (F12 dead, reboot needed). `ioctl_wait` was tied to the tape engine and holds the whole HPS link, so Main could not serve the engine's sector reads. The engine now yields to downloads instead.
- **OSD/MGL:** MGL files can only load F/S entries on the first OSD page; ours were on sub-pages, so every MGL with a tape or disk was dropped.
- **MZ-700/800 sound:** the beeper played an octave low (a divide-by-2 meant for the MZ-80K's 2 MHz clock), and on the MZ-800 counter 0's gate was forced on in 800 mode, so games that switch modes (Astro Marine Corps) clicked.
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

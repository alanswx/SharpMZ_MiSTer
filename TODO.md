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
| MZ-1500 | New (from mz800emu's MZ-1500): 9Z-502M ROMs, PCG (3 planes, palette, priority), 2 PSGs in stereo, Z80 PIO, Quick Disk (`rtl/mz_qdisk.sv`, .qdf/.mzq, read and write). Boots to the IPL and loads Lode Runner from Quick Disk with its PCG title screen pixel-identical to mz1500emu. On hardware: Lode Runner, Nintendo Tennis, and two-sided Battle City, Grobda, Milky Way and Batten Tanuki (side B swapped by the MGL) reach their title or demo; MZ-5Z001 BASIC formats a Quick Disk, saves, loads and runs a program (W01); 8 Quick Disk titles archived as two tapes run from disks made by `tools/mzf2qdf.py` (G01-G08). |
| Floppy | MZ-700/800 interface (`rtl/mz_fdc.sv`) with two drives from Extended DSK images. CP/M 1.3, 1.4, 2.3 and 4.1 boot in simulation. MZ-700: the MZ-1E05 ROM at F000 comes with the interface; `J F000` boots a disk made by `tools/make_boot_disk.py`. MZ-80B: the IPL boots SB-6511 Disk BASIC and CP/M 2.2 from the idealine.info images. |
| MZ-80B | Boots the IPL; loads SB-5520 BASIC from a tape image and SB-6511 Disk BASIC / CP/M 2.2 from floppy (sim and hardware). |
| MZ-2000 | Real IPL (MAME mz20ipl.bin) and MZ-2000 character ROM with katakana (MAME font.bin, hand-made, BAD_DUMP). Loads Gang Man and Zero Fighter (colour) from tape and boots a TF-DOS D88 disk with Japanese text, in the sim and on hardware. |
| FPGA | Latest build (fdb8de9, clean) meets timing (core clock +1.7 ns): about 18,300 ALMs (44%), 65% of block memory bits. Built on cottageubuntu (Quartus 17.0.2); always clean-build (`rm -rf db incremental_db`). |
| Regression | `make test`: 36 tests (34 plus ipl_mz1500 and qd_mz1500), including disk and tape tests that need `software/` (see `verilator/README.md`). All pass. Hardware suite: `tools/mister_test.py`, 57 MGL tests (T01-T26, Q01-Q05, B01-B04, C01-C12, W01-W02, G01-G08). |

## Open work

### Next
- [ ] Sound tests for the other models: MZ-80K/80A note table (does the MZ-80K need the counter 0 divide-by-2?), MZ-800 PSG channels and noise, MZ-80B/2000 PC2.
- [x] Beeper vs PSG level: on the MZ-800/1500 the beeper is now one PSG channel's level, as mz800emu mixes them; full range on the models without a PSG.
- [ ] Tape saves into a growing image instead of a pre-made blank tape: needs a Main change, proposed in `docs/main-growable-images.md` (with an RTL-only alternative through Main's save files).
- [ ] Astro1: mz800emu rings the monitor bell (6 frames of 880 Hz) when the game restarts the monitor; the sim shows only the PC0 step. beep_mz800 shows the path works, so check the game's timing.
- [ ] Floppy writes: copy a file on a writable image and check it in mz800emu; drive B; turbo speeds.
- [ ] 8253: the CP/M 1.x loader waits for counter 2's first clock (the first 1 s pulse of counter 1): about 1 s here, as the 8253 datasheet gives, and 2 s in mz800emu. Only the boot pause differs; confirm on hardware.

### MZ-800
- [ ] Border colour (CF register 6): only the 320x200/640x200 area is output. VideoController can draw a border (display window inside a wider display area), but widening the area moves the canvas within the line and changes every MZ-700/800 frame hash: do it behind an OSD option (mz800emu: 154/134 pixels left/right in 640 mode, 46/42 lines top/bottom).
- [x] Joysticks: ports F0/F1 read MiSTer joysticks 1/2 while 8255 PA5/PA6 strobe them (mz800emu's bit layout). Not yet tried with software.
- [ ] Printer port.
- [x] RAM disk board: the 64 KB "standard" board of mz800emu (EA/EB, F8-FA; OSD MZ-800 RAM Disk). Not yet tried with CP/M; the Pezik boards (E8, EC-EF) and larger sizes aren't implemented.
- [ ] 1.44 MB disk images (`_Vzor144`, `_Vzor_Nova`): `wd1793.sv` addresses 1 MB.
- [ ] Turbo-loader tapes: 66 MZ-800 games have exec 1108, a loader in the MZF header's comment area (loaded at 10F0) that reads the body itself; most other unusual types are later parts of multi-part games. Check a few in the sim against mz800emu, which plays them at standard speed.

### MZ-1500
- [x] Quick Disk writes: the SIO transmitter (break, data, CRC on underrun, sync) as the ROM drives it, written sectors back to the image. BASIC INIT "QD:", SAVE and LOAD work on hardware; images check with `tools/qdinfo.py`. Writing needs a full-size image (`tools/make_blank_qd.py`).
- [x] The two-tape "DATA" titles (Rally-X, Druaga, Dig Dug, Mappy, Door Door, Knither, Zolvass, Burnin' Rubber, ...) are Quick Disk products dumped to tape, not installers: side A asks for side B ("SET PROGRAM QD ?", answer Y). `tools/mzf2qdf.py` makes a disk of each side.
- [x] Fast tape 32x mapped to the normal CPU speed on the MZ-700/800/1500 and MZ-80B/2000; it now selects the fastest rate (capped at about 35 MHz). The 48 KB Druaga file loads in under a minute on hardware.
- [x] Short keypresses: a remote or scripted key (make and break back to back) was missed by the MZ-1500 IPL while it probes the Quick Disk. Every key now stays in the matrix until 80 ms after the latest press (`keymatrix.vhd`). This exposed an old bug: the E008 sound gate latched only on the 2 MHz peripheral enable, so some CPU writes to it were lost (no beeper).
- [ ] More `mzf2qdf.py` titles: Dark Storm, Demon Crystal, Devil Land, Feizer-21, Flappy, Holy Knight, Volgurd, Grobda/Battle City tapes, Galaga (two files on one tape).
- [ ] Tape titles on hardware: the `C` at the IPL menu is sometimes missed (keypress while the IPL still probes the QD); W02 presses it twice, the C tests should too.
- [x] CG ROM read through OUT E5 0, with bit 7 as the left pixel like the PCG (software copies CG characters into the PCG; Xetter '91's text was mirrored with the ROM dump's order). Test cg_mz1500: 'F' reads 7E40407840404000.
- [ ] Galaga's tape (GALAGA DATA + GALAGA MZ-1500) stops at "QD: Not ready": probably a Quick Disk title too; try `mzf2qdf.py` with both files.
- [x] Joysticks: MZ-1X03 on E008 bits 1-4 (OSD MZ-1X03 Joysticks, also for the MZ-700): buttons during the picture, axis pulses of 68 + 28 x position T-states from the start of vertical blank, as mz800emu's joymz-1x03.c. Not yet tried with software.
- [ ] Printer.
- [x] MZ-1500 ROMs: identical to MAME's mz1500 set (9z-502m.rom, mz700fon.jpn).

### Other models
- [ ] MZ-700 floppy on hardware; MZ-2Z009 Disk BASIC (loads from tape) on a blank disk.
- [ ] MZ-2000: MZ-80B CP/M (DISK01) on the MZ-2000 stays black; recheck now that NST resets the CPU.
- [ ] MZ-2000 character ROM is MAME's hand-made font.bin; a real dump of the IX0286PA (also the Japanese MZ-80B font) would replace it.
- [ ] More MZ-2000 tapes from `software/mz2200` (Super Doors, Itasandrias, Project A, ...); Ice Block's MZT is malformed.
- [ ] MZ-80B SB-7010 (DISK29) loads and stops at its monitor's `*` prompt; find out how FDOS is started from there.
- [x] wd1793: EDSK sectors dumped with a CRC error (ST2 bit 5 data field, ST1 bit 5 ID field) now report CRC ERROR. Recheck DISK37/38 (bad dumps) on the MZ-80B: the IPL should report a loading error instead of hanging.
- [ ] MZ-80K/80A floppy interface ROMs and the SA-6510 boot disk (`software/idealine/`).
- [ ] MZ-80B: GRAM and 40/80 column switching with real software; SAVE and APSS.
- [x] MZ-80A keys: cursor keys, Backspace/Delete/Insert and Home/End go to the MZ-80A's UP/DOWN, RIGHT/LEFT, INST/DEL and CLR/HOME keys (with SHIFT where needed), the keypad to its keypad (`tools/fix_keymap.py`). Not yet tried on hardware.
- [ ] MZ-80K/1200 keys: check the same keys against their matrices.
- [ ] MZ-80K: 3-D MAZE loads and runs but the screen looks garbled; check whether that's the program.

### Core and polish
- [ ] Audio mixing: sound and tape together, volume.
- [x] Joystick mapping in the OSD (Fire 1, Fire 2).
- [ ] Show tape status (record number, tape full) in the OSD.
- [ ] Tape PLAY_READY "one second" counter is hard-coded to 32,000,000 cycles.
- [ ] Optional 64 MHz clock for the MZ-80K/80A/80B family, so their clock enables are exact (±1 clk_sys jitter now).
- [ ] Unit testbenches for `cmt.vhd` and the i8254.
- [x] WAV to MZF converter: `tools/wav2mzf.py` (WAV, or FLAC etc. through ffmpeg; either polarity; header and body copies). Decodes the No-Intro MZ-700 "BASIC" and "Applications" recordings.
- [ ] Release RBF `releases/SharpMZ_YYYYMMDD.rbf` after hardware testing.
- [ ] Later: v2 machine options (RAM size, GRAM, MZ-1R25), and removing `support/sharpmz/` from Main_MiSTer.

## Known issues
- Changing the model doesn't reset MZ-800 characters redefined through C000; the IPL restores the font on the next boot.
- The author's framebuffer graphics extension (bitmap graphics for the MZ-700/80A) isn't included.

## Hardware test log
- **2026-09-29, MZ-700:** Galactic Invaders loads from tape and plays (SHIFT fires, SPACE pauses as the game intends). This found the keymap bugs fixed in `cbb1c04`.
- **2026-09-30, all models (`tools/mister_test.py`):** T01-T06 boot screens correct on every model (MZ-2000 on the MZ-2200 IPL). T07 MZ-700 tape, T08 MZ-700 floppy, T09/T10 MZ-800 graphics tests pass. T11/T12 MZ-800 games load from tape images (Cauldron II, Cybernoid) after the tape image fix. The user played MZ-800 CP/M games from disk (sound fixed in `11f2d8b`). T13-T18 on b4004ff: MZ-800 CP/M 4.1 (DIR), CP/M 1.3 and the Hry file manager boot from floppy; MZ-80B boots SB-6511 Disk BASIC and CP/M 2.2; the MZ-2000 loads MZ-80B CP/M and stays blank, as in the sim. T19/T20 play the BELL and 440 Hz tone (by ear).
- **2026-10-02, tapes and keys (build 2ca6911):** all twelve MZ-1500 tape tests now get their `C` (80 ms key hold): Pac-Man, Mario Bros. Special, Thunder Force, Star Fighter and Xetter '91 reach their titles; Mappy, Dig Dug, Rally-X, Door Door, Flappy and Druaga ask for their Quick Disk; Galaga stops at "QD: Not ready". Xetter '91's text was mirrored (CG read bit order, fixed). T03 (MZ-700), T25/T26 and W01 unchanged.
- **2026-10-02, Quick Disk writes (build fdb8de9):** W01: MZ-5Z001 BASIC boots from a disk made by `mzf2qdf.py`, `INIT "QD:"` formats it, `SAVE "TEST"`, `NEW`, `LOAD "TEST"`, `RUN` prints the result; the fetched image has the count, format mark, header and body blocks with good CRCs. BASIC had hung before READY: the Z80 PIO dropped a /CTC0 condition that changed while its interrupt was disabled (fixed as in mz800emu). G01-G08: Druaga, Rally-X, Dig Dug, Mappy, Door Door MkII, Knither, Zolvass and Burnin' Rubber reach their title screens from tape images turned into Quick Disks. W02 showed the Druaga tape is not an installer: it asks for QD side B.
- **2026-10-02, MZ-1500 software (build aa0e0a7):** Quick Disk: Nintendo Tennis runs; Battle City, Grobda, Milky Way and Batten Tanuki load side A, ask for side B and reach their title/demo once the MGL swaps it in. Tapes: Rally-X, Thunder Force, Door Door MkII and Druaga load their DATA files (Quick Disk products: side A asks for side B, see the entry above); Pac-Man, Mappy, Dig Dug, Mario Bros. Special, Flappy, Star Fighter, Xetter91 and Galaga missed the `C` keypress in the test run.
- **2026-10-01, MZ-1500 (build 5eda577):** T25 IPL menu, T26 Lode Runner from Quick Disk with the PCG title screen; MZ-700 unchanged (T03).
- **2026-10-01, MZ-80B/2000 (clean build 9b9001e):** T21 MZ-80B SB-5520 BASIC from tape, T22 Gang Man, T23 TF-DOS D88 with katakana, T24 Zero Fighter in colour. All match the sim.

## Bugs found and fixed
Each has a commit; this list is for context.
- **MZ-80B/2000 NST:** PC1 going high must reset the CPU (the IPL's jump into RAM); the core carried on at 0008 inside the loaded program (Zero Fighter crashed).
- **Stale FPGA ROM contents:** a Quartus incremental build kept the old character ROM after only the MIF changed; builds are now clean (`rm -rf db incremental_db`).
- **MZ-80B/2000 tape never played:** GHDL lost the CMT state process's writes to CMT_BUS_OUTi (the vector was split between the process and concurrent assignments), so the APSS deck never left reset; and the deck needed PLAY high with STOP low, which the MZ-2200 IPL never does. Now registered bits and edge-triggered commands, as MAME.
- **Tape image lost on reset:** a machine reset cleared the CMT but the tape engine still thought its record was loaded, so a tape mounted before Reset (or an MGL `<reset>`) never played. It now reloads after a reset.
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

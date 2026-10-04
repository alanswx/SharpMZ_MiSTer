# Software triage against mz800emu

`tools/triage.py` runs each single-file machine-code program of the year-based collection
(`software/Year-Based Collection of Games for the Sharp MZ-80K Line of Home Computers v1.0`, folders named
`MZ-700` / `MZ-800`) two ways and takes one screenshot of each, about 400 frames (8 s) after the program starts:

- the core: the half-clock Verilator sim (`verilator/obj_dir_fast/Vtop`, `make fast`), the program loaded straight into
  RAM and started with the monitor's `J` (MZ-800: `M` at the IPL first);
- the reference: mz800emu's headless mode with its own direct load.

```sh
cd verilator && make fast && cd ..
python3 tools/triage.py mz700 "software/Year-Based Collection ..." --jobs 10 --frames 400
```

It writes `verilator/out/triage/<model>/`: `NNNN_core.png`, `NNNN_emu.png`, `results.csv` and contact sheets
(`sheet_NN.png`, core left, emulator right; needs Pillow). Multi-file titles (Loader + Program) and BASIC programs
(types 02 and 05) are listed as skipped: they need the tape path or the BASIC interpreter.

The two runs don't start at the same cycle, so animation phase, attract-mode progress, colour cycling and anything
random differ; the sheets are reviewed by eye.

## MZ-700 (2026-10-04): 224 titles

| Result | Titles |
|---|---|
| Same screen | 165 |
| Differ only by timing, animation, colour cycling | 45 |
| Core bug, fixed | 2 (Base Zero, Revers [a1]) |
| Random colours (`LD A,R`), not a bug | 3 (Zaxxon, Blast Off, Maze Minder [b]) |
| Need more than a direct load | 6 (data files, loaders for a next tape file) |
| No usable reference | 3 (mz800emu gave no picture or an error; the core's screen is plausible) |

**Fixed: the 8253 interrupt storm.** Base Zero and Revers [a1] stayed at the monitor. They execute `EI`; the MZ-700
monitor enables the 8253 counter 2 interrupt (8255 PC2) at cold start but never programs counter 2, and our 8253
reset every counter to mode 2 with OUT high, so the interrupt never cleared (2,846 interrupts in 10 frames). The
counters now power up in mode 0 with OUT low and idle until a count is written, as mz800emu
(`rtl/i8254/i8254_counter.vhd`). This hit any MZ-700 program that enables interrupts without setting the clock.

**Not bugs:**
- Zaxxon, Blast Off and Maze Minder pick colours from the Z80 R register (Maze Minder's colour RAM fill is
  `POKE P, 70h + RND`), so they differ with timing.
- Destructeurs and Mental Mike (Loader) load their next part from tape; mz800emu shows `PLAY`, the core waits
  silently, because the OSD tape buttons default to Auto, which reports PLAY pressed so SAVE needs no prompt.

## MZ-800 (2026-10-04): 114 titles

| Result | Titles |
|---|---|
| Same screen | 72 |
| Differ only by timing, animation, border, palette shade | 8 |
| Core bug, fixed | 10 (black drawn grey in MZ-700 mode) |
| Header area wiped by the direct-load reset (see below) | 12 |
| Cause not known yet | 4 (Abu Simbel Profanation, Antiriad (Eng), Planetoids v3.1, Space Guerilla) |
| Both blank, no usable reference, or not runnable this way | 8 |

**Fixed: black drawn as grey on the MZ-800 in MZ-700 mode.** The palette index for 700 mode was `1111 & '1' & GRB`,
so MZ-700 black became MZ-800 colour 8 (grey). mz800emu maps the MZ-700 colours to `{0, 9..15}`: black stays black
and colours 1-7 take the bright half. `VideoController.vhd` now sets the intensity bit to `G or R or B`. Ground
Attack, Moty, James, Space Duel, HOBRA-Schach, Hell Diver, IS-Chess, Life, Points and Starkiller now match.

**Load Direct and the MZF header.** A direct load holds the machine in a warm reset (`sharpmz.sv`, as on hardware),
so the MZ-800 IPL runs afterwards and clears 10F0-11FF, where the MZF header was put. Programs that start in that
area or read their own header there (Exploding Fist, Jumpin' Jack, Tetris, Solomon's Key, Brouk, Jack the Nipper,
...) fail after Load Direct; mz800emu with the header zeroed fails the same way. From tape they load normally. A
fix would be for Load Direct to start the program itself, as mz800emu does (TODO).

The reviews are in `verilator/out/triage/<model>/review.md` (not in git; rerun the script to rebuild them).

# [Sharp MZ](https://en.wikipedia.org/wiki/Sharp_MZ) for MiSTer Platform

A hardware emulation of the Sharp MZ series personal and business computers, originally written by Philip Smart ([eaw.app](https://www.eaw.app/sharpmz-emulator/)), running as a standard MiSTer 8-bit computer core.

| Model  | Status | Model  | Status |
| ------ | ------ | ------ | ------ |
| MZ-80K | Working | MZ-80C | Working |
| MZ-1200 | Working | MZ-80A | Working |
| MZ-700 | Working | MZ-80B | Working: IPL boots tape and floppy (BASIC, CP/M) |
| MZ-2000 | Working: IPL, tape and floppy, colour graphics, katakana | MZ-800 | Working (IPL, graphics, PSG, tape, floppy, CP/M), tested on hardware |
| MZ-1500 | New: IPL, PCG graphics, stereo PSG, Quick Disk (read and write) | | |

How it compares with the original v2 core, NibblesLab's DE0 cores, mz800emu and MAME: [docs/comparison.md](docs/comparison.md).

## Features

* Z80 CPU at the original speed (2 MHz MZ-80K/C/1200/A, 3.547 MHz MZ-700/800, 4 MHz MZ-80B/2000), with turbo steps up to about 32–35 MHz.
* Native video timing (MZ-700/800 are 50 Hz PAL, the others 60 Hz), scaled by the MiSTer framework: HDMI, analog, scandoubler, scanlines and aspect ratio work as in other cores.
* 40x25 and 80x25, mono and colour character modes; programmable character generator (PCG); MZ-80B/2000 graphics RAM.
* MZ-800: IPL and 9Z-504M monitor, MZ-700 and MZ-800 modes with the MZ-800 memory map, all 320x200/640x200 graphics modes with hardware scroll, the SN76489 sound chip and the Z80 PIO.
* Floppy disk (MB8876 interface on the MZ-700, MZ-800, MZ-80B and MZ-2000): two drives from Extended DSK (`.dsk`) or D88/D77 images. The MZ-800 IPL boots CP/M 1.x, 2.3 and 4.1 disks; the MZ-80B/2000 IPL boots Disk BASIC, CP/M and TF-DOS.
* 8253 sound or the tape signal on the audio output.
* Joysticks: the MZ-800's ports and the MZ-1X03 joysticks of the MZ-700/1500.
* Cassette: MZF loading onto the virtual tape or straight into RAM, and a **Tape Image** slot that loads multi-program tapes and **saves** programs written with SAVE. MZ-80B/2000 load from the tape image under IPL control (deck commands and APSS seek). Fast tape up to 32x.
* Monitor ROMs, character generator ROMs and keymaps for every model are built in, and can be replaced from the OSD.

## Installation

Copy `SharpMZ_<date>.rbf` from `releases/` to the `_Computer` folder of your MiSTer SD card, and put your tape files (`.mzf`, `.mzt`) and disk images (`.dsk`) in `games/SharpMZ/`.

## Using the Emulator

The core boots as an MZ-80A with the SA-1510 monitor. Press F12 for the OSD.

The tape loads, the tape image and the two floppy drives are on the OSD's first page; the other settings are in the Machine, Tape, Display, Floppy and ROM and RAM pages below. MGL files can load any of the first-page entries (`<file type="f" index="1">` for Load Tape to CMT, `type="s" index="0"` for the tape image, `index="1"`/`"2"` for the drives).

### Machine

| Option | Description |
| ------ | ----------- |
| Model | MZ-80A, MZ-80K, MZ-80C, MZ-1200, MZ-700, MZ-80B, MZ-2000, MZ-800 or MZ-1500. Changing model resets the machine. |
| CPU Speed | Default is the original speed. Each step doubles it up to the core's limit of about 32–35 MHz (MZ-700: +4; MZ-80K/A/B: +4 or +5); higher steps fall back to the original speed. |
| Boot Reset | MZ-80B/2000: reset back into the IPL. |
| MZ-1X03 Joysticks | MZ-700/MZ-1500: connect two Sharp MZ-1X03 joysticks (MiSTer joysticks 1 and 2, read on E008). The MZ-800's own joystick ports (F0/F1) are always connected. |
| MZ-800 Mode | The MZ-800 rear switch. In MZ-800 mode the IPL switches to MZ-800 graphics before starting a program loaded from tape; in MZ-700 mode (default) programs start in MZ-700 mode, which MZ-700 software needs. Reset after changing it. |

### Tape

A tape is either a single `.mzf` file (a 128-byte header followed by the program) or an `.mzt` file (several `.mzf` records back to back).

| Option | Description |
| ------ | ----------- |
| Load Tape to CMT | Put an `.mzf` on the virtual tape. Start it from the machine as normal (`L` or `LOAD` in the monitor, `LOAD` in BASIC). |
| Load Direct to RAM | Copy the program straight into memory at its load address and reset. Start it from the monitor with `J` and the exec address. |
| Tape Image | Mount an `.mzt`/`.mzf` as the cassette. The first program is ready to play; when the machine stops the tape after reading one program, the next one is loaded, so multi-part programs work. Programs saved with SAVE are appended to the image. |
| Rewind Tape Image | Go back to the first program on the mounted image. |
| Tape Buttons | Auto (play or record as the machine needs), Off, Play, Record. |
| Fast Tape | Run the CPU (and the tape) faster while the tape is moving, 2x to 32x (capped like CPU Speed: 16x and 32x are both the fastest on the MZ-700/800/1500). Default and Off are real speed. |
| Sharp ASCII Name | Convert tape file names between Sharp display codes and ASCII on save and/or load. |
| Audio Source | The 8253 sound, or the tape signal. |
| Tape Sound | Mix the tape signal in quietly while the tape is playing or recording, as the machines' own tape monitor would (Audio Source stays on the sound). |

**Saving programs.** MiSTer can't grow a mounted file, so saving needs a tape image with spare room. Make a blank one with `tools/make_blank_tape.py` (default 1 MB, zero-filled), mount it as the Tape Image, and SAVE as usual (for example `S120012FF1200` then a file name in the MZ-700 monitor). Each program is appended after the last one. If the image is read-only or full, the save is skipped.

### Floppy

| Option | Description |
| ------ | ----------- |
| Floppy Drive A / B | Mount an Extended DSK or D88/D77 image (up to 1 MB, e.g. the usual 720 KB CP/M disks). With a disk in drive A, the MZ-800 and MZ-80B IPLs boot it at reset; on the MZ-700 type `J F000` at the monitor (the interface brings its MZ-1E05 ROM). The interface is available on the MZ-700, MZ-800, MZ-80B and MZ-2000. |
| Quick Disk | Mount a Quick Disk image: a raw dump (`.qdf`) or mz800emu's `.mzq`. Built into the MZ-1500 (press `Q` at the IPL menu); on the MZ-800 it appears while an image is mounted. Writes (BASIC `INIT "QD:"`, `SAVE`) go back to the image, which must be full size: make a blank one with `tools/make_blank_qd.py`. |
| Floppy Interface | Auto (present only while a disk is mounted, so the IPL doesn't stop at "Make ready FD"), On or Off. |
| Floppy CRC Errors | Ignore (default): sectors the disk image marks as read with a CRC error are read as good, which suits most dumps. Report: the drive reports CRC ERROR for them, for software that checks (copy protection). |
| MZ-800 RAM Disk | A 64 KB RAM disk board (ports EA/EB, F8-FA), for CP/M's RAM drive. Its contents are lost at power off. |

Writes go back to the image; mount a copy if you want to keep the original.

### Display

| Option | Description |
| ------ | ----------- |
| Display Type | Default follows the model (MZ-700/800 colour 40x25, MZ-80B/2000 mono 80x25, others mono 40x25). |
| Video / Graphics | Turn the character or graphics layer off. |
| VRAM Wait | Insert the original wait states when the CPU accesses video RAM during the display (MZ-80A/1200/700). Some software relies on this timing. |
| Aspect ratio | Original, full screen, or the custom ratios from `MiSTer.ini`. |

### ROM and RAM

| Option | Description |
| ------ | ----------- |
| User ROM / FDC ROM | Map the user ROM (E800) or FDC ROM (F000) for the current model. |
| Load System ROM / RAM / Keymap / CGROM | Replace the built-in combined monitor ROM, the initial RAM image, the keymaps or the character generator ROM. The files use the same layout as `rtl/software/roms/combined_*.rom`. |

## Known Issues

* MZ-2000: the character ROM is MAME's `font.bin`, which was rebuilt by hand from bitmaps (MAME marks it a bad dump); a few katakana glyphs may differ from the real IX0286PA ROM.
* MZ-800: checked in simulation against the mz800emu emulator, still being tested on hardware. The border colour isn't shown (only the 320x200/640x200 area is output), and the printer port isn't implemented. Joysticks and the RAM disk are new and not yet tried with software.
* Floppy: 1.44 MB images aren't supported, and the MZ-80K/80A floppy interface isn't implemented. Writing works (CP/M SAVE on hardware); drive B and writes at turbo speeds are untested.
* The author's framebuffer graphics extension (bitmap graphics for the MZ-700/80A) isn't available in this version.
* The MZ-80B/2000 have had little testing beyond a handful of tapes and disks (see `TODO.md`).
* Many MZ-1500 Quick Disk titles are archived as two tape images (side A a "DATA" loader that asks for side B). They don't run from tape; `tools/mzf2qdf.py OUT.qdf SIDE.mzt` makes a Quick Disk of each side (answer `Y` to "SET PROGRAM QD ?" after swapping in side B). `tools/qdinfo.py` lists a Quick Disk image's files and checks their CRCs.
* Tape recordings (the No-Intro "Waveform" sets, `.wav`/`.flac`) convert to MZF with `tools/wav2mzf.py RECORDING [OUTDIR]` (standard Sharp format only, not turbo loaders).

## Design Summary

* **One clock.** Everything runs on a single 70.9376 MHz clock (4x the MZ-700's 17.7344 MHz crystal) with clock enables for the CPU, video, sound and timers (`rtl/clkgen.vhd`). The MZ-700/800 rates are exact divides.
* **Standard MiSTer framework.** The `sys/` folder is stock Template_MiSTer, the OSD is a normal configuration string, and files come in through the standard ioctl and image-slot interfaces. Main_MiSTer's old Sharp MZ driver isn't used.
* **Video** is the author's v2 VideoController from the [tranZPUter](https://git.eaw.app/eaw/tranZPUter) project, moved onto the core clock (`rtl/vc/`).
* **Tape images** are handled in the FPGA by `rtl/tape_image.sv`, which moves programs between the image and the core's cassette buffer.
* **Floppy** is `rtl/mz_fdc.sv`: the Sharp interface around Sorgelig's `wd1793.sv` (from the FM-7 core), reading DSK images through the image slots.
* More detail in `docs/design.md`.

## Building and Simulation

* **FPGA:** open `sharpmz.qpf` in Quartus Prime Lite 17.0 and compile.
* **Simulation:** `verilator/` runs the core headless with GHDL and Verilator: boot any model, type at it, load and save tapes, and write screenshots. `make test` runs the regression tests. See `verilator/README.md`.
* **Status and open work:** `TODO.md`. **Design notes:** `docs/design.md`.

## Links

The Sharp MZ Series Computers were not as wide spread as Commodore, Atari or Sinclair but they had a dedicated following. Given their open design it was very easy to modify and extend applications such as the BASIC interpreters and likewise easy to add hardware extension. As such, a look round the web finds some very comprehensive User Groups with invaluable resources. If you need manuals, programs, information then please look (for starters) at the following sites:

| Site                                                 | Description |
| ----                                                 | ----------- |
| [Engineers At Work](https://www.eaw.app/)            | My personal projects site. |
| [SharpMZ.org](https://original.sharpmz.org/)         | Original SharpMZ site, excellent resource but the owner has retired now. |
| [SharpMZ.no](https://www.sharpmz.no/)                | Site to replace the Original SharpMZ site, still under development. |
| [mz-80a.com](https://mz-80a.com)                     | MZ-80A Sectors guide to the Sharp MZ-80A |
| [Sharp Users Club](http://www.sharpusersclub.org/)   | Still active, the Sharp Users Club. |
| [SharpMZ Forum](http://forum.sharpmz.org)            | Active Sharp MZ forum for all models. |
| [SCAV](http://www.scav.cz/uvod.htm)                  | Czech site for Sharp information and downloads, use chrome to auto translate Czech |

## Credits

My original intention was to port the MZ80C Emulator written by Nibbles Lab <https://github.com/NibblesLab/mz80c_de0> to the Terasic DE10 Nano. After spending some time analyzing it and trying to remove the NIOSII dependency, I discovered the MISTer project, at that point I decided upon writing my own emulation. Consequently some ideas in this code will have originated from Nibbles Lab and the i8253/Keymatrix modules were adapted to work in this implementation. Thus due credit to Nibbles Lab and his excellent work. Also credit to Sorgelig for his hard work in creating the MiSTer framework and design of some excellent hardware add-ons. The MiSTer framework makes it significantly easier to design/port emulations. Where I have used or based any component on a 3rd parties design I have included the original authors copyright notice within the headers or given due credit. All 3rd party software, to my knowledge and research, is open source and freely useable, if there is found to be any component with licensing restrictions, it will be removed from this repository and a suitable link/config provided.

## Licenses

This design, hardware and software, is licensed under the GNU Public Licence v3.

### The Gnu Public License v3

 The source and binary files in this project marked as GPL v3 are free software: you can redistribute it and-or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

 The source files are distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

 You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

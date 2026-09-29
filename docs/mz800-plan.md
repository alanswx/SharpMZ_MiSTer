# MZ-800 support plan

The MZ-800 is added to the existing v1 machine logic (`rtl/mz80c/mz80c.vhd`, `rtl/sharpmz.vhd`) as a separate branch selected by `CONFIG(MZ800)`, so the other models synthesize as before. The author's v2 `mz80k_hw.vhd` (tranZPUter) is a reference only: its interface and CONFIG layout differ, it changes the behaviour of the working models, and it has gaps against mz800emu (listed below). mz800emu (`refs/mz800emu`) is the behavioural reference.

## Hardware (from mz800emu and the MZ-800 Technical Reference Manual)

### Memory map

One 5-bit map register, shared by both modes: ROM_0000, ROM_1000, CGRAM_VRAM, ROM_E000, PROHIBITED (`mz800_memory.h`). What CGRAM_VRAM and ROM_E000 map depends on the GDG display mode register DMD (port CE): bit 3 = MZ-700 mode, bit 2 = 640 wide.

Reset: map = ROM_0000 | ROM_1000 | ROM_E000; DMD = 0x08 (700 mode).

| Area | Mapped when | Otherwise |
|---|---|---|
| 0000-0FFF | ROM_0000: ROM | RAM |
| 1000-1FFF | ROM_1000: CG ROM | RAM |
| 8000-9FFF | 800 mode and CGRAM_VRAM: VRAM (GDG planes) | RAM |
| A000-BFFF | 800 mode, CGRAM_VRAM and 640 wide: VRAM | RAM |
| C000-CFFF | 700 mode and CGRAM_VRAM: CG-RAM (PCG) | RAM |
| D000-DFFF | 700 mode and ROM_E000: VRAM | RAM |
| E000-FFFF | ROM_E000: ROM, except the bottom (below) | RAM |

Bottom of E000 when ROM_E000 is set:
- 700 mode: E000-E008 are the memory-mapped ports (8255, 8253, E008 GDG status/gate); E009-E00F read 0x1A.
- 800 mode: E000-E00F read 0xFF.

PROHIBITED: every read of E000-FFFF returns 0x1A. It survives E0-E4 writes and mode switches; only OUT E6 clears it.

### Bank ports

| Access | Effect |
|---|---|
| OUT E0 | clear ROM_0000, ROM_1000 |
| OUT E1 | clear ROM_E000 |
| OUT E2 | set ROM_0000 |
| OUT E3 | set ROM_E000 |
| OUT E4 | set ROM_0000, ROM_1000, CGRAM_VRAM, ROM_E000; in 700 mode then clear ROM_1000 and CGRAM_VRAM |
| OUT E5 / E6 | set / clear PROHIBITED |
| IN E0 | set ROM_1000, CGRAM_VRAM |
| IN E1 | clear ROM_1000, CGRAM_VRAM |

### ROM

One 16 KB chip, `rtl/software/roms/MZ800_{0000,CGROM,E000}.rom` (extracted from mz800emu):

| Chip offset | Contents | CPU address |
|---|---|---|
| 0000-0FFF | 1Z-013B (MZ-700 monitor variant, starts `JP E800`) | 0000-0FFF |
| 1000-1FFF | CG (the MZ-700 CG bit-reversed) | 1000-1FFF |
| 2000-3FFF | IPL and 9Z-504M monitor | E000-FFFF |

The chip address is the CPU address A13..A0. In the combined monitor ROM it goes at 0x1C000 (that region is unused).

### I/O

- D0-D3 (8255) and D4-D7 (8253): 800 mode only. In 700 mode they are at E000-E007.
- CC WF, CD RF, CE DMD, CF CRTC, F0 palette: writable in both modes.
- IN CE status: bit 7 HBLNK, 6 VBLNK, 5 HSYNC, 4 VSYNC, 2 CKSW, **1 = MZ-700 mode switch**, 0 TEMPO.
- F0/F1: joysticks (0xFF when not strobed). F2: PSG (write only). FC-FF: Z80 PIO.

The machine always powers up in 700 mode. The IPL reads CE bit 1 and, if the switch is off, writes DMD=0 to enter 800 mode.

### Clocks and wiring

- CPU = 17.734475 MHz / 5 = 3.5469 MHz. 8253 CLK0 = CPU / 16 = 1.1084 MHz. CLK1 = HSYNC; OUT1 clocks CTC2.
- PSG is clocked at 3.5469 MHz (it divides by 16 itself), independent of turbo.
- CTC gate 0 is '1' in 800 mode; in 700 mode it is bit 0 written to E008.
- Sound = CTC0 AND 8255 PC0. INT = (CTC2 and PC2) OR the PIO interrupt.

## Gaps in v2 `mz80k_hw.vhd` (why it is only a reference)

1. It keeps separate MZ-700 latches and MZ-800 bitmaps, which drift apart (e.g. reset, OUT E4, OUT CE 0 leaves 8000 mapped to VRAM).
2. The A000 VRAM decision is taken at E4/IN E0 time and does not follow later DMD writes.
3. In 700 mode, E010-E06F is not ROM (QD-IOCS starts there).
4. Missing reads: 0x1A for PROHIBITED and E009-E00F, 0xFF for E000-E00F in 800 mode.
5. Joystick reads 0x00 (all pressed) instead of 0xFF.
6. No 8253 sound in 800 mode, and PC0 does not gate the sound.
7. The PSG clock follows the CPU (turbo changes pitch) and adds wait states.
8. Clocks made from signal edges.
9. The VideoController CE read returns the mode register, not the status byte.

## Steps

`make test` after each step; the existing boot and tape tests must not change.

1. **Clocks.** MZ-800 gets the MZ-700 CPU speeds and sound clock. Check: about 70.9k CPU cycles per frame, as mz800emu (70890).
2. **ROM.** 16 KB at 0x1C000 of the combined ROM; MROM bank for the MZ-800.
3. **700 mode.** Map register, bank ports with IN side effects, E000 ports, CE status and the mode switch on the OSD.
   - Checkpoint A: at frame 150 the text screen matches mz800emu (the IPL menu: "Please push key", "C:Cassette tape", "M:Monitor").
   - Checkpoint B: typing `M` gives `**  MONITOR 9Z-504M  **`. Add `boot_mz800`.
4. **800 mode.** D0-D7 I/O, GRAM at 8000/A000, gate 0 and PC0. Checkpoint C: a test program setting DMD, palette, border and writing planes gives the same picture as mz800emu.
5. **PSG** (`sn76489_audio.vhd` from v2) on a fixed 3.5469 MHz enable; 16-bit mix with the 8253.
6. **Z80 PIO** at FC-FF; joystick reads 0xFF.
7. **PCG.** C000 writes in 700 mode to a CG RAM (with the bit reversal); fix the CE read in VideoController.
8. **Tape.** Load an MZF from the IPL `C` option; add to `run_tests.sh`.

Existing issue found on the way: the first MROM_BANK clause for each model in `sharpmz.vhd` has no address condition, so the User ROM (E800) and FDC ROM (F000) banks are never selected.

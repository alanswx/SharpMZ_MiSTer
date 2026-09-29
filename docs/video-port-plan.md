# Plan: replace v1 `video.vhd` with the v2 VideoController on clk_sys

Phase 4 of `TODO.md`. **VC** = `refs/tranZPUter/FPGA/SW700/v1.3/MZ700/VideoController/VideoController.vhd` (the author's v2, GPLv3; `refs/` is gitignored, see `refs/README.md`). **v1** = `rtl/video.vhd`. **SMZ** = `rtl/sharpmz.vhd`. Line numbers refer to those files as of September 2026.

## 1. Clocks

**PLLs.** VC uses two PLLs from CLOCK_50: `Video_Clock` (VC:966) and `Video_Clock_II` (VC:990). Every video clock is 2× the dot clock. FFCLK1–6 (VC:1506–1594) pick one by `CLOCKSEL` (timing table column 22). `VID_CLK` is an AND/OR gated clock (VC:5255).

**Native modes:**

| Mode | Timing | Active area | Dot clock |
|---|---|---|---|
| MONO40 | 512×260 | 320 | 8 MHz |
| MONO80 | 1024×260 | 640 | 16 MHz |
| COLOUR40 | 568×260 | 320 | 8.8672 MHz |
| COLOUR80 | 1136×260 | 640 | 17.7344 MHz |

VC:412–415.

**Clock domains:**
- **VID_CLK:** RENDERCHRFRAME (VC:1614), RENDERGRAPHICSFRAME (VC:1917), GENVIDEO (VC:2246), and port B of every RAM.
- **SYS_CLK:** bus capture (VC:1431), the MZ-800 GDG (VC:2738), the GPU (VC:3344), CTRLREGISTERS (VC:3707), and port A of every RAM.
- **Unsynchronised crossings:** `GRAM_MODE_REG`, `OFFSET_ADDR`, `MODE_VIDEO_*`, the `GD_*` registers, `PALETTE_REG`, and `VIDEOMODE_NEXT` (combinational, VC:5141). `CG_ADDR` (VC:5008) mixes both domains. All of these become synchronous on clk_sys.

**Logic that assumes a 2× clock:**
- `VIDCLK_DIV` toggles, and pixel work happens on the second edge (VC:2306, 2315, 2433, 2439, 2443).
- `RENDR_*_NEXT` is one VID_CLK wide (VC:2318–2319).
- The render FSMs have about 15 VID_CLK per 8 pixels (VC:1611).
- `VIDEOMODE_RESET_TIMER` counts 255 clocks (VC:2436).
- `COLR_OUT` is clocked at 17.73 MHz (VC:5396).

**Replacement:**
- Delete the PLLs, FFCLK1–6 and `VID_CLK`.
- Add a CE_PIXEL generator indexed by `CLOCKSEL`, using the same accumulator as `rtl/clkgen.vhd`.
  - At 70.9376 MHz, 17.7344 = clk_sys/4 and 8.8672 = clk_sys/8, both exact.
  - 8 and 16 MHz jitter by ±1 clk_sys, which ascal handles.
- GENVIDEO's old `VIDCLK_DIV='1'` body runs on CE_PIXEL.
- `RENDR_*_NEXT` becomes one clk_sys wide.
- The render FSMs run ungated. At 80 columns there are ≥32 clk_sys per 8 pixels, against about 7 needed.
- All RAM ports go on clk_sys.
- CE_PIXEL feeds `CLKVID`/`CE_PIXEL`, so `CONFIG(VIDSPEED)` becomes unused.

**Bug:** TIMING_COLOUR40/80_50HZ (VC:423–424) are copies of the 60 Hz mono timing. Restore 568×312 and 1136×312 (see the commented table at VC:390–391).

## 2. Bus interface and decode

**VC decode:**
- **Memory:** VRAM `CS_DXXXn` (VC:4714); E-range PCG E010–E012 (VC:4752), invert E014/E015 (VC:4755), scroll E200–E2FF (VC:4758), 8255 snoop (VC:4762); GRAM `CS_800_GRAMn` / `CS_80B_GRAMn` / `CS_MZ2K_GRAMn` / `CS_FBRAMn` (VC:4722–4736).
- **I/O:** A0–BF controller registers (VC:4738–4809), MZ-800 CC–CF/F0 (VC:4813–4826), MZ-80B snoops of E0/E4/E8 (VC:4830–4837), MZ-2000 F4–F7 (VC:4851–4907).
- **Direct addressing:** when `VIDEO_ADDR(23:16) /= 0` (VC:4673–4702).
- **Read latency:** read data is latched after RD has been low for 4 cycles (VC:1465–1468), and writes use a falling-edge pulse (VC:1488). Always register `VIDEO_DATA_OUTi` instead; otherwise turbo CPU speeds read stale data. Tie `WR_BYTE`/`WR_HWORD` to byte and narrow the data bus to 8 bits.

**What v1 passes to video** (SMZ:852–900): `T80_A(13:0)`, RD/WR/MREQ, `CS_VRAM_n`, `CS_MEM_G_n`, `CS_GRAM_n`, `CS_GRAM_80B_n`, `CS_IO_GFB_n`, `CS_IO_G_n`, `VGATE_n`, `INVERSE_n`, `CONFIG_CHAR80` (muxed at SMZ:1132–1139).

**Double-decode hazards:**
- **MZ-700 bank switching.** v1's `CS_VRAM_ni`/`CS_E_ni` (`mz80c.vhd:431–447`) follow the bank switching; VC does not. Gate it: `VIDEO_MREQn = T80_MREQ_n OR (CS_VRAM_n AND CS_MEM_G_n AND CS_GRAM_n AND CS_GRAM_80B_n)`, as `coreMZ_emuMZ.vhd:1559–1573` does.
- **MZ-80B.** VC snoops PIO/PPI writes and ignores PIO mode and direction (VC:4165–4226). Remove the snoops. Drive `DISPLAY_VGATE`, `DISPLAY_INVERT` and `VIDEO_MODE_REG(4)` from v1's `VGATE_n`, `INVERSE_n` and `CONFIG_CHAR80`; drive `MZ80B_VRAM_*` / `CS_80B_GRAMn` from v1's `CS_VRAM_n` / `CS_GRAM_80B_n`.
- **Graphics ports.** v1's I/O base is programmable (`CONFIG(GRAMIOADDR)`, reset 00–07; `mctrl.vhd:424`). VC hardwires B8–BD. Map `CS_IO_GFB_n` +0..+3 onto `CS_FB_CTLn`/`REDn`/`GREENn`/`BLUEn`, replace `CS_FBRAMn`/`FBRAM_PAGE_ENABLE` with `CS_GRAM_n`, and remove the A0–BF decode.
- **No conflict:** F4–F7 (v1 decodes only F4) and MZ-800 CC–CF/F0 (gated to MZ-800 mode).

## 3. CG ROM and CG RAM loading

- **v2:** a 4 KB CGROM0 RAM (VC:1387) reloaded by the I/O processor. It's written through direct addressing at 0x220000 or through port BD bit 7 plus D000–DFFF (VC:4132, 5010); the MZ-800 also writes C000–CFFF (VC:5013). CGRAM0 (VC:1410) is the PCG; its direct address is 0x222000, not the 0x221000 the comments give.
- **v1:** a 32 KB CGROM0 (v1:782), initialised from `combined_cgrom.mif` with 2 KB banks by `CGROM_BANK` (v1:1721–1741). ioctl writes it at 0x500000, and CGRAM at 0x600000.
- **Plan:** use the 32 KB combined dpram, addressed `CGROM_BANK(3:1) & (CG_ADDR(11) for 4 KB MZ-700/800 banks, else bank(0)) & CG_ADDR(10:0)`. Port B is the renderer; port A is ioctl plus MZ-800 CPU writes. Keep CGRAM0 at 4 KB with the PCG logic (VC:4296–4313, 4984–5008). Drop direct addressing.

## 4. What to strip

| Remove | VC lines |
|---|---|
| GPU | 3344–3654, 4938–4944, 5027, 5039–5069 |
| OSD buffers | 1326–1382 |
| OSD planes | 2568–2642 |
| OSD entries in the timing table | cols 4–9, 14–19 |
| OSD blend | 1088–1131, 1141–1155 |
| OSD size and direct access | 3976–3998, 4691–4702, 4963–4980 |
| Palette RAMs and A3–A7/B0 | 1004–1084 |
| VGA timings and modes | — |
| Composite, CSYNC, COLR, `V_*`, tristates | 5356–5398, 4929 |
| `HW_HOST`/`HW_MODE`/`MB_VIDEO_ENABLEn` and "internal monitor" modes 16/17/38/39 | 5321–5342, 1457–1489 |
| Direct addressing | — |

Replace the palette with a small 8-bit RGB LUT: 8 colours, the MZ-800 16-colour IRGB set, and mono green/white. Register RGB/HS/VS/HB/VB on CE_PIXEL. What remains is about 2,700 lines.

## 5. Wait states

- v2 has no MZ-80A/700 VRAM wait. `VWAITn` (VC:4929) is for the framebuffer only and its polarity looks wrong.
- **v2 bug:** `CONFIG(VRAMWAIT)`/`CONFIG(PCGRAM)` are written into `GRAM_MODE_REG(6/7)`, which are the blend operator bits (VC:4378–4385, VC:1094). VC:4374 also compares `GRAMDISABLE` with `CONFIG_LAST(VRAMDISABLE)`.
- **v1:** `VRAM_WAIT` samples `H_BLANKi` at the start of MREQ; `WAITi_n` fires on a VRAM access during active display on MZ_A/MZ700, and `WAITii_n` extends it by one CPU cycle (v1:1552–1567, 1633–1636). It's merged at SMZ:1114. Neither version has an MZ-80B wait; VGATE only blanks.
- **Plan:** keep v1's wait logic in the wrapper, driven by VC's `H_BLANKi` (VC:2447–2448). Check the phase in simulation.

## 6. MZ-800 in v2

- **Implemented:** GWF/GRF/GDMD/GCRTC (VC:2800–2942), all six write modes and both read modes (VC:2993–3320), 320×200×4 planes, 640×200×2 planes, frames A/B/AB, MZ-1R25, and scroll (VC:1274–1321, 2125–2234).
- **Gaps:**
  - CKSW superimpose is unused.
  - There's no MZ-800 memory map, PSG or ports on the machine side.
  - The 50 Hz timings are wrong (section 1).
  - `MODE_VIDEO_BASE = MZ800` (VC:5215) only works by index coincidence.
  - The render depends on `VideoRAM_DP_3208`'s port-B lane select being combinational on the current address while the word is registered.

## 7. Block RAM (M10K)

| | VRAM | GRAM | CGRAM | CGROM | Framebuffer | Status/menu buffers | Total |
|---|---|---|---|---|---|---|---|
| v2 stripped | 4 | 48 | 4 | 32 | — | — | ~88 |
| v1 | 4 | 48 + 16 | 4 | 32 | 48 (16K×24) | 12 + 24 | ~188 |

Expect total RAM blocks to drop from 482 to about 380 of 553.

## 8. Port order (the sim keeps booting at each step)

0. **Baseline.** Save v1 simulation results (ASCII dumps, frame logs, tape tests) for mz700, mz80a, mz80k and mz80b.
1. **Copy and clean up.** Copy VC and its package into `rtl/`. Remove `altera_mf`, inout/'Z' ports and the PLLs. Add `when others` to the case statements at VC:1976, 2012, 2048 and 4265. Avoid the `reverse_vector`/`to_std_logic` clash with `functions_pkg`. GHDL analysis must pass.
2. **RAMs.** Move them onto `rtl/dpram`; ghdl can't synthesise shared variables written from two processes.
   - VRAM: 12/8-bit port A, 11/16-bit port B, keeping the instance name `vram0` for `verilator/sim.v`.
   - GRAM: four byte-lane 4K×8 RAMs with a combinational lane mux.
3. **CE_PIXEL and native-only tables.** A GHDL testbench checks 512/1024/568/1136 × 260 (and ×312) totals with 320/640 × 200 active.
4. **Strip** section 4 and add the RGB LUT.
5. **CONFIG.** Replace the CONFIG port with explicit inputs. Ours is 70 bits with MZ80B = 6 and MZ2000 = 7; v2's is 90 bits with 7 and 8. Rewrite VC:4326–4402 and fix the section 5 bugs.
6. **Wrapper and SMZ wiring.** Pass the full 16-bit address, gate MREQ, keep v1's wait logic, and update the Makefile and `files.qip`. Check that the MZ-700 boots, the ASCII dump and tape load match, and the VBLANK/HBLANK phase matches (it feeds 8255 PC7 and E008 bit 7; `mz80c.vhd:358, 819`).
7. **MZ-80A/K/C:** 8 MHz, E200 scroll, E014 invert, PCG.
8. **MZ-80B/2000:** GRAM I/II, runtime 40/80 switching, IPL.
9. **Remove v1** `video.vhd` and run a Quartus fit to check BRAM and timing.
10. **MZ-800**, later.

## Risks

- The double decode on the MZ-700 and MZ-80B until MREQ is gated and the snoops are removed.
- Read latency at turbo speeds.
- The MZ-800 lane-select dependency.
- `CLOCKSEL` changes at frame boundaries, so the scaler has to resync.
- The `CONFIG` dependency throughout CTRLREGISTERS.

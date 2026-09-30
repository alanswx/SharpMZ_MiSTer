# SharpMZ Verilator simulation

Runs the core headless on the host. It can boot any model, type at it, load and save tapes, boot floppy disks, and write screenshots, frame logs, audio, CPU/I/O traces and memory dumps. No DE10-Nano or Quartus is involved.

The options match the headless CLI of the reference emulator in `../refs/mz800emu` (`HEADLESS_CLI.md` there), so the same scenario can be run on both and compared.

## Build and run

```sh
cd verilator
make                 # -> ./obj_dir_headless/Vtop
make test            # regression tests (run_tests.sh; QUICK=1 skips the slow tape tests)
make test-clkgen     # GHDL testbench: clock enable rates and jitter
./obj_dir_headless/Vtop --help
```

Needs GHDL 5.x, Verilator 5.x and Python 3 (`brew install ghdl verilator`). **Run the binary from this directory**, because the RAM init files are loaded from `./software/mif/*.hex`.

## How the build works

1. `ghdl synth` turns `../rtl` (VHDL) into a Verilog netlist, `gen/sharpmz.v`. Module, instance and register names survive.
2. Two fix-ups are applied to the netlist:
   - VHDL names that are Verilog keywords (`do`, `config`) are renamed.
   - `fix_port_aliases.py` restores `SIG <= in_port;` assignments that GHDL 5.1's Verilog writer drops.
3. `dpram`/`dprom` (Altera `altsyncram` wrappers) are black boxes, implemented by `rtl_v/dpram.v` and `rtl_v/dprom.v`. `mif2hex.py` converts the `.mif` init files for `$readmemh`, so the ROMs are built in, as on hardware.
4. `sim.v` stands in for `sharpmz.sv`:
   - the OSD configuration as inputs;
   - the ioctl download bus (MZF to the tape buffer at `0x400000`/`0x410000`, direct loads into RAM at `0x100000+`);
   - the tape image (`rtl/tape_image.sv`) and floppy (`rtl/mz_fdc.sv`, `rtl/wd1793.sv`) with their image slots.
5. `sim_headless.cpp` emulates Main's side of hps_io: key presses, downloads, and the 512-byte sector handshake of the image slots (S0 tape, S1 floppy drive A).

## Options (main ones)

| Option | |
|---|---|
| `--model M` | mz80k, mz80c, mz1200, mz80a, mz700, mz800, mz80b or mz2000 |
| `--stop-at-frame N` | Run to frame N. |
| `--screenshot N`, `--dump-every N` | PNGs of frames. |
| `--ascii-end` | Print the text screen at exit. |
| `--frame-log FILE` | Per frame: hash, CPU cycles, PC. |
| `--type FRAME:TEXT` | Type text from a frame on, with escapes like `\n` and `{WAIT n}`, and key names such as `{LEFT}`, `{BS}`, `{BREAK}`. |
| `--mzf FILE` | Put an MZF on the tape. `--mzf-direct` / `--mzf-direct-frame N` load it into RAM instead. |
| `--tape-image FILE` | Mount a tape image (S0). Also `--tape-readonly`, `--tape-rewind`. |
| `--fast-tape STEP` | The OSD Fast Tape step (0–7), not a multiplier. 4 is about 8x; 5 is the fastest (capped at clk_sys/2). |
| `--fdd FILE` | Extended DSK image in floppy drive A. Also `--fdd-readonly`, and `--fdc-mode auto\|on\|off`. |
| `--mz800-mode 700\|800` | The MZ-800 rear switch (default 700, as mz800emu). |
| `--turbo N`, `--vmode` | CPU speed step; video mode. |
| `--trace-cpu FILE` | PC of every opcode fetch; `--trace-from`/`--trace-to` limit the frames. |
| `--trace-io FILE` | Every I/O write: frame, PC, port, data. |
| `--wav FILE` | Audio at 48 kHz, as `sharpmz.sv` mixes it. |
| `--dump-mem` | Main RAM at exit. |
| `--verbose` | Tape status, record FSM and pulse widths. |

## Tests

`run_tests.sh` runs everything in parallel and writes `out/test/<name>.*`:

| Test | Checks |
|---|---|
| `boot_<model>` | Boot to frame 150 and compare the text screen (MZ-80K/80C/1200/80A/700/800). |
| `kb_mz700` | Typing letters, digits, symbols, cursor keys and DEL at the MZ-700 monitor (matches mz800emu). |
| `mon_mz800` | `M` at the MZ-800 IPL starts the 9Z-504M monitor. |
| `gfx_mz800`, `pcg_mz800`, `m800_*` | MZ-800 graphics modes, write/read modes, scroll and CG-RAM, by frame hash. The pictures match mz800emu; `tests/mz800/compare_emu.sh` redoes the comparison. |
| `psg_mz800` | The PSG plays 439.8 Hz (measured from `--wav`). |
| `tape_image`, `tape_mz800` | Load from a tape image, on the MZ-700 monitor and the MZ-800 IPL. Slow; skipped with `QUICK=1`. |
| `fdd_cpm`, `fdd_hry` | CP/M 4.1 boots from disk and runs DIR; a games disk starts its file manager (pixel-identical to mz800emu). They need the images in `../software/dsk/` (not in the repository) and are skipped otherwise. |

The test programs are in `tests/mz800/`, with the Python scripts that generate them.

## Notes

- **Frames:** a frame is counted at each vsync after the machine is configured; frame 0 is the first.
- **`fb_hash`:** FNV-1a 32 over the RGB888 bytes of the active picture (e.g. 320x200), the same bytes as the PNG. mz800emu includes its border unless run with `--crop canvas`; `tests/mz800/cmp_emu.py` compares a screenshot with an mz800emu canvas.
- **Comparing traces with mz800emu:** our `--trace-cpu` logs every opcode fetch (prefixed instructions appear twice), while mz800emu logs each instruction.
- **`--dump-mem`:** reads physical main RAM, not the CPU's banked view.
- **Tape speed:** real-speed tapes have a 10 s lead-in, so use `--fast-tape 4` or `5` to save time.
- **Speed:** about 1/44 real time (~1.6M clk_sys cycles per second on an M-series Mac). A 450-frame run takes several minutes.

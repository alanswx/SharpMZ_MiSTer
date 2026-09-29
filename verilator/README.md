# SharpMZ Verilator simulation

Runs the core headless on the host: boot a machine, type at it, load MZF tapes, and write screenshots, frame logs and memory dumps. There's no DE10-Nano or Quartus build involved.

The command line matches the headless CLI added to the reference emulator in `../refs/mz800emu` (`HEADLESS_CLI.md` there), so the same scenario can be run on both and compared.

## Build and run

```sh
cd verilator
make                 # -> ./obj_dir_headless/Vtop
make test-clkgen     # GHDL testbench: clock enable rates and jitter
./obj_dir_headless/Vtop --help
```

Needs GHDL 5.x, Verilator 5.x and Python 3 (`brew install ghdl verilator`). **Run the binary from this directory**: the RAM init files are loaded from `./software/mif/*.hex`.

## How the build works

1. `ghdl synth` turns `../rtl` (VHDL) into a Verilog netlist, `gen/sharpmz.v`. Module, instance and register names survive.
2. Two fix-ups are applied to the netlist:
   - VHDL signal names that are Verilog keywords (`do`, `config`) are renamed.
   - `fix_port_aliases.py` restores `SIG <= in_port;` assignments that GHDL 5.1's Verilog writer drops. It reads them back from a VHDL netlist written in the same run.
3. `dpram`/`dprom` (Altera `altsyncram` wrappers) stay black boxes. `rtl_v/dpram.v` and `rtl_v/dprom.v` implement them, including the mixed 8/16-bit VRAM port.
4. `mif2hex.py` converts the core's `.mif` init files to `software/mif/*.mif.hex` for `$readmemh`. The ROMs are baked in, as on hardware.
5. `sim.v` stands in for `sharpmz.sv`. The C++ harness drives the ioctl bus the way `sharpmz.sv` does:
   - config register writes at `0x1000000+`;
   - MZF header and data to the tape buffer at `0x400000`/`0x410000`;
   - MZF direct loads into RAM at `0x100000+`.

## Examples

```sh
# MZ-700 boot, print the text screen
./obj_dir_headless/Vtop --model mz700 --stop-at-frame 100 --ascii-end

# Load a tape and type L at the monitor prompt
./obj_dir_headless/Vtop --mzf ../rtl/software/mzf/ramtest.mzf --type '100:L\n' \
    --stop-at-frame 900 --dump-every 100 --frame-log out/ramtest.csv --ascii-end

# Same scenario on the reference emulator
../refs/mz800emu/build/build-mz700emu-pal/mz700emu-pal --headless --model mz700 \
    --mzf ../rtl/software/mzf/ramtest.mzf --type '100:L\n' --stop-at-frame 900 --ascii-end
```

## Notes

- **Frames:** a frame is counted at each vsync rising edge after the machine is configured. Frame 0 is the first one.
- **`fb_hash`:** FNV-1a 32 over the RGB888 bytes of the unblanked picture, the same bytes written to the PNG. The core captures only the active area (e.g. 320x200); mz800emu includes its border unless run with `--crop canvas`. Compare text dumps and frame timing rather than hashes across the two.
- **`--dump-mem`:** reads physical main RAM, not the CPU's banked view.
- **Tape speed:** `--fast-tape` defaults to 1 (off, real speed), matching the reference emulator's scripted mode.
- **Speed:** about 1/44 real time (~1.6M `clk_sys` cycles per second on an M-series Mac).

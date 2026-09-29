#!/usr/bin/env python3
"""Add the MZ-800 ROMs to the combined ROM images and rewrite their MIFs.
Run after romtool (build_meminitfiles.sh).

  combined_mrom  0x1C000: the 16 KB MZ-800 ROM (1Z-013B, CG, IPL/9Z-504M).
  combined_cgrom 0x3000:  the MZ-800 CG (the MZ-700 CG with each byte bit-reversed).

usage: add_mz800_rom.py ROMDIR MIFDIR
"""
import sys

romdir, mifdir = sys.argv[1], sys.argv[2]


def read(name):
    return open(f"{romdir}/{name}", "rb").read()


def patch(name, offset, data, size=None):
    rom = bytearray(read(f"{name}.rom"))
    if size:
        rom += bytes(size - len(rom))
    rom[offset:offset + len(data)] = data
    open(f"{romdir}/{name}.rom", "wb").write(rom)
    with open(f"{mifdir}/{name}.mif", "w") as f:
        f.write(f"DEPTH = {len(rom)};\nWIDTH = 8;\nADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\nCONTENT BEGIN\n")
        for a in range(0, len(rom), 16):
            f.write(f"{a:04x}: " + " ".join(f"{b:02x}" for b in rom[a:a + 16]) + ";\n")
        f.write("END;\n")


mz800 = read("MZ800_0000.rom") + read("MZ800_CGROM.rom") + read("MZ800_E000.rom")
assert len(mz800) == 0x4000
patch("combined_mrom", 0x1C000, mz800, 0x20000)
patch("combined_cgrom", 0x3000, read("MZ800_CGROM.rom"))

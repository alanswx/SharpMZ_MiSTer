#!/usr/bin/env python3
"""Add ROMs that romtool's layout has no place for to the combined ROM images, and rewrite their MIFs.
Run after romtool (build_meminitfiles.sh).

  combined_mrom  0x1C000: the 16 KB MZ-800 ROM (1Z-013B, CG, IPL/9Z-504M).
  combined_mrom  0x10800: the MZ-700 FDC ROM banks (F000-FFFF): the MZ-1E05 floppy interface ROM.
  combined_mrom  0x17800: the MZ-2000 IPL banks (40 and 80 column): the MZ-2200 IPL, as no MZ-2000 dump is known.
  combined_cgrom 0x3000:  the MZ-800 CG (the MZ-700 CG with each byte bit-reversed).

usage: patch_roms.py ROMDIR MIFDIR
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
# MROM_BANK "100001"/"100010" (sharpmz.vhd) = MZ-700 F000-F7FF / F800-FFFF.
fd700 = read("MZ-1E05.rom")
assert len(fd700) == 0x1000
patch("combined_mrom", 0x21 * 0x800, fd700)
# MROM_BANK "101111"/"110000" = MZ-2000 IPL, 40/80 column.
ipl2200 = read("MZ2200_IPL.rom")
assert len(ipl2200) == 0x800
patch("combined_mrom", 0x2F * 0x800, ipl2200)
patch("combined_mrom", 0x30 * 0x800, ipl2200)
patch("combined_cgrom", 0x3000, read("MZ800_CGROM.rom"))

# MZ-800 tests

`gfx320.mzf` (load and exec 2000h) sets the MZ-800 320x200 4-colour mode, palette 0-3 = black, light red, light green, white, and fills plane I in the top 100 lines with FF and plane II in all 200 lines with 0F. Expected picture: top half 4 white / 4 light red pixels, bottom half 4 light green / 4 black (bit 0 is the leftmost pixel).

It matches mz800emu:

    mz800emu --headless --model mz800 --type 160:M --mzf gfx320.mzf --mzf-direct --mzf-direct-frame 200 \
             --stop-at-frame 321 --screenshot 320

(mz800emu's lower lines also show whatever was in plane I before; the simulation starts with clear VRAM.)

`make_gfx320.py` writes the MZF.

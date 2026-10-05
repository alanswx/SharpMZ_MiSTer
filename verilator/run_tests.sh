#!/bin/bash
# Regression tests for the SharpMZ simulation. Run from verilator/ (make test).
#
#   boot_<model>  boot to frame 150 and compare the text screen with tests/expected/
#   kb_mz700      MZ-700: type letters, digits, symbols, cursor keys and DEL at the monitor (matches mz800emu)
#   mon_mz800     MZ-800: M at the IPL starts the 9Z-504M monitor
#   gfx_mz800     MZ-800: tests/mz800/gfx320.mzf draws 320x200 planes; frame hash compared
#                 (the picture matches mz800emu, see tests/mz800/README.md)
#   pcg_mz800     MZ-800: tests/mz800/pcg700.mzf redefines a character in the 700 mode CG-RAM (C000); frame hash
#   m800_<test>   MZ-800 graphics modes, write/read modes and hardware scroll (tests/mz800/make_gfx_modes.py);
#                 frame hash. The pictures match mz800emu (tests/mz800/compare_emu.sh).
#   beep_mz700    MZ-700: tests/sound/beep700.mzf rings the monitor BELL, then counter 0 plays 440 Hz (measured);
#   beep_mz800    the same program on the MZ-800 in 700 mode with PC0 set (the 8253 sound path and E008 gate)
#   psg_mz800     MZ-800: tests/mz800/psg440.mzf plays 439.8 Hz on the PSG; the frequency is measured from --wav
#   fdd_cpm       MZ-800: CP/M 4.1 boots from ../software/dsk/CPMv41 System.dsk, DIR; frame hash (matches
#                 mz800emu pixel for pixel). fdd_hry: CPMv41 Hry COM A autostarts its file manager.
#                 Skipped when the disk images aren't there (they are not in the repository).
#   fdd_mz80b     MZ-80B: the IPL boots SB-6511 Disk BASIC (DISK23) and CP/M 2.2 (fdd_mz80b_cpm, DISK01) from
#                 ../software/idealine/mz-80b/rb_DSK/DSK; frame hash. Skipped when the images aren't there.
#   ipl_mz2000    MZ-2000: the MZ-2200 IPL reaches "IPL is looking for a program" (frame hash at 300)
#   tape_mz80b    MZ-80B: the IPL loads SB-5520 BASIC from a tape image (../software/mz80b) to "Ready"; frame hash.
#   tape_mz2000   MZ-2000: the MZ-2200 IPL loads Gang Man (../software/mz2200) to its title; frame hash.
#                 Both skipped when the tapes aren't there, and with QUICK=1 (the MZ-80B model is slow to simulate).
#   ipl_mz1500    MZ-1500: the 9Z-502M IPL menu ("Make ready QD"); frame hash at 150.
#   fdd_hd        MZ-800: 1.44 MB image on unit 2 (--fdd-b-hd); a sector 1.45 MB into the image written and read
#                 back by tests/fdd/fdhd.mzf (status bytes, count, data). Skipped without ../software/dsk/_Vzor144.dsk.
#   prn_mz700/800 tests/printer/prntest.mzf prints through the printer port; the bytes decoded from the UART match
#   joy_mz800     MZ-800: tests/mz800/joytest.mzf strobes the 8255 with 07, EF (PA4 low: joystick 1) and FF and reads F0/F1
#                 with right + fire 1 held (--joy0 17): E7 FF E7 FF
#   rd_mz800      MZ-800: tests/mz800/ramdisk.mzf writes 5A C3 to the RAM disk board (--ramdisk) and reads them back
#   kb_mz80k/80a  type AB, cursor LEFT, C at the monitor prompt: *AC (LEFT needs the keymap's added SHIFT)
#   cg_mz1500     MZ-1500: tests/mz1500/cgread.mzf reads the CG ROM through OUT E5 0 and prints the 8 bytes of 'F' in
#                 hex, bit 7 = left pixel as the PCG (MAME's mz700fon.jpn bit-reversed: 7E40407840404000)
#   qd_mz1500     MZ-1500: Q loads Lode Runner from a Quick Disk dump (../software/mz1500); PCG title, frame hash at 600
#                 (pixel-identical to mz1500emu). Skipped without the image and with QUICK=1.
#   fdd_mz700     MZ-700: boot a disk made by tools/make_boot_disk.py from ramtest.mzf with J F000 (MZ-1E05 ROM)
#   tape_mz800    MZ-800: the IPL (C) loads ramtest from the same tape image
#   tape_image    load ramtest from an MZT through the tape image slot (fast tape)
#
# Tests run in parallel; each writes to out/test/<name>.log. Set QUICK=1 to skip
# the tape test (it takes several minutes).

cd "$(dirname "$0")"
BIN=${BIN:-./obj_dir_headless/Vtop}
OUT=${OUT:-out/test}
mkdir -p "$OUT"

MODELS="mz80k mz80c mz1200 mz80a mz700 mz800"
pids=()
names=()

for m in $MODELS; do
    ( $BIN --model $m --stop-at-frame 150 --ascii-end --quiet > "$OUT/boot_$m.txt" 2> "$OUT/boot_$m.log" ) &
    pids+=($!); names+=("boot_$m")
done

( $BIN --model mz700 --type '120:ABCXYZ0123456789-,./;[] QABCD{LEFT}{LEFT}X{BS}' --stop-at-frame 400 --ascii-end --quiet \
      > "$OUT/kb_mz700.txt" 2> "$OUT/kb_mz700.log" ) &
pids+=($!); names+=("kb_mz700")
for m in mz80k mz80a; do      # cursor keys need the added SHIFT (fix_keymap.py); 120 ms presses as a typist's
    ( $BIN --model $m --type '150:AB{LEFT}C' --type-rate 6:6 --stop-at-frame 300 --ascii-end --quiet 2> "$OUT/kb_$m.log" \
          | sed -n 2p > "$OUT/kb_$m.txt" ) &
    pids+=($!); names+=("kb_$m")
done
( $BIN --model mz800 --type 160:M --stop-at-frame 300 --ascii-end --quiet > "$OUT/mon_mz800.txt" 2> "$OUT/mon_mz800.log" ) &
pids+=($!); names+=("mon_mz800")
( $BIN --model mz800 --mzf tests/mz800/gfx320.mzf --mzf-direct --mzf-direct-frame 20 --type 200:M --type '280:J2000\n' \
      --stop-at-frame 401 --frame-log "$OUT/gfx_mz800.csv" --quiet > /dev/null 2> "$OUT/gfx_mz800.log"
  awk -F, '$1==400 {print $2}' "$OUT/gfx_mz800.csv" > "$OUT/gfx_mz800.txt" ) &
pids+=($!); names+=("gfx_mz800")
( $BIN --model mz800 --mzf tests/mz800/pcg700.mzf --mzf-direct --mzf-direct-frame 20 --type 200:M --type '280:J2000\n' \
      --stop-at-frame 341 --frame-log "$OUT/pcg_mz800.csv" --quiet > /dev/null 2> "$OUT/pcg_mz800.log"
  awk -F, '$1==340 {print $2}' "$OUT/pcg_mz800.csv" > "$OUT/pcg_mz800.txt" ) &
pids+=($!); names+=("pcg_mz800")
for t in gfx640 gfx640h gfx320h gfx320b gfx320x gfxwm gfxwm640 gfxrw gfxscr gfxscr640 gfxscr640b; do
    ( $BIN --model mz800 --mzf tests/mz800/$t.mzf --mzf-direct --mzf-direct-frame 20 --type 200:M --type '280:J2000\n' \
          --stop-at-frame 401 --frame-log "$OUT/m800_$t.csv" --quiet > /dev/null 2> "$OUT/m800_$t.log"
      awk -F, '$1==400 {print $2}' "$OUT/m800_$t.csv" > "$OUT/m800_$t.txt" ) &
    pids+=($!); names+=("m800_$t")
done
( $BIN --model mz2000 --stop-at-frame 301 --frame-log "$OUT/ipl_mz2000.csv" --quiet > /dev/null 2> "$OUT/ipl_mz2000.log"
  awk -F, '$1==300 {print $2}' "$OUT/ipl_mz2000.csv" > "$OUT/ipl_mz2000.txt" ) &
pids+=($!); names+=("ipl_mz2000")
( $BIN --model mz1500 --stop-at-frame 151 --frame-log "$OUT/ipl_mz1500.csv" --quiet > /dev/null 2> "$OUT/ipl_mz1500.log"
  awk -F, '$1==150 {print $2}' "$OUT/ipl_mz1500.csv" > "$OUT/ipl_mz1500.txt" ) &
pids+=($!); names+=("ipl_mz1500")
# Printer: tests/printer/prntest.mzf prints two lines through the Sharp handshake (MZ-700 ports FE/FF, MZ-800 PIO);
# the sim decodes the UART line (9600 8N1) into the .bin, compared as hex with tests/expected/prn_*.txt.
( $BIN --model mz700 --mzf tests/printer/prntest.mzf --mzf-direct --mzf-direct-frame 20 --type '100:J2000\n' \
      --stop-at-frame 220 --printer "$OUT/prn_mz700.bin" --quiet > /dev/null 2> "$OUT/prn_mz700.log"; \
  xxd -p "$OUT/prn_mz700.bin" > "$OUT/prn_mz700.txt" ) &
pids+=($!); names+=("prn_mz700")
( $BIN --model mz800 --mzf tests/printer/prntest.mzf --mzf-direct --mzf-direct-frame 20 --type '200:M' \
      --type '280:J2000\n' --stop-at-frame 400 --printer "$OUT/prn_mz800.bin" --quiet > /dev/null 2> "$OUT/prn_mz800.log"; \
  xxd -p "$OUT/prn_mz800.bin" > "$OUT/prn_mz800.txt" ) &
pids+=($!); names+=("prn_mz800")
# 1.44 MB disk: tests/fdd/fdhd.mzf writes and reads back track 79 side 1 sector 17 (1.45 MB into the image) on
# unit 2 (--fdd-b-hd). Needs ../software/dsk/_Vzor144.dsk; skipped without it.
if [ -f ../software/dsk/_Vzor144.dsk ]; then
    cp ../software/dsk/_Vzor144.dsk "$OUT/fdd_hd.dsk"
    ( $BIN --model mz800 --fdd-b "$OUT/fdd_hd.dsk" --fdd-b-hd --mzf tests/fdd/fdhd.mzf --mzf-direct --mzf-direct-frame 20 \
          --type '200:M' --type '280:J2000\n' --stop-at-frame 420 --dump-mem 2FF0:30:"$OUT/fdd_hd.bin" --quiet \
          > /dev/null 2> "$OUT/fdd_hd.log"; xxd -p "$OUT/fdd_hd.bin" > "$OUT/fdd_hd.txt" ) &
    pids+=($!); names+=("fdd_hd")
fi
cp tests/mz800/joytest.mzf "$OUT/joy_mz800.mzt"
( $BIN --model mz800 --joy0 17 --fast-tape 4 --tape-image "$OUT/joy_mz800.mzt" --type '160:C' --stop-at-frame 700 \
      --ascii-end --quiet 2> "$OUT/joy_mz800.log" | head -1 | cut -c1-8 > "$OUT/joy_mz800.txt" ) &
pids+=($!); names+=("joy_mz800")
cp tests/mz800/ramdisk.mzf "$OUT/rd_mz800.mzt"
( $BIN --model mz800 --ramdisk --fast-tape 4 --tape-image "$OUT/rd_mz800.mzt" --type '160:C' --stop-at-frame 700 \
      --ascii-end --quiet 2> "$OUT/rd_mz800.log" | head -1 | cut -c1-4 > "$OUT/rd_mz800.txt" ) &
pids+=($!); names+=("rd_mz800")
cp tests/mz1500/cgread.mzf "$OUT/cg_mz1500.mzt"
( $BIN --model mz1500 --fast-tape 6 --tape-image "$OUT/cg_mz1500.mzt" --type '150:C' --stop-at-frame 450 \
      --ascii-end --quiet 2> "$OUT/cg_mz1500.log" | head -1 | cut -c1-16 > "$OUT/cg_mz1500.txt" ) &
pids+=($!); names+=("cg_mz1500")
QDF="../software/mz1500/Lode Runner (1985)(Broderbund Software)(Universe) Side A.qdf"
if [ -z "${QUICK:-}" ] && [ -f "$QDF" ]; then
    cp "$QDF" "$OUT/qd_mz1500.qdf"
    ( $BIN --model mz1500 --qd "$OUT/qd_mz1500.qdf" --type '150:Q' --stop-at-frame 601 \
          --frame-log "$OUT/qd_mz1500.csv" --quiet > /dev/null 2> "$OUT/qd_mz1500.log"
      awk -F, '$1==600 {print $2}' "$OUT/qd_mz1500.csv" > "$OUT/qd_mz1500.txt" ) &
    pids+=($!); names+=("qd_mz1500")
fi
python3 ../tools/make_boot_disk.py ../rtl/software/mzf/ramtest.mzf "$OUT/fdd_mz700.dsk" > /dev/null
( $BIN --model mz700 --fdd "$OUT/fdd_mz700.dsk" --fdd-readonly --type '120:JF000\n' --stop-at-frame 500 \
      --ascii-end --quiet > "$OUT/fdd_mz700.txt" 2> "$OUT/fdd_mz700.log" ) &
pids+=($!); names+=("fdd_mz700")
DSK=../software/dsk
if [ -f "$DSK/CPMv41 System.dsk" ]; then
    cp "$DSK/CPMv41 System.dsk" "$OUT/fdd_cpm.dsk"
    ( $BIN --model mz800 --fdd "$OUT/fdd_cpm.dsk" --fdd-readonly --type '200:DIR\n' --stop-at-frame 451 \
          --frame-log "$OUT/fdd_cpm.csv" --quiet > /dev/null 2> "$OUT/fdd_cpm.log"
      awk -F, '$1==450 {print $2}' "$OUT/fdd_cpm.csv" > "$OUT/fdd_cpm.txt" ) &
    pids+=($!); names+=("fdd_cpm")
fi
if [ -f "$DSK/CPMv41 Hry COM A.dsk" ]; then
    cp "$DSK/CPMv41 Hry COM A.dsk" "$OUT/fdd_hry.dsk"
    ( $BIN --model mz800 --fdd "$OUT/fdd_hry.dsk" --fdd-readonly --stop-at-frame 601 \
          --frame-log "$OUT/fdd_hry.csv" --quiet > /dev/null 2> "$OUT/fdd_hry.log"
      awk -F, '$1==600 {print $2}' "$OUT/fdd_hry.csv" > "$OUT/fdd_hry.txt" ) &
    pids+=($!); names+=("fdd_hry")
fi
( $BIN --model mz800 --mzf tests/mz800/psg440.mzf --mzf-direct --mzf-direct-frame 20 --type 200:M --type '280:J2000\n' \
      --stop-at-frame 400 --wav "$OUT/psg_mz800.wav" --quiet > /dev/null 2> "$OUT/psg_mz800.log"
  python3 tests/wav_freq.py "$OUT/psg_mz800.wav" 7.0 1.0 > "$OUT/psg_mz800.txt" ) &
pids+=($!); names+=("psg_mz800")
( $BIN --model mz700 --mzf tests/sound/beep700.mzf --mzf-direct --mzf-direct-frame 20 --type '150:J2000\n' \
      --stop-at-frame 450 --wav "$OUT/beep_mz700.wav" --quiet > /dev/null 2> "$OUT/beep_mz700.log"
  python3 tests/wav_freq.py "$OUT/beep_mz700.wav" 6.0 2.0 > "$OUT/beep_mz700.txt" ) &
pids+=($!); names+=("beep_mz700")
( $BIN --model mz800 --mzf tests/sound/beep700.mzf --mzf-direct --mzf-direct-frame 20 --type 200:M --type '280:J2000\n' \
      --stop-at-frame 500 --wav "$OUT/beep_mz800.wav" --quiet > /dev/null 2> "$OUT/beep_mz800.log"
  python3 tests/wav_freq.py "$OUT/beep_mz800.wav" 8.0 1.5 > "$OUT/beep_mz800.txt" ) &
pids+=($!); names+=("beep_mz800")

if [ -z "$QUICK" ]; then
    cat ../rtl/software/mzf/ramtest.mzf ../rtl/software/mzf/tapecheck.mzf > "$OUT/two.mzt"
    cp "$OUT/two.mzt" "$OUT/two800.mzt"
    ( $BIN --model mz800 --fast-tape 4 --tape-image "$OUT/two800.mzt" --type '160:C' \
          --stop-at-frame 700 --ascii-end --quiet > "$OUT/tape_mz800.txt" 2> "$OUT/tape_mz800.log" ) &
    pids+=($!); names+=("tape_mz800")
    ( $BIN --model mz700 --fast-tape 4 --tape-image "$OUT/two.mzt" --type '100:L\n' \
          --stop-at-frame 700 --ascii-end --quiet > "$OUT/tape_image.txt" 2> "$OUT/tape_image.log" ) &
    pids+=($!); names+=("tape_image")
fi
if [ -z "${QUICK:-}" ]; then
    for t in "tape_mz80b|mz80b|../software/mz80b/SB-5520.mzt" \
             "tape_mz2000|mz2000|../software/mz2200/Gang Man (1983)(Hudson Soft)(Fumihiko Itagaki) [CT].mzt"; do
        IFS='|' read -r n m f <<< "$t"
        if [ -f "$f" ]; then
            cp "$f" "$OUT/$n.mzt"
            ( $BIN --model $m --fast-tape 5 --tape-image "$OUT/$n.mzt" --stop-at-frame 2401 \
                  --frame-log "$OUT/$n.csv" --quiet > /dev/null 2> "$OUT/$n.log"
              awk -F, '$1==2400 {print $2}' "$OUT/$n.csv" > "$OUT/$n.txt" ) &
            pids+=($!); names+=("$n")
        fi
    done
fi
RB=../software/idealine/mz-80b/rb_DSK/DSK
for t in "fdd_mz80b DISK23 900" "fdd_mz80b_cpm DISK01 1200"; do
    set -- $t
    if [ -f "$RB/$2.DSK" ]; then
        cp "$RB/$2.DSK" "$OUT/$1.dsk"
        ( $BIN --model mz80b --fdd "$OUT/$1.dsk" --fdd-readonly --stop-at-frame $(($3 + 1)) \
              --frame-log "$OUT/$1.csv" --quiet > /dev/null 2> "$OUT/$1.log"
          awk -F, -v f=$3 '$1==f {print $2}' "$OUT/$1.csv" > "$OUT/$1.txt" ) &
        pids+=($!); names+=("$1")
    fi
done

for p in "${pids[@]}"; do wait $p; done

fail=0
for n in "${names[@]}"; do
    case $n in
        boot_*|mon_*|gfx_*|pcg_*|m800_*|kb_*|fdd_*|ipl_*|qd_*|cg_*|rd_*|joy_*|prn_*|tape_mz80b|tape_mz2000)
            if diff -q "tests/expected/$n.txt" "$OUT/$n.txt" > /dev/null; then
                echo "PASS $n"
            else
                echo "FAIL $n"; diff "tests/expected/$n.txt" "$OUT/$n.txt" | head -5; fail=1
            fi ;;
        psg_mz800|beep_mz700|beep_mz800)
            if awk '{exit !($1 > 435 && $1 < 445)}' "$OUT/$n.txt"; then
                echo "PASS $n ($(cat "$OUT/$n.txt") Hz)"
            else
                echo "FAIL $n"; cat "$OUT/$n.txt"; fail=1
            fi ;;
        tape_image|tape_mz800)
            if grep -q "RAM TESTER" "$OUT/tape_image.txt"; then
                echo "PASS $n"
            else
                echo "FAIL $n"; head -5 "$OUT/tape_image.txt"; fail=1
            fi ;;
    esac
done
exit $fail

#!/bin/bash
# Regression tests for the SharpMZ simulation. Run from verilator/ (make test).
#
#   boot_<model>  boot to frame 150 and compare the text screen with tests/expected/
#   mon_mz800     MZ-800: M at the IPL starts the 9Z-504M monitor
#   gfx_mz800     MZ-800: tests/mz800/gfx320.mzf draws 320x200 planes; frame hash compared
#                 (the picture matches mz800emu, see tests/mz800/README.md)
#   pcg_mz800     MZ-800: tests/mz800/pcg700.mzf redefines a character in the 700 mode CG-RAM (C000); frame hash
#   m800_<test>   MZ-800 graphics modes, write/read modes and hardware scroll (tests/mz800/make_gfx_modes.py);
#                 frame hash. The pictures match mz800emu (tests/mz800/compare_emu.sh).
#   psg_mz800     MZ-800: tests/mz800/psg440.mzf plays 439.8 Hz on the PSG; the frequency is measured from --wav
#   tape_mz800    MZ-800: the IPL (C) loads ramtest from the same tape image
#   tape_image    load ramtest from an MZT through the tape image slot (fast tape)
#
# Tests run in parallel; each writes to out/test/<name>.log. Set QUICK=1 to skip
# the tape test (it takes several minutes).

cd "$(dirname "$0")"
BIN=./obj_dir_headless/Vtop
OUT=out/test
mkdir -p "$OUT"

MODELS="mz80k mz80c mz1200 mz80a mz700 mz800"
pids=()
names=()

for m in $MODELS; do
    ( $BIN --model $m --stop-at-frame 150 --ascii-end --quiet > "$OUT/boot_$m.txt" 2> "$OUT/boot_$m.log" ) &
    pids+=($!); names+=("boot_$m")
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
for t in gfx640 gfx640h gfx320h gfx320b gfx320x gfxwm gfxwm640 gfxrw gfxscr gfxscr640; do
    ( $BIN --model mz800 --mzf tests/mz800/$t.mzf --mzf-direct --mzf-direct-frame 20 --type 200:M --type '280:J2000\n' \
          --stop-at-frame 401 --frame-log "$OUT/m800_$t.csv" --quiet > /dev/null 2> "$OUT/m800_$t.log"
      awk -F, '$1==400 {print $2}' "$OUT/m800_$t.csv" > "$OUT/m800_$t.txt" ) &
    pids+=($!); names+=("m800_$t")
done
( $BIN --model mz800 --mzf tests/mz800/psg440.mzf --mzf-direct --mzf-direct-frame 20 --type 200:M --type '280:J2000\n' \
      --stop-at-frame 400 --wav "$OUT/psg_mz800.wav" --quiet > /dev/null 2> "$OUT/psg_mz800.log"
  python3 tests/wav_freq.py "$OUT/psg_mz800.wav" 7.0 1.0 > "$OUT/psg_mz800.txt" ) &
pids+=($!); names+=("psg_mz800")

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

for p in "${pids[@]}"; do wait $p; done

fail=0
for n in "${names[@]}"; do
    case $n in
        boot_*|mon_*|gfx_*|pcg_*|m800_*)
            if diff -q "tests/expected/$n.txt" "$OUT/$n.txt" > /dev/null; then
                echo "PASS $n"
            else
                echo "FAIL $n"; diff "tests/expected/$n.txt" "$OUT/$n.txt" | head -5; fail=1
            fi ;;
        psg_mz800)
            if awk '{exit !($1 > 435 && $1 < 445)}' "$OUT/psg_mz800.txt"; then
                echo "PASS $n ($(cat "$OUT/psg_mz800.txt") Hz)"
            else
                echo "FAIL $n"; cat "$OUT/psg_mz800.txt"; fail=1
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

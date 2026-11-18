#!/bin/sh
# shots.sh EMU SD NAME SECONDS T1 T2 ... - run tests/NAME.keys (keys and mouse) on a fresh
# copy of the SD card SD (with /SYSTEM/NODESK: the text shell, unless DESK=1), take a picture at each time Tn (seconds), and write
#   build/NAMEn.ppm, build/NAME.md5 (their md5), build/NAME.out (console),
#   build/NAME.err (emu816's own log, e.g. the classic-machine ops).
set -e
emu=$1 sd=$2 name=$3 secs=$4
shift 4
rm -rf build/run-pic
cp -r "$sd" build/run-pic
[ -n "$DESK" ] || touch build/run-pic/SYSTEM/NODESK   # the text shell (DESK=1: the Desktop)
# the Desktop sessions get a fixed Programs menu (tests/desk.programs), so programs added
# to the card do not change their pictures; PREP: a command run on the card copy first
[ -z "$DESK" ] || cp tests/desk.programs build/run-pic/SYSTEM/PROGRAMS
[ -z "$PREP" ] || (cd build/run-pic && sh -c "$PREP")
n=0 args=""
for t in "$@"; do n=$((n + 1)); args="$args --shot build/$name$n.ppm --shot-at $t"; done
$emu --headless --sd build/run-pic --max-seconds "$secs" \
    --keys "$(python3 tests/keyscript.py "tests/$name.keys")" \
    --mouse "$(python3 tests/keyscript.py --mouse "tests/$name.keys")" \
    $args "$sd/SYSTEM/HORIZON.SYS" > "build/$name.out" 2> "build/$name.err" || true
files=$(i=0; while [ $i -lt $n ]; do i=$((i + 1)); echo "$name$i.ppm"; done | LC_ALL=C sort)
(cd build && md5sum $files) > "build/$name.md5"   # (exactly these: desk14*.ppm are not desk1*)
# SHOTPNG=1 (where disk space is short): keep PNG copies (build/NAMEn.png) instead of the
# PPM files once their md5 is taken
if [ -n "$SHOTPNG" ]; then
  python3 -c "import sys; from PIL import Image; [Image.open('build/' + f).save('build/' + f[:-4] + '.png') for f in sys.argv[1:]]" $files
  (cd build && rm -f $files)
fi

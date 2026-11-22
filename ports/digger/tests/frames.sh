#!/bin/sh
# tests/frames.sh [HORIZON] [--update] - the pictures' test: a recorded game (tests/play.drf,
# the scripted game of tests/play.script as the game itself recorded it: its keys at each
# game frame) played back, and a picture taken at each game frame of tests/frames.txt,
# compared with tests/ref/frame-N.png pixel for pixel.
#
# The pictures are of game frames, not of moments: the program reads the frames from
# SHOTS.TXT, stops at each (the frame drawn shown, the view put at its place), prints
# "digger: shot N", and the emulator takes the picture then (run816.py --shot-on). Nothing
# else is in them: the playback's game is the same frame by frame however fast or slow the
# program runs, so the pictures do not move when the program's timing does (a change of
# its code or of the SDK, the code's place in its banks). A change in what is drawn does.
# --update: write the references (look at them first: build/frames/autoN.png).
HZ=${1:-../../horizon}
UPD=$2
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
cp tests/frames.txt build/SHOTS.TXT
python3 ../../sdk/tools/run816.py DIGGER.PRG --horizon "$HZ" --mode shell \
  --args "/Q /S:0 /P:PLAY.DRF" --file DIGGER.DAT:/APPS/DIGGER.DAT \
  --file tests/play.drf:/APPS/PLAY.DRF --file build/SHOTS.TXT:/APPS/SHOTS.TXT \
  --shot-on "digger: shot" --seconds 80 --out build/frames >/dev/null 2>&1
want=$(wc -w < tests/frames.txt)
got=$(grep -ac '^digger: shot' build/frames/console.txt)
if [ "$got" != "$want" ]; then
  echo "FAIL  frames: $got of $want pictures taken (build/frames/console.txt)"
  exit 1
fi
python3 tests/cmpshots.py build/frames tests/ref frame --prefix auto $UPD

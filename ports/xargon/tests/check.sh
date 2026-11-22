#!/bin/sh
# tests/check.sh [HORIZON] [--refs] - Xargon's tests (make test), in the emulator:
#
#   1. the scripted game (tests/play.script): the title, the main menu, a game saved on the
#      map, the map's paths and its journal, level 1 (a jump, a shot, the water: the hero
#      dies and starts again), the game's menu, quitting, the high scores, the game loaded
#      again. Checked: the save on the card (SAVE_0.XR1, the name in CONFIG.XR1); the game
#      loaded back where it was saved; the sound (Lau's writes for the effects, the music
#      and the effects in the recorded output: loud enough, not clipped); the frame rate;
#      the screenshots against tests/play.md5 (make refs: the pictures in tests/ref/ and
#      their checksums, after a change meant to show: look at them first)
#   2. the recorded demo (tests/demo.script: DEMO-PREVIEW, DEMO_MAC.XR0) played twice, the
#      second time on a slower machine (/BUSY:30: 30 ms more of the CPU each game frame,
#      so the frames are late and fall elsewhere): at its frame 1,500 (of 5,077) the game
#      must be exactly as
#      tests/demo.ref says (score, health, emeralds, hero, objects): the game logic, frame
#      for frame, and the compiler
#
# The game's own files must be in data/card (make data).
HZ=${1:-../../horizon}
REFS=$2
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
FILES=
for f in data/card/*; do FILES="$FILES --file $f:/GAMES/XARGON/$(basename "$f")"; done
run() {
  a=$1
  shift
  python3 ../../sdk/tools/run816.py XARGON1.PRG --horizon "$HZ" \
    --dest /GAMES/XARGON/XARGON1.PRG --mode shell --args "/STATS$a" $FILES "$@"
}
mkdir -p build/test

# ---------------------------------------------------------------- 1. the scripted game
run "" --script tests/play.script --seconds 68 --log-lau --wav build/test/play.wav \
  --out build/test/play > build/test/play.log 2>&1 || bad "the scripted game's run (killed?)"
con=build/test/play/console.txt
card=build/test/play/card/GAMES/XARGON
if grep -aq 'xargon: sound: effects 1, music 1 (Lau 1, OPL2 1, playing 1)' "$con"; then
  ok "sound: the effects on Lau and the music on the OPL2"
else bad "sound: not both on (console: $(grep -a 'xargon: sound' "$con" | tail -1))"; fi
n=$(grep -c '^lau ' build/test/play/emu.err)
if [ "$n" -gt 100 ]; then ok "sound: $n writes to Lau (the effects)"
else bad "sound: only $n writes to Lau"; fi
if python3 tests/wavcheck.py build/test/play.wav; then :; else fail=1; fi
if ls "$card" | grep -qi '^save_0\.xr1$' && grep -aq 'HZTEST' "$card"/[Cc][Oo][Nn][Ff][Ii][Gg].[Xx][Rr]1; then
  ok "the game saved: SAVE_0.XR1, HZTEST in CONFIG.XR1"
else bad "no SAVE_0.XR1 or no HZTEST in CONFIG.XR1"; fi
# the last position reported (every 10 s): after the load, the map where it was saved
last=$(grep -a '^xargon: hero' "$con" | tail -1 | tr -d '\r')
case "$last" in
  "xargon: hero 5 at 80, 64 (state "*", level 127,"*) ok "the game loaded: $last";;
  *) bad "the game loaded back: '$last' (want the map's hero at 80, 64)";;
esac
fr=$(grep -a 'game frames' "$con" | tail -1 | tr -d '\r')
if [ -n "$fr" ]; then ok "frames: $fr"; else bad "no frame statistics"; fi
if [ "$REFS" = --refs ]; then
  python3 tests/shots.py build/test/play tests/play.md5 --update || fail=1
else
  python3 tests/shots.py build/test/play tests/play.md5 || fail=1
fi

# ---------------------------------------------------------------- 2. the recorded demo
want=$(grep -v '^#' tests/demo.ref | head -1)
for k in 1 2; do
  extra=
  [ $k = 2 ] && extra=" /BUSY:30"
  run "$extra" --script tests/demo.script --seconds 160 --out build/test/demo$k \
    > build/test/demo$k.log 2>&1 || bad "the demo's run $k (killed?)"
  got=$(grep -a '^xargon: demo reached' build/test/demo$k/console.txt | head -1 | tr -d '\r')
  if [ "$got" = "$want" ]; then ok "the demo$([ $k = 2 ] && echo ', slower,') as tests/demo.ref: $got"
  else bad "the demo$([ $k = 2 ] && echo ', slower,'): '$got', want '$want'"; fi
done

[ $fail = 0 ] && echo "xargon: ALL TESTS PASSED"
exit $fail

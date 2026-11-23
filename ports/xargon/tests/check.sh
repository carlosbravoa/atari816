#!/bin/sh
# tests/check.sh [HORIZON] [--refs] - Xargon's tests (make test), in the emulator:
#
#   1. the scripted game (tests/play.script): the title, the main menu, a game saved on the
#      map, the map's paths and its journal, level 1 (a jump, a shot, the water: the hero
#      dies and starts again), the game's menu, quitting, the high scores, the game loaded
#      again. Checked: the save on the card (SAVE_0.XR1, the name in CONFIG.XR1); the game
#      loaded back where it was saved; the sound (Lau's writes for the effects, the music
#      and the effects in the recorded output: loud enough, not clipped); the frame rate;
#      the pictures of its screens (tests/play.shots) against tests/play.md5; the heap at
#      each board's start the same each time (no leak), and room on every board of the
#      three episodes for the longest text window (tests/heapcheck.py)
#   2. the recorded demo (tests/demo.script: DEMO-PREVIEW, DEMO_MAC.XR0) played twice, the
#      second time on a slower machine (/BUSY:30: 30 ms more of the CPU each game frame,
#      so the frames are late and fall elsewhere): at its frame 1,500 (of 5,077) the game
#      must be exactly as tests/demo.ref says (score, health, emeralds, hero, objects): the
#      game logic, frame for frame, and the compiler; and both runs' pictures (the title,
#      the menu, five frames of the demo: tests/demo.shots) as tests/demo.md5; the heap at
#      its boards' starts as in 1.
#   3. the help (tests/help.script): INSTRUCTIONS on the title's menu twice, the heap's
#      tightest place (the longest text over the board with the most texts). And no
#      "out of memory" in any run
#
# The pictures are of the game's frames, not of moments: the program (/SHOTS:FILE,
# horizon/hz_frame.c) stops at each screen of the list, counted by the game (a screen that
# waits for keys: its Nth key poll; a level: its game frame N), prints "xargon: shot K",
# and the emulator takes the picture then (run816.py --shot-on); the scripts wait for those
# lines before their next keys. So the pictures do not move when the program's speed does
# (a change of its code, the compiler, /BUSY). --refs (make refs): the references written
# anew (tests/play.md5, tests/demo.md5, the pictures in tests/ref/: look at them first).
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
rm -rf build/test
mkdir -p build/test

# (2.'s two runs of the demo and 3. go on meanwhile)
run " /SHOTS:PLAY.SHT" --file tests/play.shots:/GAMES/XARGON/PLAY.SHT \
  --script tests/help.script --shot-on "xargon: shot" --seconds 30 \
  --out build/test/help > build/test/help.log 2>&1 && touch build/test/help.ok &
for k in 1 2; do
  extra=
  [ $k = 2 ] && extra=" /BUSY:30"
  run " /SHOTS:DEMO.SHT$extra" --file tests/demo.shots:/GAMES/XARGON/DEMO.SHT \
    --script tests/demo.script --shot-on "xargon: shot" --seconds 160 \
    --out build/test/demo$k > build/test/demo$k.log 2>&1 && touch build/test/demo$k.ok &
done

# ---------------------------------------------------------------- 1. the scripted game
run " /SHOTS:PLAY.SHT" --file tests/play.shots:/GAMES/XARGON/PLAY.SHT \
  --script tests/play.script --shot-on "xargon: shot" --seconds 80 --log-lau \
  --wav build/test/play.wav --out build/test/play > build/test/play.log 2>&1 ||
  bad "the scripted game's run (killed, or a wait not met: build/test/play.log)"
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
# the heap at each board's start (loadboard, after the last board's texts were freed): the
# same every time (title, map, level 1, the level again after a death, the title, the map
# loaded: nothing kept), no "out of memory"; and room on every board for the help text
before=$(grep -a '^xargon: heap before' "$con" | sed 's/.*: //' | tr -d '\r' | sort -u)
nb=$(grep -ac '^xargon: heap before' "$con")
if [ "$nb" -ge 6 ] && [ "$(echo "$before" | wc -l)" = 1 ]; then
  ok "heap: the same at all $nb board starts ($before)"
else bad "heap: board starts $nb, with $(echo "$before" | tr '\n' '/') (a leak?)"; fi
python3 tests/heapcheck.py data/card "$con" || fail=1
UPD=
[ "$REFS" = --refs ] && UPD=--update
python3 tests/shots.py build/test/play tests/play.md5 $UPD || fail=1

# ---------------------------------------------------------------- 2. the recorded demo
wait
want=$(grep -v '^#' tests/demo.ref | head -1)
for k in 1 2; do
  [ -f build/test/demo$k.ok ] || bad "the demo's run $k (killed, or a wait not met: build/test/demo$k.log)"
  got=$(grep -a '^xargon: demo reached' build/test/demo$k/console.txt | head -1 | tr -d '\r')
  if [ "$got" = "$want" ]; then ok "the demo$([ $k = 2 ] && echo ', slower,') as tests/demo.ref: $got"
  else bad "the demo$([ $k = 2 ] && echo ', slower,'): '$got', want '$want'"; fi
  # the heap at the demo's boards: the title's (the menu, the demo's first board) as in
  # the scripted game; the boards the macro goes to (its 2,360 bytes held) all the same
  c=build/test/demo$k/console.txt
  b=$(grep -a '^xargon: heap before intro' $c | sed 's/.*: //' | tr -d '\r' | sort -u)
  m=$(grep -a '^xargon: heap before' $c | grep -av 'before intro' | sed 's/.*: //' | tr -d '\r' | sort -u)
  n=$(grep -ac '^xargon: heap before' $c)
  if [ "$n" -ge 4 ] && [ "$b" = "$before" ] && [ "$(echo "$m" | wc -l)" = 1 ]; then
    ok "heap: the demo's $n board starts$([ $k = 2 ] && echo ', slower,'): the title's as the game's, the macro's boards all $m"
  else bad "heap: the demo's $n board starts$([ $k = 2 ] && echo ', slower,'): the title's $(echo "$b" | tr '\n' '/') (want $before), the others $(echo "$m" | tr '\n' '/')"; fi
  if [ $k = 1 ]; then python3 tests/shots.py build/test/demo1 tests/demo.md5 $UPD || fail=1
  else python3 tests/shots.py build/test/demo2 tests/demo.md5 || fail=1; fi
done

# ---------------------------------------------------------------- 3. the help on the title
[ -f build/test/help.ok ] || bad "the help's run (killed, or a wait not met: build/test/help.log)"
h=$(grep -a '^xargon: heap with the help' build/test/help/console.txt | tr -d '\r')
n=$(echo "$h" | grep -c .)
if [ "$n" = 2 ]; then ok "the help opened twice on the title's board ($(echo "$h" | tail -1 | sed 's/.*help: //'))"
else bad "the help opened $n times on the title's board, want 2"; fi

if grep -a 'out of memory' build/test/*/console.txt; then bad "out of memory"; fi
[ $fail = 0 ] && echo "xargon: ALL TESTS PASSED"
exit $fail

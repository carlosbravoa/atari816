#!/bin/sh
# tests/check.sh - after make test's scripted game (tests/play.script, in build/test):
#   1. the high score was saved: DIGGER.SCO on the card has HZD with 125 points;
#   2. the sound: POKEY's 16-bit voices were set up and played (emu816 --log-sound);
#   3. the pictures of a recorded game at given game frames are the reference pictures
#      (tests/frames.sh, tests/ref/frame-N.png);
#   4. upstream's recorded games play out as upstream's (tests/drf.sh).
# HORIZON: the Horizon tree (0.28 or later: DIGGER.PRG is a large program).
HZ=${1:-../../horizon}
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
if head -c 12 build/test/card/APPS/DIGGER.SCO 2>/dev/null | grep -q '^sHZD     125'; then
  ok "the high score saved (DIGGER.SCO: HZD 125)"
else bad "DIGGER.SCO has not HZD 125"; fi
n=$(grep -c '^sound \$DB0[4-7]' build/test/emu.err)
if grep -q '^sound \$DB08 = \$78' build/test/emu.err && [ "$n" -gt 500 ]; then
  ok "sound: both 16-bit voices on (AUDCTL \$78), $n writes to the music's channels"
else bad "sound: no AUDCTL \$78 or few writes ($n)"; fi
# the game just played, recorded (F8 at the title) and played back: the same end
rec=$(ls build/test/card/APPS | grep -i '^hzd125\.drf$')
if [ -n "$rec" ]; then
  python3 ../../sdk/tools/run816.py DIGGER.PRG --horizon "$HZ" --mode shell \
    --args "/Q /S:0 /E:HZD125.DRF" --file DIGGER.DAT:/APPS/DIGGER.DAT \
    --file "build/test/card/APPS/$rec:/APPS/HZD125.DRF" --seconds 120 --out build/replay \
    >/dev/null 2>&1
  got=$(grep -a '^score=' build/replay/console.txt | tr -d '\r')
  case "$got" in
    "score=125 level=1 "*) ok "the recording of the game played back: $got";;
    *) bad "the recording played back: '$got' (want score=125 level=1)";;
  esac
else bad "no recording HZD125.DRF saved (F8)"; fi
sh tests/frames.sh "$HZ" || fail=1
sh tests/drf.sh "$HZ" || fail=1
grep -a '^digger: ' build/test/console.txt
[ $fail = 0 ] && echo "digger: ALL TESTS PASSED"
exit $fail

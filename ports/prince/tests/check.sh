#!/bin/sh
# tests/check.sh [HORIZON] [--refs] - Prince of Persia's tests (make test), in the emulator:
#
#   1. the replays (tests/replays/*.p1r, recorded with upstream SDLPoP on a PC: level 1 from
#      its start to the sword and on through ten rooms, a loose floor, a sword fight on
#      level 2) in upstream's own "validate" mode: the game's state every 10 ticks and
#      upstream's end lines must be the PC's (tests/ref/*.ref, from tests/mkref.sh)
#   2. one replay played at the game's speed (its frame waits, its drawing), on a machine
#      made 30 ms a frame slower (/BUSY:30): the same states again
#   3. pictures at ticks of the replays: their checksums (tests/frames.md5; they were equal
#      pixel for pixel to the PC's frames, tests/cmpframe.py; make check-host compares
#      them with the PC's again)
#   4. the scripted game (tests/play.script): the first screen, the title, level 1 through
#      the keyboard, a quicksave and a quickload, a pause; its console lines, QUICKSAVE.SAV
#      on the card, Lau's writes (the effects), the title music's OPL2 writes against its
#      stream (tests/oplcheck.py), the pictures (tests/play.md5)
#   5. a game saved on level 3 (Ctrl+G: PRINCE.SAV) and loaded from the title (Ctrl+L)
#
# --refs: write tests/frames.md5 and tests/play.md5 anew (look at the pictures first).
# The game's data must be in data/card (make data).
HZ=${1:-../../horizon}
REFS=$2
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
FILES=
for f in data/card/*; do FILES="$FILES --file $f:/APPS/PRINCE/$(basename "$f")"; done
run() {
  python3 ../../sdk/tools/run816.py PRINCE.PRG --horizon "$HZ" --dest /APPS/PRINCE/PRINCE.PRG \
    $FILES "$@"
}
shell() {
  a=$1
  shift
  run --mode shell --cd /APPS/PRINCE --args "$a" "$@"
}
rm -rf build/test
mkdir -p build/test/frames

# ---------------------------------------------------------------- 1. the replays, validated
# (and 3. their pictures: SHOTS ticks of each)
shots_of() {
  case $1 in
    l1sword) echo 80,285,660,790,940,950;;
    l1run)   echo 1110,1186;;
    loose)   echo 72,78,80,118,130;;
    fight)   echo 44,70,84,100,110;;
  esac
}
pids=
for r in tests/replays/*.p1r; do
  n=$(basename "$r" .p1r)
  U=$(echo "$n" | tr a-z A-Z)
  shell "validate $U.P1R every=10 shots=$(shots_of $n)" --file "$r:/APPS/PRINCE/$U.P1R" \
    --shot-on "prince: shot" --seconds 240 --out build/test/val-$n > build/test/val-$n.log 2>&1 &
  pids="$pids $!"
done
wait $pids
for r in tests/replays/*.p1r; do
  n=$(basename "$r" .p1r)
  con=build/test/val-$n/console.txt
  tr -d '\r' < "$con" |
    grep -E "^ref:|^Replay (started|ended)|^Kid is|^Remaining|^Elapsed|^Play duration" > build/test/val-$n.txt
  if cmp -s build/test/val-$n.txt tests/ref/$n.ref; then
    ok "replay $n: $(grep -c '^ref:' tests/ref/$n.ref) states and the end as upstream on the PC ($(grep 'Play duration matches' tests/ref/$n.ref | sed 's/Play duration matches replay length. //'))"
  else
    bad "replay $n: not as tests/ref/$n.ref:"
    diff tests/ref/$n.ref build/test/val-$n.txt | head -4
  fi
  # its pictures, named by tick
  tr -d '\r' < "$con" | grep -a '^prince: shot' | while read a b k c tick d vy g; do
    cp build/test/val-$n/auto$k.png build/test/frames/$n-$tick.png
  done
done

# ---------------------------------------------------------------- 2. at the game's speed, slower
shell "L1SWORD.P1R nosound every=10 /BUSY:30 stats=1000" \
  --file tests/replays/l1sword.p1r:/APPS/PRINCE/L1SWORD.P1R --seconds 120 \
  --out build/test/timed > build/test/timed.log 2>&1
tr -d '\r' < build/test/timed/console.txt | grep '^ref:' | head -96 > build/test/timed.txt
grep '^ref:' tests/ref/l1sword.ref > build/test/timed.want
if cmp -s build/test/timed.txt build/test/timed.want; then
  ok "replay l1sword at the game's speed, 30 ms a frame slower: the same $(wc -l < build/test/timed.want) states"
else
  bad "replay l1sword at the game's speed: not as tests/ref/l1sword.ref"
  diff build/test/timed.want build/test/timed.txt | head -4
fi
st=$(tr -d '\r' < build/test/timed/console.txt | grep 'prince: stats all' | tail -1)
[ -n "$st" ] && echo "      ($st)"

# ---------------------------------------------------------------- 3. the pictures
if [ "$REFS" = --refs ]; then
  python3 tests/shots.py tests/frames.md5 build/test/frames/*.png --update || fail=1
elif python3 tests/shots.py tests/frames.md5 build/test/frames/*.png; then :; else fail=1; fi

# ---------------------------------------------------------------- 3b. a late clock
# the machine on for 280 s before the title (every other run is in its first minute): the
# title's pictures, the story's wipe (it froze there on the board), then a key starts level 1
run --mode desktop --script tests/late.script --seconds 330 \
  --out build/test/late > build/test/late.log 2>&1 || bad "the late clock's run (killed, or a wait never ended)"
if grep -aq "^prince: level 1" build/test/late/console.txt; then
  ok "the machine on for 280 s: the title, the story's wipe, level 1"
else bad "the machine on for 280 s: no level 1 (the title froze)"; fi

# ---------------------------------------------------------------- 4. the scripted game
run --mode desktop --script tests/play.script --seconds 40 --log-lau \
  --out build/test/play > build/test/play.log 2>&1 || bad "the scripted game's run (killed, or a wait never ended)"
con=build/test/play/console.txt
okl=1
for w in "prince: title" "prince: level 1" "prince: text LEVEL 1" "prince: text QUICKSAVE" \
         "prince: text QUICKLOAD" "prince: text GAME PAUSED"; do
  grep -aq "^$w" "$con" || { bad "the scripted game: no '$w'"; okl=0; }
done
[ $okl = 1 ] && ok "the scripted game: the title, level 1, a quicksave, a quickload, a pause"
if grep -aq '\[kill\]\|sheet_draw refused' "$con"; then bad "the scripted game: $(grep -a '\[kill\]\|refused' "$con" | head -1)"; fi
q=build/test/play/card/APPS/PRINCE/QUICKSAVE.SAV
if [ -f "$q" ] && [ "$(wc -c < "$q")" -gt 3000 ]; then ok "QUICKSAVE.SAV written ($(wc -c < "$q") bytes)"
else bad "no QUICKSAVE.SAV in the program's folder"; fi
n=$(grep -c '^lau ' build/test/play/emu.err)
if [ "$n" -gt 50 ]; then ok "sound: $n writes to Lau (the effects)"; else bad "sound: only $n writes to Lau"; fi
run --mode desktop --script tests/title.script --seconds 25 --log-opl-us \
  --out build/test/title > build/test/title.log 2>&1 || bad "the title's run"
if python3 tests/oplcheck.py data/card/POP.SND 54 build/test/title/emu.err --seconds 10; then
  ok "sound: the title music on the OPL2 as its stream (the first 10 s)"
else bad "sound: the title music's OPL2 writes"; fi
if [ "$REFS" = --refs ]; then
  python3 tests/shots.py tests/play.md5 build/test/play/shot*.png --update || fail=1
elif python3 tests/shots.py tests/play.md5 build/test/play/shot*.png; then :; else fail=1; fi

# ---------------------------------------------------------------- 5. save and load
shell "megahit 3" --script tests/save.script --seconds 30 --out build/test/save \
  > build/test/save.log 2>&1 || bad "the saving run"
s=build/test/save/card/APPS/PRINCE/PRINCE.SAV
if grep -aq '^prince: text GAME SAVED' build/test/save/console.txt && [ -f "$s" ]; then
  ok "a game saved on level 3: PRINCE.SAV ($(wc -c < "$s") bytes)"
else bad "no 'GAME SAVED' or no PRINCE.SAV"; fi
if [ -f "$s" ]; then
  shell "" --file "$s:/APPS/PRINCE/PRINCE.SAV" --script tests/load.script --seconds 30 \
    --out build/test/load > build/test/load.log 2>&1 || bad "the loading run"
  if grep -aq '^prince: level 3' build/test/load/console.txt; then
    ok "the saved game loaded from the title (Ctrl+L): level 3"
  else bad "Ctrl+L at the title did not start level 3"; fi
fi

if [ $fail = 0 ]; then echo "check: all passed"; else echo "check: FAILED"; fi
exit $fail

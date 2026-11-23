#!/bin/sh
# tests/levels.sh [HORIZON] - make test-long: every level of the game against upstream
# SDLPoP on the PC (make host), in the emulator with the board's card:
#
#   1. for each level 1-14 a replay recorded by the PC from the level's start (tests/
#      mklevels.sh: build/levels/levN.p1r, made once), validated by the port: the start
#      room, the level structure's checksum (2,305 bytes: the level loaded whole), the state
#      every 10 ticks and upstream's end lines must be tests/levels/levN.ref (the PC's);
#      the picture at tick 40 (the first room, the status line) equal to the PC's pixel for
#      pixel (tests/cmpframe.py)
#   1b. level 6's shadow (a replay whose start the PC's tests/patchp1r.py moved: the kid
#      runs into the shadow's room): states and pictures as the PC's (the XOR blit)
#   2. the whole game walked through with the cheat keys ("megahit 1", Shift+L thirteen
#      times): each level must start in its room with the heap as when that level is
#      started directly ("megahit N": no leak from level to level, the fault class of the
#      empty level 1, PORTING-NOTES.md fault 11)
HZ=${1:-../../horizon}
cd "$(dirname "$0")/.." || exit 1
LEVELS="1 2 3 4 5 6 7 8 9 10 11 12 13 14"
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
FILES=
for f in data/card/*; do FILES="$FILES --file $f:/APPS/PRINCE/$(basename "$f")"; done
run() {
  python3 ../../sdk/tools/run816.py PRINCE.PRG --horizon "$HZ" --dest /APPS/PRINCE/PRINCE.PRG $FILES "$@"
}
shell() {
  a=$1
  shift
  run --mode shell --cd /APPS/PRINCE --args "$a" "$@"
}
for n in $LEVELS shadow; do
  [ -f build/levels/lev$n.p1r ] && [ -f build/levels/host-$n.png ] && continue
  [ $n = shadow ] && [ -f build/levels/shadow.p1r ] && [ -f build/levels/host-shadow-40.png ] && continue
  sh tests/mklevels.sh > /dev/null || { echo "FAIL  no level replays (tests/mklevels.sh: make host)"; exit 1; }
  break
done
rm -rf build/test-long
mkdir -p build/test-long

# ---------------------------------------------------------------- 1. each level's start
pids=
k=0
for n in $LEVELS; do
  shell "validate LEV$n.P1R every=10 levelsum shots=40" --file "build/levels/lev$n.p1r:/APPS/PRINCE/LEV$n.P1R" \
    --shot-on "prince: shot" --seconds 120 --out build/test-long/lev$n > build/test-long/lev$n.log 2>&1 &
  pids="$pids $!"
  k=$((k + 1))
  if [ $k = 7 ]; then wait $pids; pids=; k=0; fi
done
wait $pids
for n in $LEVELS; do
  con=build/test-long/lev$n/console.txt
  tr -d '\r' < "$con" |
    grep -E "^ref:|^lvl:|^Replay (started|ended)|^Kid is|^Remaining|^Elapsed|^Play duration" > build/test-long/lev$n.txt
  lvl=$(grep '^lvl:' tests/levels/lev$n.ref | sed 's/^lvl: //; s/ size.*//')
  if cmp -s build/test-long/lev$n.txt tests/levels/lev$n.ref; then
    ok "level $n: $lvl, $(grep -c '^ref:' tests/levels/lev$n.ref) states and the end as on the PC"
  else
    bad "level $n: not as tests/levels/lev$n.ref:"
    diff tests/levels/lev$n.ref build/test-long/lev$n.txt | head -4
  fi
  s=$(tr -d '\r' < "$con" | grep -a '^prince: shot' | head -1)
  set -- $s
  if [ -n "$s" ] && python3 tests/cmpframe.py build/test-long/lev$n/auto$3.png build/levels/host-$n.png \
       $7 $8 --diff build/test-long/diff-$n.png > build/test-long/cmp-$n.txt 2>&1; then
    ok "level $n: the picture at tick 40 as the PC's"
  else bad "level $n: the picture at tick 40: $(cat build/test-long/cmp-$n.txt 2>/dev/null | tail -1)"; fi
done

# ---------------------------------------------------------------- 1b. the shadow
# level 6's shadow across the gap (its XOR blit: SDLPoP's in RGB), states and pictures
shell "validate SHADOW.P1R every=2 shots=20,40" --file build/levels/shadow.p1r:/APPS/PRINCE/SHADOW.P1R \
  --shot-on "prince: shot" --seconds 60 --out build/test-long/shadow > build/test-long/shadow.log 2>&1
tr -d '\r' < build/test-long/shadow/console.txt |
  grep -E "^ref:|^Replay (started|ended)|^Kid is|^Remaining|^Elapsed|^Play duration" > build/test-long/shadow.txt
if cmp -s build/test-long/shadow.txt tests/levels/shadow.ref; then
  ok "the shadow (level 6): $(grep -c '^ref:' tests/levels/shadow.ref) states as on the PC"
else
  bad "the shadow: not as tests/levels/shadow.ref:"
  diff tests/levels/shadow.ref build/test-long/shadow.txt | head -4
fi
for t in 20 40; do
  s=$(tr -d '\r' < build/test-long/shadow/console.txt | grep -a "^prince: shot [0-9]* tick $t " | head -1)
  set -- $s
  if [ -n "$s" ] && python3 tests/cmpframe.py build/test-long/shadow/auto$3.png build/levels/host-shadow-$t.png \
       $7 $8 --diff build/test-long/diff-shadow-$t.png > build/test-long/cmp-shadow-$t.txt 2>&1; then
    ok "the shadow: the picture at tick $t as the PC's (its XOR's colours)"
  else bad "the shadow: the picture at tick $t: $(tail -1 build/test-long/cmp-shadow-$t.txt 2>/dev/null)"; fi
done

# ---------------------------------------------------------------- 2. the game walked through
# (Shift held 400 ms past the L: the cut scenes between levels are skipped, as upstream does)
{
  echo "0 wait prince: level 1 in room"
  for n in $LEVELS; do
    [ $n = 1 ] && continue
    echo "+2500 down lshift"
    echo "+100 key l 100"
    echo "+400 up lshift"
    echo "+0 wait prince: level $n in room"
  done
  echo "+2000 shot"
} > build/test-long/walk.script
shell "megahit 1" --script build/test-long/walk.script --seconds 400 --out build/test-long/walk \
  > build/test-long/walk.log 2>&1 &
pids=$!
k=1
for n in $LEVELS; do
  shell "megahit $n" --stop-on "prince: level $n in room" --seconds 60 --out build/test-long/meg$n \
    > build/test-long/meg$n.log 2>&1 &
  pids="$pids $!"
  k=$((k + 1))
  if [ $k = 8 ]; then wait $pids; pids=; k=0; fi
done
wait $pids
grep -q "FAIL" build/test-long/walk.log && bad "the walk through the levels (a wait never ended: build/test-long/walk)"
okw=1
for n in $LEVELS; do
  w=$(tr -d '\r' < build/test-long/walk/console.txt | grep -a "^prince: level $n in room" | head -1)
  d=$(tr -d '\r' < build/test-long/meg$n/console.txt | grep -a "^prince: level $n in room" | head -1)
  room=$(grep '^lvl:' tests/levels/lev$n.ref | sed 's/^lvl: level [0-9]* room \([0-9]*\) .*/\1/')
  case "$w" in
    "prince: level $n in room $room,"*) ;;
    *) bad "the walk: level $n: '$w' (its start room is $room)"; okw=0; continue;;
  esac
  if [ "${w#*heap }" != "${d#*heap }" ]; then
    bad "the walk: level $n: the heap ${w#*heap } (started directly: ${d#*heap })"; okw=0
  fi
done
[ $okw = 1 ] && ok "the walk through levels 1-14 with Shift+L: each in its start room, the heap as when started directly"

if [ $fail = 0 ]; then echo "levels: all passed"; else echo "levels: FAILED"; fi
exit $fail

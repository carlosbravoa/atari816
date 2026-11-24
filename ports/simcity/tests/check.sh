#!/bin/sh
# tests/check.sh [HORIZON] [--refs] - Micropolis's tests (make test):
#
#   1. the simulator: SIMTEST.PRG on the Atari816 (the emulator) against its twins on the
#      PC (host16: the engine with a 16-bit int; host32: upstream's types), 5,000 ticks of
#      four generated cities (a small city laid by the tools on each), four scenarios and
#      two of upstream's cities: the whole state equal every 100 ticks (tests/simeq.sh)
#   2. the tools with the mouse and the keys in the game (tests/tools.script): every call
#      the game made to the engine's tools (its log) made again by simtest on the PC: the
#      same state; the pictures (the city built, the query's window, the zoomed-out view,
#      the overview map) against their checksums (tests/tools.md5)
#   3. saving: a city loaded and saved by the game (Ctrl+S, paused) byte for byte the file
#      simtest saves of the same city on the PC; SIMTEST.PRG's save the same; the saved
#      map the map in memory (simtest's dump); the saved file loads again (simtest)
#   4. a scenario in the game: Tokyo (the monster), its intro, 2,000 frames played
#      at the fast speed: the game's own state line equal to simtest's after the same
#      ticks is not asked (the frames decide the ticks), but no [kill], the ticks' cost
#      on the log, the pictures of the running city
#   5. the windows: budget, evaluation, graphs, the File menu, load (pictures)
#
# --refs: write tests/*.md5 anew (look at the pictures first).
HZ=${1:-../../horizon}
REFS=$2
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
mkdir -p build/test

# ---------------------------------------------------------------- 1. the simulator
if sh tests/simeq.sh "$HZ" ${TICKS:-5000} > build/test/simeq.txt 2>&1; then
  ok "the simulator on the Atari816 equals its twins on the PC: $(grep -c PASS build/test/simeq.txt) cases, ${TICKS:-5000} ticks each"
else
  bad "the simulator on the Atari816 and the PC:"
fi
sed 's/^/      /' build/test/simeq.txt

# ---------------------------------------------------------------- 2. the tools
sh tests/run.sh "$HZ" build/test/tools --args "seed 1234 paused" --script tests/tools.script \
  --shot-on "micropolis: shot" --seconds 90 > build/test/tools.log 2>&1 ||
  bad "the tools' run (killed, or a wait never ended: build/test/tools.log)"
con=build/test/tools/console.txt
args=$(tr -d '\r' < $con | sed -n 's/^micropolis: tool \(down\|drag\|up\) \(.*\)/\1 \2/p' | tr '\n' ' ')
st816=$(tr -d '\r' < $con | sed -n 's/^micropolis: state crc \([0-9a-f]*\).*/\1/p' | head -1)
sthost=$(build/host16/simtest gen 1234 $args ticks 0 | sed -n 's/^sim: start crc \([0-9a-f]*\).*/\1/p')
n=$(echo "$args" | grep -o 'down\|drag\|up' | wc -l)
if [ -n "$st816" ] && [ "$st816" = "$sthost" ]; then
  ok "the tools: $n calls from the mouse in the game, made again by simtest on the PC: the same state ($st816)"
else
  bad "the tools: the game's state '$st816', simtest's of the same calls '$sthost'"
fi
for w in "micropolis: query" "micropolis: window 5"; do
  grep -aq "$w" $con || bad "the tools: no '$w'"
done
pics() {   # NAME RUNDIR: the run's autoN.png against tests/NAME.md5
  if [ "$REFS" = --refs ]; then
    python3 tests/shots.py tests/$1.md5 $2/auto*.png --update
  else
    python3 tests/shots.py tests/$1.md5 $2/auto*.png
  fi
}
if l=$(pics tools build/test/tools); then ok "the tools' pictures: $l"; else bad "the tools' pictures: $l"; fi

# ---------------------------------------------------------------- 3. saving
cp engine/cities/kobe.cty build/test/TEST.CTY
sh tests/run.sh "$HZ" build/test/save --args "seed 7 city TEST.CTY paused" --file build/test/TEST.CTY:/APPS/MICROPOLIS/TEST.CTY \
  --script tests/save.script --seconds 60 > build/test/save.log 2>&1 || bad "the save's run"
build/host16/simtest seed 7 load engine/cities/kobe.cty speed 0 ticks 0 save build/test/host.cty \
  dump build/test/host.dump > /dev/null
if cmp -s build/test/save/card/APPS/MICROPOLIS/TEST.CTY build/test/host.cty; then
  ok "a city loaded and saved by the game: the file simtest saves on the PC, byte for byte ($(wc -c < build/test/host.cty) bytes)"
else bad "the game's saved city differs from simtest's (build/test/save/card/APPS/MICROPOLIS/TEST.CTY)"; fi
python3 ../../sdk/tools/run816.py SIMTEST.PRG --horizon "$HZ" --mode shell \
  --args "seed 7 load /APPS/K.CTY speed 0 ticks 0 save /APPS/O.CTY" --file engine/cities/kobe.cty:/APPS/K.CTY \
  --stop-on "sim: saved" --stop-on-delay 1000 --seconds 60 --out build/test/simsave > /dev/null 2>&1
if cmp -s build/test/simsave/card/APPS/O.CTY build/test/host.cty; then
  ok "SIMTEST.PRG's save of the city: the PC's, byte for byte"
else bad "SIMTEST.PRG's saved city differs from the PC's"; fi
if python3 tests/ctycheck.py build/test/host.cty build/test/host.dump; then
  ok "the saved file holds the map, funds and time in memory (upstream's format: big-endian words)"
else bad "the saved file does not hold the state in memory"; fi
a=$(build/host16/simtest load build/test/host.cty speed 0 ticks 0 | sed -n 's/^sim: start crc [0-9a-f]* \(time [0-9]* funds [0-9]*\).*/\1/p')
b=$(build/host16/simtest load engine/cities/kobe.cty speed 0 ticks 0 | sed -n 's/^sim: start crc [0-9a-f]* \(time [0-9]* funds [0-9]*\).*/\1/p')
if [ -n "$a" ] && [ "$a" = "$b" ]; then ok "the saved city loads again: $a"; else bad "the saved city loads as '$a', the original as '$b'"; fi

# ---------------------------------------------------------------- 4. playing a scenario
sh tests/run.sh "$HZ" build/test/play --args "scen 5 seed 77" --script tests/play.script \
  --shot-on "micropolis: shot" --seconds 200 > build/test/play.log 2>&1 || bad "the scenario's run (build/test/play.log)"
con=build/test/play/console.txt
if grep -aq "^\[kill\]" $con; then bad "the scenario: $(grep -a '^\[kill\]' $con)"; fi
t=$(tr -d '\r' < $con | grep -a "ticks, .* ms a tick" | tail -1)
if [ -n "$t" ]; then ok "Tokyo at the fast speed: ${t#micropolis: }"; else bad "the scenario: no ticks counted"; fi
grep -aq "micropolis: scenario 5" $con && ok "the scenario's intro" || bad "no scenario"

# ---------------------------------------------------------------- 5. the windows
sh tests/run.sh "$HZ" build/test/windows --args "seed 4321 paused" --script tests/windows.script \
  --shot-on "micropolis: shot" --seconds 90 > build/test/windows.log 2>&1 || bad "the windows' run"
con=build/test/windows/console.txt
for w in 2 3 4 1 6; do
  grep -aq "micropolis: window $w" $con || bad "the windows: window $w did not open"
done
if l=$(pics windows build/test/windows); then ok "the windows' pictures: $l"; else bad "the windows' pictures: $l"; fi

[ $fail = 0 ] && echo "micropolis: ALL TESTS PASSED"
exit $fail

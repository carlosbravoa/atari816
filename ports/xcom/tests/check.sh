#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/check.sh [HORIZON] [--refs]: make test. Each run of tests/runs (upstream's KEYS
# scripts: a new game, the geoscape, base screens, UFOpaedia, graphs; a quick battle):
#
#   1. on the host build (the reference, build/host/xcomhost: the engine on Linux with the
#      virtual clock): its LOG, its pictures (the model's test pictures, plat.h "test
#      runs"); the pictures' checksums against RUNS.md5 (tests/runs.md5: the reference itself has not
#      moved: the data's pictures are not in git, only their checksums)
#   2. on the Atari816 in the emulator (XCOM.PRG /V: the same virtual clock), in parallel:
#      the same LOG line for line (tests/compare.py: the lines that may differ, and why),
#      the same pictures at the same virtual times (the model's checksum of A000 and the
#      DAC, printed by both), and what the emulator showed at each (the 320 x 180 shown
#      of the 320 x 200 at the pan printed) equal pixel for pixel to the host's picture
#
# --refs: write RUNS.md5 anew (look at the pictures first). The packs must be in
# data/packs (make data).
# A run's line may start with s=N: its emulator run's longest length (default
# XCOM_SECONDS, 400). A run ends 1 s of emulated time after the program's last line
# ("xcom: files: at most ...", printed at its exit: run816 --stop-on), not at that limit;
# "xcom: end ... (machine N s)" tells what a run needs.
# A run's line may also start with k=NAME (tests/NAME.keys instead of tests/RUN.keys) and
# r=N (the emulator reports hardware revision N: --rev N; r=12 is a board without the
# blitter's colour remap, so the night's shade is the CPU's: the same pictures). The
# night's runs check the console's line on how the shade was made (the remap at the
# emulator's default revision, the CPU at r=12).
# RUNS=FILE: the runs of FILE instead of tests/runs (make test-long: tests/runs-long; the
# real input's run only with tests/runs); O=DIR the output folder (build/test).
HZ=${1:-../../horizon}
REFS=$2
RUNS=${RUNS:-tests/runs}
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
O=${O:-build/test}
# (the program's last line: its exit's files report, after the LOG and the saves are
# closed; then 1 s for stdio's own closes and the shell)
STOP_TEXT='xcom: files: at most'
rm -rf $O
mkdir -p $O

# ---------------------------------------------------------------- the card's files
FILES=
for f in data/packs/*.PAK data/packs/PACKS.VER; do FILES="$FILES --file $f:/GAMES/XCOM/$(basename "$f")"; done
for f in data/packs/VGA/*; do FILES="$FILES --file $f:/GAMES/XCOM/VGA/$(basename "$f")"; done
[ -f MUSD.PRG ] && FILES="$FILES --file MUSD.PRG:/GAMES/XCOM/MUSD.PRG"   # the music task (sound)

# a run line's options before the engine's (s=N, k=NAME, r=N): secs, keys, rev, args
opts() {
  secs=${XCOM_SECONDS:-400} keys=$name rev=
  while :; do
    case "$args" in
      s=*) secs=${args%% *}; secs=${secs#s=} ;;
      k=*) keys=${args%% *}; keys=${keys#k=} ;;
      r=*) rev=${args%% *}; rev=${rev#r=} ;;
      *) break ;;
    esac
    args=${args#* }
  done
}

# ---------------------------------------------------------------- 1. the host
while read -r name args; do
  case "$name" in ''|\#*) continue ;; esac
  opts
  mkdir -p $O/$name
  sh tests/hostrun.sh "$keys" $O/$name/host $args > $O/$name/host.txt 2>&1 || true
  [ -d $O/$name/host ] || { bad "$name: the host run"; continue; }
done < $RUNS
(cd $O && for n in */host/shot*.ppm; do md5sum "$n"; done | sed 's|/host/|/|') > $O/host.md5
if [ "$REFS" = --refs ]; then
  cp $O/host.md5 $RUNS.md5
  echo "$RUNS.md5 written ($(wc -l < $O/host.md5) pictures)"
elif cmp -s $RUNS.md5 $O/host.md5; then
  ok "the host's reference runs: $(wc -l < $O/host.md5) pictures as $RUNS.md5"
else
  bad "the host's reference runs: pictures not as $RUNS.md5:"
  diff $RUNS.md5 $O/host.md5 | head -6
fi

# ---------------------------------------------------------------- 2. the Atari816
pids= running=
while read -r name args; do
  case "$name" in ''|\#*) continue ;; esac
  opts
  U=$(echo "$name" | tr a-z A-Z)
  # (BENCH reads the back buffer behind the blitter's back: /S waits for it at once)
  S=; case " $args " in *" BENCH "*) S=/S ;; esac
  K=; [ -f tests/$keys.keys ] && K="KEYS $U.KEY"
  R=; [ -n "$rev" ] && R="--emu-arg --rev --emu-arg $rev"
  echo "/V /T 5 $S $args $K" > $O/$name/$U.ARG
  printf '0 wait xcom: end\n' > $O/$name/end.script
  python3 ../../sdk/tools/run816.py XCOM.PRG --horizon "$HZ" --mode shell $R \
    --dest /GAMES/XCOM/XCOM.PRG --cd /GAMES/XCOM --args "@$U.ARG" $FILES \
    $( [ -f tests/$keys.keys ] && echo --file tests/$keys.keys:/GAMES/XCOM/$U.KEY) --file $O/$name/$U.ARG:/GAMES/XCOM/$U.ARG \
    --script $O/$name/end.script --shot-on "xcom: shot" --seconds $secs --stop-on "$STOP_TEXT" --stop-on-delay 1000 \
    --out $O/$name/816 > $O/$name/run816.log 2>&1 &
  pids="$pids $!"
  # (at most JOBS emulators at once: the machine is shared)
  running="$running $!"
  set -- $running
  if [ $# -ge "${JOBS:-6}" ]; then wait "$1"; shift; running="$*"; fi
done < $RUNS
wait $pids

# ---------------------------------------------------------------- the full card
# tests/save.keys with the card nearly full (emu816 --card-free: 8,000 bytes more fit):
# the save is written short, the engine says "Could not save the game!", the model removes
# the cut save (no XCOMXT1.SAV left to load as garbage), the game goes on (its Load Game
# finds no save) and ends normally. (emu816 counts the bytes written in the run, so the
# card stays full after the removal: the LOG's later lines are lost, not checked)
fpid=
if [ "$RUNS" = tests/runs ]; then
  mkdir -p $O/full
  echo "/V /T 5 VGA NOINTRO LOG SAVE.TXT KEYS SAVE.KEY" > $O/full/FULL.ARG
  printf '0 wait xcom: end\n' > $O/full/end.script
  python3 ../../sdk/tools/run816.py XCOM.PRG --horizon "$HZ" --mode shell \
    --dest /GAMES/XCOM/XCOM.PRG --cd /GAMES/XCOM --args "@FULL.ARG" $FILES \
    --file tests/save.keys:/GAMES/XCOM/SAVE.KEY --file $O/full/FULL.ARG:/GAMES/XCOM/FULL.ARG \
    --script $O/full/end.script --emu-arg --card-free --emu-arg 8000 --seconds 150 --stop-on "$STOP_TEXT" --stop-on-delay 1000 \
    --out $O/full/816 > $O/full/run816.log 2>&1 &
  fpid=$!
fi

# ---------------------------------------------------------------- 3. the real input
# Horizon's keyboard and mouse in full screen, the real clock, no KEYS script
# (tests/input.script): start menu, New Game, the difficulty, a base placed by a click
# on the globe and Enter, the base screen by its button, back by GEOSCAPE (the pan
# brings the bottom rows in), G for the graphs; the engine's LOG says each happened
# The same three times: as the machine is after its start, with the microsecond clock as
# after 5 minutes (/U: the port's clock reading plus an offset) and with it wrapping
# (2^32 us, 71.6 minutes) about 25 s into the run, in the middle of the game: the
# port's clock (plat_counts, the BIOS clock, the polls' gaps) must go on through it.
ipids=
if [ "$RUNS" = tests/runs ]; then
for v in input late5 wrap; do
  case $v in input) U= ;; late5) U="/U 300000000" ;; wrap) U="/U 4264967296" ;; esac
  echo "$U VGA NOINTRO LOG INPUT.TXT" > $O/$v.ARG
  python3 ../../sdk/tools/run816.py XCOM.PRG --horizon "$HZ" --mode shell \
    --dest /GAMES/XCOM/XCOM.PRG --cd /GAMES/XCOM --args "@INPUT.ARG" $FILES \
    --file $O/$v.ARG:/GAMES/XCOM/INPUT.ARG --script tests/input.script --seconds 70 \
    --out $O/$v > $O/$v.log 2>&1 &
  ipids="$ipids $!"
done
fi

while read -r name args; do
  case "$name" in ''|\#*) continue ;; esac
  opts
  log=$(echo "$args" | sed -n 's/.*LOG \([^ ]*\).*/\1/p')
  python3 tests/compare.py $name $O/$name "$log" || fail=1
  case " $args " in *" NIGHT "*)
    if [ -n "$rev" ] && [ "$rev" -lt 13 ]; then w="no colour remap"; h="by the CPU (REV $rev)"
    else w="by the blitter's colour remap"; h="by the blitter's colour remap"; fi
    if grep -aq "xcom: night shade: .*$w" $O/$name/816/console.txt; then ok "$name: the night's shade $h"
    else bad "$name: the night's shade not $h: $(grep -a 'night shade' $O/$name/816/console.txt)"; fi ;;
  esac
  case "$keys" in nlight)
    # the night lights' run did what it is for: a fire, a flare, aliens seen and lost
    L=$O/$name/host/card/$log
    if grep -aq "incendiary at" $L && grep -aq "device 3 placed" $L && grep -aq ": night: alien .* seen by" $L \
       && grep -aq ": night: alien .* out of sight" $L; then
      ok "$name: a fire, a flare, aliens seen and lost in the dark ($(grep -ac ': night: alien' $L) LOG lines)"
    else bad "$name: the script no longer makes its fire, flare or sightings"; fi ;;
  esac
done < $RUNS

if [ -n "$ipids" ]; then
wait $ipids
for v in input late5 wrap; do
  case $v in input) what= ;; late5) what=", the clock as 5 minutes after the machine's start" ;;
             wrap) what=", the microsecond clock wrapping during the game (71.6 minutes)" ;; esac
  L=$O/$v/card/GAMES/XCOM/INPUT.TXT
  okl=1
  for w in "new game, difficulty Beginner" "NAME HQ" "X-COM base operational" "BASE menu: 11 buttons" \
           "GRAPHS UFO areas"; do
    grep -q "$w" $L 2>/dev/null || { bad "the real input ($v): no '$w' in INPUT.TXT"; okl=0; }
  done
  grep -aq '\[kill\]' $O/$v/console.txt && { bad "the real input ($v): $(grep -a '\[kill\]' $O/$v/console.txt)"; okl=0; }
  if [ $v = wrap ] && ! grep -aq "xcom: the microsecond clock wrapped" $O/$v/console.txt; then
    bad "the real input (wrap): the clock did not wrap during the run"; okl=0
  fi
  [ $okl = 1 ] && ok "the real input (mouse and keys through Horizon): new game, base placed and named, base screen, back, graphs$what"
done
fi

if [ -n "$fpid" ]; then
  wait $fpid
  F=$O/full/816
  if grep -aq 'written short (the card is full?): removed' $F/console.txt \
     && [ ! -e $F/card/GAMES/XCOM/XCOMXT1.SAV ] && grep -aq 'xcom: end at' $F/console.txt \
     && ! grep -aq '\[kill\]' $F/console.txt; then
    ok "a full card: the save written short, the cut file removed, the game went on to its end"
  else bad "a full card ($F): $(grep -a 'save slot\|written short\|kill' $F/console.txt $F/card/GAMES/XCOM/SAVE.TXT 2>/dev/null | head -3)"; fi
fi

if [ $fail = 0 ]; then echo "check: all passed"; else echo "check: FAILED"; fi
exit $fail

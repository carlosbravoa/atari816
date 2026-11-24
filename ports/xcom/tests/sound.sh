#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/sound.sh [HORIZON]: the sound (PORTING-NOTES.md "Sound"), the Atari816 against the
# host build (make sound; about 60 s on the fast machine, the three runs in parallel):
#
#   geo    tests/geo.keys, then 30 s of the geoscape: the music task's OPL2 writes
#          (MUSD.PRG on the music timer) equal the host's (the engine's own driver at its
#          virtual clock) for the geoscape track's first 1,456 ticks (20 s; from its start,
#          found in the task's writes: the start menu's GMSTORY before it ends at a moment
#          of each build's own clock), each tick on the
#          13.731 ms beat within 20 ms (it is late by up to 8-17 ms once, while the
#          geoscape's pictures load); the recording: heard (RMS 150+), not clipped
#   sndbat a quick battle (FA1V, sectoids, seed 1, tests/sndbat.keys): a soldier walks out
#          of the craft (its metal floor's footsteps, then the ground's: two a step, pack
#          format 6) and shoots (rifle). The music while the engine loads the
#          battle and redraws the view: the same writes, ticks within 20 ms of the beat (no
#          stall); every Sound Blaster block the host's (which effect, rate, samples; the
#          block ends and the IRQs on the virtual clock, the same readings on both builds)
#          and a Lau start of it
#   sndai  the same battle, the turn ended at once (tests/sndai.keys): the aliens' turn
#          (seconds of computation), the music over the whole run as the host's and on
#          the beat within 30 ms. (The engine's turn itself is not compared: make test's
#          LOGs are; the host's runs on, -t 600, so that its ticks cover the emulator's)
#   sndui  the interface (tests/sndui.keys): the start menu, Load Saved Game and the list's
#          CANCEL (the start menu again: it does not pop up again), a new game by clicks, the
#          geoscape's INTERCEPT and its CANCEL, OPTIONS, Save Game and the list's CANCEL, a
#          time button, OPTIONS by Esc: every Sound Blaster block the host's and a Lau start,
#          and the effects that start are the 19 expected, in order: a pop-up (W: one of the
#          three) when each window that pops up opens (the start menu, the saves' list,
#          the difficulty, the base's name, INTERCEPT, OPTIONS, the saves' list, OPTIONS),
#          a click (B) for each
#          button pressed by the mouse (none for the keys); their loudest 50 ms (NOMUSIC:
#          the effects alone; the start menu's GMSTORY is as loud as the shots) under the
#          battle's (the shots)
#
# Pictures and LOGs are make test's (the runs here only listen). Output: build/sound.
HZ=${1:-../../horizon}
cd "$(dirname "$0")/.." || exit 1
O=build/sound
rm -rf $O && mkdir -p $O
fail=0
PY=python3
FILES=
for f in data/packs/*.PAK data/packs/PACKS.VER; do FILES="$FILES --file $f:/GAMES/XCOM/$(basename "$f")"; done
for f in data/packs/VGA/*; do FILES="$FILES --file $f:/GAMES/XCOM/VGA/$(basename "$f")"; done
FILES="$FILES --file MUSD.PRG:/GAMES/XCOM/MUSD.PRG"

# name, the engine's options, the host's idle end (s), the emulator's options
run() {
  name=$1 args=$2 idle=$3; shift 3
  U=$(echo "$name" | tr a-z A-Z)
  mkdir -p $O/$name/card
  for f in "$PWD"/data/packs/*.PAK "$PWD"/data/packs/PACKS.VER "$PWD"/data/packs/VGA; do
    ln -s "$f" "$O/$name/card/$(basename "$f")"
  done
  build/host/xcomhost -C $O/$name/card -o $O/$name -t ${HOSTIDLE:-$idle} -opl "$PWD/$O/$name/opl.txt" \
    -sb "$PWD/$O/$name/sb.txt" $args KEYS "$PWD/tests/$name.keys" > $O/$name/host.txt 2>&1 &
  echo "/V /T $idle $args KEYS $U.KEY" > $O/$name/$U.ARG
  printf '0 wait xcom: end\n' > $O/$name/end.script
  $PY ../../sdk/tools/run816.py XCOM.PRG --horizon "$HZ" --mode shell \
    --dest /GAMES/XCOM/XCOM.PRG --cd /GAMES/XCOM --args "@$U.ARG" $FILES \
    --file tests/$name.keys:/GAMES/XCOM/$U.KEY --file $O/$name/$U.ARG:/GAMES/XCOM/$U.ARG \
    --script $O/$name/end.script --seconds ${SECONDS816:-200} --log-opl-us --wav $O/$name/816.wav \
    --stop-on "xcom: files: at most" --stop-on-delay 1000 \
    --out $O/$name/816 "$@" > $O/$name/run816.log 2>&1
  wait
}
run geo "VGA NOINTRO LOG GEO.TXT" 30 &
p1=$!
run sndbat "VGA NOINTRO BATTLE SEED 1 MISSION FA1V.PAK RACE RSV.PAK LOG SNDBAT.TXT" 10 --log-lau &
p2=$!
HOSTIDLE=600 SECONDS816=300 run sndai "VGA NOINTRO BATTLE SEED 1 MISSION FA1V.PAK RACE RSV.PAK LOG SNDAI.TXT" 10 &
p3=$!
run sndui "VGA NOINTRO NOMUSIC LOG SNDUI.TXT" 10 --log-lau &
p4=$!
wait $p1 $p2 $p3 $p4

for n in geo sndbat sndai sndui; do
  grep -aq '\[kill\]' $O/$n/816/console.txt && { echo "FAIL  $n: $(grep -a '\[kill\]' $O/$n/816/console.txt)"; fail=1; }
  grep -aq 'music task' $O/$n/816/console.txt && { echo "FAIL  $n: $(grep -a 'music task' $O/$n/816/console.txt)"; fail=1; }
done
$PY tests/soundcheck.py opl "geo music" $O/geo/opl.txt $O/geo/816/emu.err 1456 30 last || fail=1
$PY tests/soundcheck.py opl "battle music (load, redraws)" $O/sndbat/opl.txt \
  $O/sndbat/816/emu.err 1456 30 || fail=1
$PY tests/soundcheck.py sfx "battle effects" $O/sndbat/sb.txt $O/sndbat/816/console.txt \
  $O/sndbat/816/emu.err 3 "has:rifle,step 1a,step 1b,step 2b" || fail=1
$PY tests/soundcheck.py sfx "the interface's effects" $O/sndui/sb.txt $O/sndui/816/console.txt \
  $O/sndui/816/emu.err 0 WBWBBWBWBBWBBWBWBBW || fail=1
$PY tests/soundcheck.py quieter "the interface under the shots" $O/sndui/816.wav 0 30 \
  $O/sndbat/816.wav 0 60 || fail=1
$PY tests/soundcheck.py wav "geo recording" $O/geo/816.wav 20 40 150 || fail=1
$PY tests/soundcheck.py wav "battle recording" $O/sndbat/816.wav 20 40 150 || fail=1

L=$O/sndai/816/card/GAMES/XCOM/SNDAI.TXT
if grep -q "alien turn" $L 2>/dev/null; then
  $PY tests/soundcheck.py opl "music through the aliens' turn ($(grep -m1 'alien turn' $L | sed 's/^T1: //'), the whole run)" \
    $O/sndai/opl.txt $O/sndai/816/emu.err 0 30 || fail=1
else
  echo "FAIL  sndai: the Atari816 did not reach the aliens' turn (no 'alien turn' in SNDAI.TXT)"; fail=1
fi

if [ $fail = 0 ]; then echo "sound: all passed"; else echo "sound: FAILED"; fi
exit $fail

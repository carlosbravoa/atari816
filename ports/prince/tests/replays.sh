#!/bin/sh
# tests/replays.sh - the test replays (build/replays/NAME.p1r) from tests/replays/NAME.p1x
# and the game's levels (data/sdlpop/data/LEVELS, tools/getdata.sh): a replay holds a
# savestate, and so the level's map, which stays out of git (tools/p1rstrip.py). Each must
# come out byte for byte as recorded (the MD5 in its .p1x). A new replay recorded on the PC:
#   python3 tools/p1rstrip.py strip NAME.p1r tests/replays/NAME.p1x
cd "$(dirname "$0")/.." || exit 1
mkdir -p build/replays
n=0
for x in tests/replays/*.p1x; do
  python3 tools/p1rstrip.py build "$x" "build/replays/$(basename "$x" .p1x).p1r" ||
    { echo "the replays: $x not rebuilt"; exit 1; }
  n=$((n + 1))
done
echo "the replays: $n rebuilt from the game's levels (tests/replays/*.p1x), each byte for byte as recorded (MD5)"

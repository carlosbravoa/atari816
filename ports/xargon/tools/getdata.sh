#!/bin/sh
# tools/getdata.sh - the game's own files (all three episodes, freeware since 2008), into
# data/orig/ (kept out of git: see README.md, "Licence"). Either
#
#   sh tools/getdata.sh                 download Xargon_Commercial.zip (the freeware release
#                                       of the registered game, Classic DOS Games) and check
#                                       its SHA-256
#   sh tools/getdata.sh DIR             take them from your own copy (the folder with
#                                       GRAPHICS.XR1, BOARD_01.XR1, ...)
#   sh tools/getdata.sh FILE.zip        from that zip
#
# Then `make data` converts them (tools/mkdata.py) into data/card/.
set -e
src=$1
if [ -n "$src" ]; then
  case $src in /*) ;; *) src=$PWD/$src;; esac
fi
cd "$(dirname "$0")/.."
URL=https://www.classicdosgames.com/files/games/epic/Xargon_Commercial.zip
SUM=16211df28b6b12822d6fc46e3f915ad0e55de07c656f72160e344f32a37f9c18
mkdir -p data
rm -rf data/orig data/tmp
mkdir -p data/orig data/tmp
if [ -z "$src" ]; then
  echo "getdata: downloading $URL"
  if command -v curl >/dev/null; then curl -sSfL -o data/tmp/x.zip "$URL"
  else wget -q -O data/tmp/x.zip "$URL"; fi
  got=$(sha256sum data/tmp/x.zip | cut -d' ' -f1)
  if [ "$got" != "$SUM" ]; then
    echo "getdata: the zip's SHA-256 is $got, not $SUM: not used" >&2; exit 1
  fi
  src=$PWD/data/tmp/x.zip
fi
if [ -d "$src" ]; then
  cp "$src"/* data/orig/
else
  (cd data/tmp && unzip -q -o "$src")
  find data/tmp -type f ! -name x.zip -exec cp {} data/orig/ \;
fi
rm -rf data/tmp
ls data/orig | grep -qi '^graphics\.xr1$' || { echo "getdata: no GRAPHICS.XR1 in $1" >&2; exit 1; }
echo "getdata: $(ls data/orig | wc -l) files in data/orig"

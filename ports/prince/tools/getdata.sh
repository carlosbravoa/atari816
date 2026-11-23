#!/bin/sh
# tools/getdata.sh - SDLPoP at the pinned commit (its data/ folder: the DOS game's graphics,
# levels, sounds and music, extracted by SDLPoP's authors), into data/sdlpop/ (kept out of
# git: see README.md, "Data and licences"). Either
#
#   sh tools/getdata.sh                 download SDLPoP's source archive from GitHub at commit
#                                       f7be2e9 and check its SHA-256
#   sh tools/getdata.sh DIR             take it from your own SDLPoP checkout (the folder with
#                                       data/ and src/)
#   sh tools/getdata.sh FILE.tar.gz     from that archive
#
# Then `make data` converts what the port needs (tools/mkdata.py) into data/card/.
set -e
src=$1
if [ -n "$src" ]; then
  case $src in /*) ;; *) src=$PWD/$src;; esac
fi
cd "$(dirname "$0")/.."
COMMIT=f7be2e939375d369d26e1d10bcdd5ca74d3002a2
URL=https://github.com/NagyD/SDLPoP/archive/$COMMIT.tar.gz
SUM=15e55632cd2607e0d8c5e97257bb19172213e551300d846542f4bf88a178cd01
mkdir -p data
rm -rf data/sdlpop data/tmp
mkdir -p data/tmp
if [ -z "$src" ]; then
  echo "getdata: downloading $URL"
  if command -v curl >/dev/null; then curl -sSfL -o data/tmp/s.tar.gz "$URL"
  else wget -q -O data/tmp/s.tar.gz "$URL"; fi
  got=$(sha256sum data/tmp/s.tar.gz | cut -d' ' -f1)
  if [ "$got" != "$SUM" ]; then
    echo "getdata: the archive's SHA-256 is $got, not $SUM: not used" >&2; exit 1
  fi
  src=$PWD/data/tmp/s.tar.gz
fi
if [ -d "$src" ]; then
  mkdir -p data/sdlpop
  cp -r "$src"/data "$src"/src "$src"/doc data/sdlpop/
else
  (cd data/tmp && tar xzf "$src")
  mv data/tmp/SDLPoP-* data/sdlpop
fi
rm -rf data/tmp
test -f data/sdlpop/data/KID/res400.pal || { echo "getdata: no data/KID/res400.pal in $1" >&2; exit 1; }
echo "getdata: SDLPoP's data in data/sdlpop/data ($(find data/sdlpop/data -type f | wc -l) files)"

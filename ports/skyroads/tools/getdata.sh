#!/bin/sh
# getdata.sh - the game's files into data/orig/ (not in git: they are Bluemoon's).
#
#   sh tools/getdata.sh          download skyroads.zip from Bluemoon's own page
#                                (http://www.bluemoon.ee/history/skyroads/) and check it
#   sh tools/getdata.sh DIR      use your copy: a folder with ROADS.LZS etc., or the zip
#
# SkyRoads is freeware: its readme.txt says "This program is freeware. You can distribute
# this program freely, as long as you don't reverse engineer, and/or modify this program
# or any of its accompanying files. This program must be distributed as a single unit,
# with all accompanying files included and intact in their original form." So the port
# does not distribute it: each user fetches the original zip; the converted files
# (data/card/) are made on the user's own machine and stay there.
set -e
cd "$(dirname "$0")/.."
URL=http://www.bluemoon.ee/history/skyroads/skyroads.zip
SHA=24762fe14196a642224288fe2063c9d0c0033be9c5b4b2f97fded09390803ee4
mkdir -p data/orig
if [ -n "$1" ]; then
    if [ -d "$1" ]; then
        for f in "$1"/*; do
            n=$(basename "$f" | tr a-z A-Z)
            cp "$f" "data/orig/$n"
        done
        test -f data/orig/ROADS.LZS || { echo "getdata: no ROADS.LZS in $1"; exit 1; }
        echo "getdata: copied from $1"
        exit 0
    fi
    cp "$1" data/skyroads.zip
else
    if command -v curl >/dev/null; then curl -sSL -o data/skyroads.zip "$URL"
    else wget -q -O data/skyroads.zip "$URL"; fi
fi
got=$(sha256sum data/skyroads.zip | cut -d' ' -f1)
if [ "$got" != "$SHA" ]; then
    echo "getdata: skyroads.zip is not the file this port was made with (sha256 $got)"
    echo "getdata: (expected $SHA, 593,740 bytes); continuing, but the tests may fail"
fi
(cd data/orig && unzip -o -q ../skyroads.zip)
echo "getdata: data/orig/ has $(ls data/orig | wc -l) files"

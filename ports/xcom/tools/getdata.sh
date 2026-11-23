#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Converts YOUR copy of X-COM: UFO Defense (DOS 1.4, e.g. the GOG or Steam install)
# into upstream's packs, with upstream's own converter (XCOMCONV, Python 3 + PyYAML):
#   sh tools/getdata.sh /path/to/X-COM [XCOMCONV options]  -> data/packs/
# (the GOG copy needs --skip-check: its fonts and ENGLISH.DAT differ from DOS 1.4's)
# The game's data and everything made from it stay out of git (data/ is ignored) and
# must not be shared. Needs upstream/ (tools/getsrc.sh).
set -e
cd "$(dirname "$0")/.."
GAME=${1:?usage: sh tools/getdata.sh /path/to/your/X-COM folder}
[ -d upstream/tools ] || sh tools/getsrc.sh
python3 -c 'import yaml' 2>/dev/null || { echo "getdata: XCOMCONV needs PyYAML (pip install pyyaml)" >&2; exit 1; }
rm -rf data/packs.tmp build/conv
mkdir -p data build/conv
# upstream's converter with this port's patches (patches/tools-*.patch), in a copy
cp -r upstream/tools upstream/data upstream/src build/conv/
for p in patches/tools-*.patch; do
    [ -f "$p" ] && patch -s -p1 -d build/conv < "$p"
done
shift
python3 -I build/conv/tools/xcomconv.py "$GAME" -o data/packs.tmp "$@"
rm -rf data/packs
mv data/packs.tmp data/packs
echo "getdata: data/packs ($(du -sh data/packs | cut -f1))"

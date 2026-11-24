#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Converts YOUR copy of X-COM: UFO Defense (DOS 1.4, e.g. the GOG or Steam install)
# into the engine's packs, with the fork's own converter (engine/tools/xcomconv.py,
# XCOMCONV: Python 3 + PyYAML):
#   sh tools/getdata.sh /path/to/X-COM [XCOMCONV options]  -> data/packs/
# (the GOG copy needs --skip-check: its fonts and ENGLISH.DAT differ from DOS 1.4's)
# The game's data and everything made from it stay out of git (data/ is ignored) and
# must not be shared.
set -e
cd "$(dirname "$0")/.."
GAME=${1:?usage: sh tools/getdata.sh /path/to/your/X-COM folder}
python3 -c 'import yaml' 2>/dev/null || { echo "getdata: XCOMCONV needs PyYAML (pip install pyyaml)" >&2; exit 1; }
rm -rf data/packs.tmp
mkdir -p data
shift
# -B: no __pycache__ written into engine/tools
python3 -I -B engine/tools/xcomconv.py "$GAME" -o data/packs.tmp "$@"
rm -rf data/packs
mv data/packs.tmp data/packs
echo "getdata: data/packs ($(du -sh data/packs | cut -f1))"

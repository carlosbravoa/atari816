#!/bin/sh
# emu-stats.sh - emu816 with --stats (the CPU's busy share, in emu.err): for run816.py --emu
exec "$(dirname "$0")/../../../../../emu/emu816" --stats "$@"

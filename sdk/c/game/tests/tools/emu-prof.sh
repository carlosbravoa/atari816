#!/bin/bash
# emu-prof.sh - emu816 with --trace, the trace run through prof816.py (for run816.py --emu).
# Set PROF_MAP (hcc --map's file), PROF_FROM, PROF_TO (emulated seconds since power-on)
# and PROF_OUT (the report).
here="$(dirname "$0")"
"$here/../../../../../emu/emu816" --trace "$@" 2> >(python3 "$here/prof816.py" \
    --map "$PROF_MAP" --from "${PROF_FROM:-0}" --to "${PROF_TO:-1000000}" \
    --out "${PROF_OUT:-/dev/stderr}")
rc=$?
wait
exit $rc

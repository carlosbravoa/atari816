#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/hostrun.sh NAME OUT OPTIONS...: one run of the host build (build/host/xcomhost) with
# tests/NAME.keys, in a game folder of its own (OUT/card: the packs linked, the LOG and any
# saves written there), pictures in OUT; stdout: the run's lines (xcom: shot ..., xcom: end)
name=$1 out=$2
shift 2
top=$(pwd)
rm -rf "$out" && mkdir -p "$out/card"
for f in "$top"/data/packs/*.PAK "$top"/data/packs/PACKS.VER "$top"/data/packs/VGA; do
    ln -s "$f" "$out/card/$(basename "$f")"
done
# (no KEYS without tests/NAME.keys: BENCH ends waiting for a key the BIOS way, where a
#  script that never ends would keep the run from its idle end)
k=; [ -f "tests/$name.keys" ] && k="KEYS $top/tests/$name.keys"
exec build/host/xcomhost -C "$out/card" -o "$out" -t 5 "$@" $k

#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# The host's reference runs alone (make check-host): each run of tests/runs on the host
# build, its pictures' checksums against tests/host.md5 (the data's pictures are not in
# git). make test (tests/check.sh) does this too, and compares the Atari816 with it.
#   sh tests/host.sh            check        sh tests/host.sh --refs     write host.md5 (look first)
set -e
cd "$(dirname "$0")/.."
out=build/host/check
rm -rf $out && mkdir -p $out
while read -r name args; do
    case "$name" in ''|\#*) continue ;; esac
    sh tests/hostrun.sh "$name" $out/$name $args > $out/$name.txt 2>&1
done < tests/runs
(cd $out && md5sum */shot*.ppm) > $out/host.md5
if [ "$1" = "--refs" ]; then cp $out/host.md5 tests/host.md5; echo "host: tests/host.md5 written"; exit 0; fi
if diff -u tests/host.md5 $out/host.md5; then echo "host: PASS ($(wc -l < $out/host.md5) pictures)"; else echo "host: FAIL"; exit 1; fi

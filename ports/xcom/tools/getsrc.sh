#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Fetches upstream XCOM-XT (GPL-3) at the pinned commit into upstream/ (not in git).
#   sh tools/getsrc.sh [DIR]     DIR: a clone of your own to copy from instead
# The port builds upstream's src/ through patches/ (applied by the Makefile into
# build/src): to move to a newer upstream, change COMMIT, run this again and
# refresh the patches (PORTING-NOTES.md, "Keeping the port mergeable").
set -e
COMMIT=a53918220c902a44608c3ebdecf8a40710805cba     # 18 Nov 2026, Alpha 0.5.1
URL=https://github.com/fmikowski/xcom-xt
cd "$(dirname "$0")/.."
rm -rf upstream.tmp
if [ -n "$1" ]; then
    git -C "$1" archive "$COMMIT" > /dev/null 2>&1 || { echo "getsrc: $1 has no commit $COMMIT" >&2; exit 1; }
    mkdir upstream.tmp
    git -C "$1" archive "$COMMIT" | tar -x -C upstream.tmp
else
    git init -q upstream.tmp
    git -C upstream.tmp fetch -q --depth 1 "$URL" "$COMMIT"
    git -C upstream.tmp checkout -q FETCH_HEAD
    rm -rf upstream.tmp/.git
fi
rm -rf upstream
mv upstream.tmp upstream
echo "$COMMIT" > upstream/COMMIT
echo "getsrc: upstream/ at $COMMIT ($(ls upstream/src/*.c | wc -l) C files)"

#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# The port's changes to upstream's src/ as one patch: diff of a pristine copy (A) and the
# edited copy (B), both holding src/:  sh tools/mkpatch.sh A B > patches/src-0001-port.patch
A=$(cd "$1" && pwd); B=$(cd "$2" && pwd)
cd "$A" && diff -ruN src "$B/src" | sed "s|^--- src/|--- a/src/|; s|^+++ $B/src/|+++ b/src/|"
true

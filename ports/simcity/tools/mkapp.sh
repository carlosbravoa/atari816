#!/bin/sh
# tools/mkapp.sh DIR: the app's folder for the archive (make app)
D=$1
rm -rf "$D"
mkdir -p "$D"
cp MICROPOL.PRG build/MICROPOL.ICN "$D/"
cp -r build/card/* "$D/"
grep -v '^#' app/APP.INF > "$D/APP.INF"

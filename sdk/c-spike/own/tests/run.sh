#!/bin/sh
# run.sh NAME PRG [run816 options...] - run a program in emu816 (output in build/run-NAME)
here=$(cd "$(dirname "$0")" && pwd)
own=$(dirname "$here")
name=$1; prg=$2; shift 2
exec python3 "$own/../../tools/run816.py" "$prg" --horizon "$own/../../../horizon" --out "$own/build/run-$name" "$@"

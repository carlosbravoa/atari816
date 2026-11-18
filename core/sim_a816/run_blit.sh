#!/bin/sh
# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
# Randomised blitter test (a816_blit + the a816_nvc port mux), Verilator >= 5.
set -e
cd "$(dirname "$0")"
A=../src/a816
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb_blit -Mdir obj_blit -o tb \
  $A/a816_nvc.sv $A/a816_blit.sv tb_blit.sv > obj_blit_build.log 2>&1 || { tail -30 obj_blit_build.log; exit 1; }
./obj_blit/tb "$@"

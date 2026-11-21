#!/bin/sh
# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
# Simulate the bring-up 1 test program on a816_sys (Verilator >= 5).
set -e
cd "$(dirname "$0")"
A=../src/a816
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb_a816 -Mdir obj -o tb \
  $A/common.sv $A/${MCODE:-mcode_packed.sv} $A/ALU.v $A/AddSubBCD.v $A/AddrGen.v $A/BCDAdder.v $A/adder4.v $A/bit_adder.v \
  $A/P65C816.v $A/a816_sys.sv $A/a816_nvc.sv $A/a816_blit.sv $A/a816_snd.sv $A/a816_opl.sv \
  $A/jtopl/*.v tb_a816.sv > obj_build.log 2>&1 || { tail -30 obj_build.log; exit 1; }
./obj/tb "$@"

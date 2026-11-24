#!/bin/sh
# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
# The HDMI diagnostic counters (src/hdmi_diag.sv) against forced lock glitches, raster
# restarts and genlock jumps (Verilator >= 5). Prints "tb_hdmi_diag: PASS" or the failures.
set -e
cd "$(dirname "$0")"
verilator --lint-only -Wall -Wno-SYNCASYNCNET ../src/hdmi_diag.sv
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb_hdmi_diag \
  -Mdir obj_hdmi_diag -o tb ../src/hdmi_diag.sv tb_hdmi_diag.sv > obj_hdmi_diag.log 2>&1 \
  || { tail -40 obj_hdmi_diag.log; exit 1; }
./obj_hdmi_diag/tb

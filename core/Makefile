# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
GOWIN_SH := $(HOME)/Documents/gowin/IDE/bin/gw_sh.sh

.PHONY: syn clean

# Stage 1: synthesis only — reports LUT/register count, no bitstream
syn:
	cd $(dir $(abspath $(lastword $(MAKEFILE_LIST)))) && $(GOWIN_SH) build.tcl

clean:
	rm -rf impl/

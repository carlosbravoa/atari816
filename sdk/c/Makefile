# The Horizon C SDK: cc816 (sdk/c/cc816, the default compiler) and vbcc 65816.
#
#   make            the C library for cc816 and for vbcc's two memory models (build/lib/;
#                   vbcc's only when its toolchain is installed), and the controls
#                   library's objects for vbcc (build/ui/)
#   make gen        include/hzsys.h again from horizon.inc, ABI.md, tools/syscalls.tab;
#                   include/huigen.h from ui.inc, icons.inc and ui/hui.tab
#   make check      include/hzsys.h against horizon.inc and ABI.md (count, numbers, names);
#                   the controls library's binding against ui.inc and ulib (genhui.py)
#   make test       make check, then every test in the emulator (tests/run.py: PASS or
#                   FAIL per test and compiler/model: cc816, vbcc large, vbcc tiny; the
#                   controls library's tests and the c-window-app template), the examples
#                   and the c-console template, and the game library's tests (both
#                   compilers), each with the default compiler (HZ_CC=vbcc for vbcc)
#   make clean
#
# cc816 needs Python 3 and cc65's ca65/ld65/ar65; vbcc its toolchain first:
# tools/get-toolchain.sh (docs/c/getting-started.md). Without it, make test runs only
# cc816 (tests/run.py --cc cc816).
# HORIZON: the Horizon tree (default: the repository's); make test needs it built.

HORIZON ?= $(abspath ../../horizon)
export HORIZON
PYTHON  ?= python3
EXAMPLES := examples/hello examples/window examples/wc ../templates/c-console
# the controls library (hui.h): the tutorial's steps, an example (c-window-app is in
# tests/run.py's uitwin)
EXAMPLES += examples/guests examples/viewer

VBCC := $(wildcard toolchain/vbcc/bin/vbcc65816)$(HZ_VBCC)
# the compilers make test runs the examples with
CCS  ?= cc816 $(if $(VBCC),vbcc)

all:
	$(PYTHON) bin/hcc --build-lib cc816
	$(if $(VBCC),$(PYTHON) bin/hcc --build-lib large tiny && $(PYTHON) bin/hcc --build-ui,@echo "(no vbcc toolchain: cc816 only)")

gen:
	$(PYTHON) tools/gensys.py --horizon $(HORIZON)
	$(PYTHON) tools/genhui.py --horizon $(HORIZON)

check:
	$(PYTHON) tools/gensys.py --check --horizon $(HORIZON)
	$(PYTHON) tools/genhui.py --check --horizon $(HORIZON)

test: check
	$(PYTHON) tests/run.py --horizon $(HORIZON) $(if $(VBCC),,--cc cc816)
	@set -e; for cc in $(CCS); do for p in $(EXAMPLES); do echo "== $$p ($$cc)"; \
	  $(MAKE) --no-print-directory -C $$p test HORIZON=$(HORIZON) HZ_CC=$$cc; done; done
	$(MAKE) --no-print-directory -C game test HORIZON=$(HORIZON) CCS="$(CCS)"
	@echo "C SDK: ALL TESTS PASSED"

clean:
	rm -rf build
	@for p in $(EXAMPLES) ../templates/c-window-app; do $(MAKE) --no-print-directory -C $$p clean; done

.PHONY: all gen check test clean

# The Horizon C SDK (vbcc 65816).
#
#   make            the C library for both memory models (build/lib/), and the controls
#                   library's objects (build/ui/: needs cc65's ca65, ld65, ar65)
#   make gen        include/hzsys.h again from horizon.inc, ABI.md, tools/syscalls.tab;
#                   include/huigen.h from ui.inc, icons.inc and ui/hui.tab
#   make check      include/hzsys.h against horizon.inc and ABI.md (count, numbers, names);
#                   the controls library's binding against ui.inc and ulib (genhui.py)
#   make test       make check, then every test in the emulator (tests/run.py: PASS or
#                   FAIL per test and model, the controls library's tests and the
#                   c-window-app template), the examples and the c-console template
#   make clean
#
# The toolchain first: tools/get-toolchain.sh (docs/c/getting-started.md).
# HORIZON: the Horizon tree (default: the repository's); make test needs it built.

HORIZON ?= $(abspath ../../horizon)
export HORIZON
PYTHON  ?= python3
EXAMPLES := examples/hello examples/window examples/wc ../templates/c-console
# the controls library (hui.h): the tutorial's steps, an example (c-window-app is in
# tests/run.py's uitwin)
EXAMPLES += examples/guests examples/viewer

all:
	$(PYTHON) bin/hcc --build-lib
	$(if $(shell command -v ca65),$(PYTHON) bin/hcc --build-ui,@echo "(no ca65: the controls library is built when a program first uses it)")

gen:
	$(PYTHON) tools/gensys.py --horizon $(HORIZON)
	$(PYTHON) tools/genhui.py --horizon $(HORIZON)

check:
	$(PYTHON) tools/gensys.py --check --horizon $(HORIZON)
	$(PYTHON) tools/genhui.py --check --horizon $(HORIZON)

test: check
	$(PYTHON) tests/run.py --horizon $(HORIZON)
	@set -e; for p in $(EXAMPLES); do echo "== $$p"; \
	  $(MAKE) --no-print-directory -C $$p test HORIZON=$(HORIZON); done
	$(MAKE) --no-print-directory -C game test HORIZON=$(HORIZON)
	@echo "C SDK: ALL TESTS PASSED"

clean:
	rm -rf build
	@for p in $(EXAMPLES) ../templates/c-window-app; do $(MAKE) --no-print-directory -C $$p clean; done

.PHONY: all gen check test clean

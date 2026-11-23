# The Horizon C SDK: hcc (bin/hcc) and cc816 (cc816/), the C library (lib/, rt/), the
# controls library's binding (ui/), the game library (game/).
#
#   make            the C library for both code models (build/lib/small, build/lib/large)
#   make gen        include/hzsys.h again from horizon.inc, ABI.md, tools/syscalls.tab;
#                   include/huigen.h from ui.inc, icons.inc and ui/hui.tab
#   make check      include/hzsys.h against horizon.inc and ABI.md (count, numbers, names);
#                   the controls library's binding against ui.inc and ulib (genhui.py)
#   make test       make check, then every test in the emulator (tests/run.py: PASS or
#                   FAIL per test and code model: small, large; the controls library's
#                   tests and the c-window-app template), the examples and the c-console
#                   template, the game library's tests (game/Makefile), the large code
#                   model with two examples (LARGE_EXAMPLES), and the skill's examples
#                   (sdk/skill/atari-816-dev/examples)
#   make clean
#
# Needs Python 3 and cc65's ca65/ld65/ar65 (docs/c/getting-started.md).
# HORIZON: the Horizon tree (default: the repository's); make test needs it built.

HORIZON ?= $(abspath ../../horizon)
export HORIZON
PYTHON  ?= python3
EXAMPLES := examples/hello examples/window examples/wc ../templates/c-console
# the controls library (hui.h): the tutorial's steps, an example (c-window-app is in
# tests/run.py's uitwin)
EXAMPLES += examples/guests examples/viewer

# built with cc816's large code model too (hcc --code large, every function that can move
# in another bank: a controls-library program and a game; the game library's tests run in
# that model too: game/Makefile)
LARGE_EXAMPLES := examples/viewer examples/glimmer

# the skill's examples (sdk/skill/atari-816-dev/examples/*: built and tested there)
SKILL := ../skill/atari-816-dev

all:
	$(PYTHON) bin/hcc --build-lib small large

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
	@set -e; for p in $(LARGE_EXAMPLES); do echo "== $$p (--code large)"; \
	  $(MAKE) --no-print-directory -C $$p test HORIZON=$(HORIZON) HZ_CODE=large \
	  HCCFLAGS="--main-room 0 --bank-room 16384"; done
	$(PYTHON) $(SKILL)/examples/check.py --horizon $(HORIZON)
	@echo "C SDK: ALL TESTS PASSED"

clean:
	rm -rf build
	@for p in $(EXAMPLES) ../templates/c-window-app; do $(MAKE) --no-print-directory -C $$p clean; done

.PHONY: all gen check test clean

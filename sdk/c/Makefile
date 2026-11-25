# The Horizon C SDK: hcc (bin/hcc) and cc816 (cc816/), the C library (lib/, rt/), the
# controls library's binding (ui/), the game library (game/).
#
#   make            the C library for both code models (build/lib/small, build/lib/large)
#                   and for the far data model (build/lib/large-far: hcc --data far)
#   make gen        include/hzsys.h again from horizon.inc, ABI.md, tools/syscalls.tab;
#                   include/huigen.h from ui.inc, icons.inc and ui/hui.tab
#   make check      include/hzsys.h against horizon.inc and ABI.md (count, numbers, names);
#                   the controls library's binding against ui.inc and ulib (genhui.py);
#                   the manual is complete (sdk/tools/doccheck.py: every public function,
#                   header, tool and option is in sdk/docs) and its web site builds with
#                   every link resolved (sdk/tools/mkmanual.py --check, into build/manual)
#   make test      make check, then every test in the emulator (tests/run.py: PASS or
#                   FAIL per test and code model: small, large; the controls library's
#                   tests and the c-window-app template), the examples and the c-console
#                   template, the game library's tests (game/Makefile), the large code
#                   model with three examples (LARGE_EXAMPLES), and the skill's examples
#                   (sdk/skill/atari-816-dev/examples); tools/host16.py's test
#                   (tests/host16: the PC build with the Atari816's types)
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
# movable assembly (rt/model.inc's FUNC): C and assembly calling each other
EXAMPLES += examples/asmfar

# built with cc816's large code model too (hcc --code large, every function that can move
# in another bank: a controls-library program and a game; the game library's tests run in
# that model too: game/Makefile; asmfar: assembly that moves as C does)
LARGE_EXAMPLES := examples/viewer examples/glimmer examples/asmfar
# built with far data too (hcc --code large --data far): a console program and a game
FAR_EXAMPLES := examples/hello examples/wc examples/glimmer

# the skill's examples (sdk/skill/atari-816-dev/examples/*: built and tested there)
SKILL := ../skill/atari-816-dev

all:
	$(PYTHON) bin/hcc --build-lib small large large-far

gen:
	$(PYTHON) tools/gensys.py --horizon $(HORIZON)
	$(PYTHON) tools/genhui.py --horizon $(HORIZON)

check:
	$(PYTHON) tools/gensys.py --check --horizon $(HORIZON)
	$(PYTHON) tools/genhui.py --check --horizon $(HORIZON)
	$(PYTHON) ../tools/doccheck.py
	$(PYTHON) ../tools/mkmanual.py -o build/manual --check

test: check
	$(PYTHON) tests/host16/check.py
	$(PYTHON) tests/run.py --horizon $(HORIZON)
	@set -e; for p in $(EXAMPLES); do echo "== $$p"; \
	  $(MAKE) --no-print-directory -C $$p test HORIZON=$(HORIZON); done
	$(MAKE) --no-print-directory -C game test HORIZON=$(HORIZON)
	@set -e; for p in $(LARGE_EXAMPLES); do echo "== $$p (--code large)"; \
	  $(MAKE) --no-print-directory -C $$p test HORIZON=$(HORIZON) HZ_CODE=large \
	  HCCFLAGS="--main-room 0 --bank-room 16384"; done
	@set -e; for p in $(FAR_EXAMPLES); do echo "== $$p (--code large --data far)"; \
	  $(MAKE) --no-print-directory -C $$p test HORIZON=$(HORIZON) HZ_CODE=large \
	  HZ_DATA=far HCCFLAGS="--main-room 0 --bank-room 16384"; done
	$(PYTHON) $(SKILL)/examples/check.py --horizon $(HORIZON)
	@echo "C SDK: ALL TESTS PASSED"

clean:
	rm -rf build
	@for p in $(EXAMPLES) ../templates/c-window-app; do $(MAKE) --no-print-directory -C $$p clean; done

.PHONY: all gen check test clean

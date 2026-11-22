# hgame, the game library of the Horizon C SDK (hgame.h, conio.h, joystick.h).
#
#   make            the library: ../build/game/cc816/libhgame.lib (cc816) and
#                   ../build/game/large/libhgame.a (vbcc); hcc also builds it by itself
#                   when a program includes one of the headers
#   make test       for each compiler (CCS, default "cc816 vbcc"): tests/run.py (every
#                   part of the library in the emulator: the programs' own checks,
#                   screenshots against tests/ref/ (the same pictures for both), the
#                   sound logs and the recorded output), then the examples (glimmer,
#                   catch, the tutorial) and the c-game template, each with its run
#   make refs       the same tests, writing their screenshots as the new references
#   make font       hg_font.c again from Horizon's console font (tools/mkfont.py)
#   make clean
#
# HORIZON: the Horizon tree with a built card (default: the repository's).

HORIZON ?= $(abspath ../../../horizon)
export HORIZON
PYTHON  ?= python3
PROGRAMS := ../examples/glimmer ../examples/catch ../examples/tutorial ../../templates/c-game
# the compilers: the tests and every program run with each
CCS     ?= cc816 $(if $(wildcard ../toolchain/vbcc/bin/vbcc65816)$(HZ_VBCC),vbcc)

all:
	$(PYTHON) hgbuild.py $(if $(filter vbcc,$(CCS)),,--cc cc816)
	$(if $(filter vbcc,$(CCS)),,@echo "(no vbcc toolchain: cc816 only)")

test: all
	@set -e; for cc in $(CCS); do $(PYTHON) tests/run.py --horizon $(HORIZON) --cc $$cc; done
	@set -e; for cc in $(CCS); do for p in $(PROGRAMS); do echo "== $$p ($$cc)"; \
	  rm -f $$p/*.PRG; $(MAKE) --no-print-directory -C $$p test HORIZON=$(HORIZON) HZ_CC=$$cc; \
	  done; done
	@echo "hgame: ALL TESTS PASSED"

refs: all
	$(PYTHON) tests/run.py --horizon $(HORIZON) --update-refs

font:
	$(PYTHON) tools/mkfont.py $(HORIZON)/kernel/font8x12.txt -o hg_font.c

clean:
	rm -rf ../build/game ../build/game-tests
	@for p in $(PROGRAMS); do $(MAKE) --no-print-directory -C $$p clean; done

.PHONY: all test refs font clean

# hgame, the game library of the Horizon C SDK (hgame.h, conio.h, joystick.h).
#
#   make            the library: ../build/game/small/libhgame.lib and
#                   ../build/game/large/libhgame.lib (the two code models); hcc also
#                   builds it by itself when a program includes one of the headers
#   make test       tests/run.py in both code models (small, and large: hcc --code large,
#                   every function that can move in another bank): every part of the
#                   library in the emulator: the programs' own checks, screenshots
#                   against tests/ref/ (the same pictures for both), the sound logs and
#                   the recorded output; then the examples (glimmer, catch, the
#                   tutorial) and the c-game template, each with its run
#   make refs       the same tests, writing their screenshots as the new references
#   make font       hg_font.c again from Horizon's console font (tools/mkfont.py)
#   make clean
#
# HORIZON: the Horizon tree with a built card (default: the repository's).

HORIZON ?= $(abspath ../../../horizon)
export HORIZON
PYTHON  ?= python3
PROGRAMS := ../examples/glimmer ../examples/catch ../examples/tutorial ../../templates/c-game
# the code models tests/run.py runs in
CODES   ?= small large

all:
	$(PYTHON) hgbuild.py

test: all
	@set -e; for c in $(CODES); do \
	  $(PYTHON) tests/run.py --horizon $(HORIZON) --code $$c; done
	@set -e; for p in $(PROGRAMS); do echo "== $$p"; \
	  rm -f $$p/*.PRG; $(MAKE) --no-print-directory -C $$p test HORIZON=$(HORIZON); done
	@echo "hgame: ALL TESTS PASSED"

refs: all
	$(PYTHON) tests/run.py --horizon $(HORIZON) --update-refs

font:
	$(PYTHON) tools/mkfont.py $(HORIZON)/kernel/font8x12.txt -o hg_font.c

clean:
	rm -rf ../build/game ../build/game-tests
	@for p in $(PROGRAMS); do $(MAKE) --no-print-directory -C $$p clean; done

.PHONY: all test refs font clean

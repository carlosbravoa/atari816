# The Atari816 SDK.
#
#   make check      the reference against Horizon's sources (tools/abicheck.py: syscall
#                   numbers, names, constants) and every example of the reference
#                   assembled and linked (tools/snippets.py)
#   make test       make check, then every template and example: build, run in the
#                   emulator with its input script, check its output (screenshots in
#                   each project's build/test/)
#   make probe      the performance probe (docs/reference/performance.md); REV=7: no blitter
#   make clean
#
# HORIZON: the Horizon tree (default: the one next to the SDK). It must be built (make -C
# $(HORIZON)) for make test and make probe; make check only needs user/, kernel/ and
# build/ulib.o, build/ui.lib.

HORIZON ?= $(abspath ../horizon)
export HORIZON
PROJECTS := templates/console templates/window-app templates/game templates/basic-game \
            examples/lantern examples/slider examples/hexview examples/deepdive \
            examples/fetch examples/echo
REV     ?= 8

all: check

check: $(HORIZON)/build/ulib.o
	python3 tools/abicheck.py --horizon $(HORIZON)
	python3 tools/snippets.py --horizon $(HORIZON)

$(HORIZON)/build/ulib.o:
	$(MAKE) -C $(HORIZON) build/ulib.o build/ui.lib

test: check
	@set -e; for p in $(PROJECTS); do \
	  if [ -f $$p/Makefile ]; then echo "== $$p"; $(MAKE) --no-print-directory -C $$p test HORIZON=$(HORIZON); fi; \
	done
	@echo "SDK TESTS PASSED"

probe: $(HORIZON)/build/ulib.o
	mkdir -p build/probe
	ca65 -I $(HORIZON)/user -o build/probe/probe.o tools/probe/probe.s
	ld65 -C $(HORIZON)/user/prog.cfg -o build/probe/PROBE.PRG build/probe/probe.o $(HORIZON)/build/ulib.o
	python3 tools/run816.py build/probe/PROBE.PRG --horizon $(HORIZON) --mode shell \
	    --rev $(REV) --seconds 50 --out build/probe/run
	@sed -n '/^content/,/^>/p' build/probe/run/console.txt

clean:
	rm -rf build
	@for p in $(PROJECTS); do [ -f $$p/Makefile ] && $(MAKE) --no-print-directory -C $$p clean || true; done

.PHONY: all check test probe clean

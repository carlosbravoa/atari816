# guests - the steps of the C application tutorial (sdk/docs/c/apps.md): step1.c (an
# empty window) to step5.c (Guests: a list, files, menus, a timer).
#
#   make            STEP1.PRG .. STEP5.PRG
#   make test       each one run in the emulator (the Desktop starts it) with its script
#                   (stepN.script), its console lines checked; step 5's file too
#   make clean
SDK     ?= ../../..
HORIZON ?= $(SDK)/../horizon
PYTHON  ?= python3
HCC     := $(PYTHON) $(SDK)/c/bin/hcc
RUN     := $(PYTHON) $(SDK)/tools/run816.py --horizon $(HORIZON) --mode desktop
STEPS   := 1 2 3 4 5

all: $(foreach n,$(STEPS),STEP$(n).PRG)

STEP%.PRG: step%.c
	$(HCC) -o $@ $<

test: all
	$(RUN) STEP1.PRG --script step1.script --out build/step1 --expect 'guests: closed'
	$(RUN) STEP2.PRG --script step2.script --out build/step2 --expect 'guests: welcome Ada'
	$(RUN) STEP3.PRG --script step3.script --out build/step3 --expect 'guests: about 0' \
	    --expect 'guests: quit'
	$(RUN) STEP4.PRG --script step4.script --out build/step4 \
	    --expect 'guests: Ada selected' --expect 'guests: Ada opened'
	$(RUN) STEP5.PRG --script step5.script --out build/step5 \
	    --expect 'guests: saved 2 to /GUESTS.TXT' --expect 'guests: read 2 from /GUESTS.TXT'
	test "$$(cat build/step5/card/GUESTS.TXT)" = "$$(printf 'Ada\nBob')"
	@echo "PASS  the tutorial's five steps"

clean:
	rm -rf build STEP*.PRG

.PHONY: all test clean

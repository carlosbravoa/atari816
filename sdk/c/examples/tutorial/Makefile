# The tutorial of sdk/docs/c/games.md: five steps from an empty file to a small game.
#
#   make            STEP1.PRG .. STEP5.PRG (the art first: art/*.txt -> art/*.h)
#   make run N=3    run step 3 in the emulator (the Desktop starts it), build/run3/
#   make test       every step built and run with a short script (screenshots in
#                   build/testN/; steps 3-5 checked by their console lines)
#   make clean

SDK     ?= ../../..
HORIZON ?= $(SDK)/../horizon
PYTHON  ?= python3
HCC     := $(PYTHON) $(SDK)/c/bin/hcc
RUN816  := $(PYTHON) $(SDK)/tools/run816.py --horizon $(HORIZON) --mode desktop
ART     := art/ship.h art/star.h
STEPS   := STEP1.PRG STEP2.PRG STEP3.PRG STEP4.PRG STEP5.PRG
N       ?= 1

all: $(STEPS)

STEP%.PRG: step%.c $(ART)
	$(HCC) -o $@ $<

art/%.h: art/%.txt $(SDK)/tools/img2c.py
	$(PYTHON) $(SDK)/tools/img2c.py $< -o $@ --name $* --key 0

run: STEP$(N).PRG
	$(RUN816) STEP$(N).PRG --script $(if $(filter 5,$(N)),test5.script,test.script) \
	    --out build/run$(N)

test: $(STEPS)
	$(RUN816) STEP1.PRG --script test.script --out build/test1
	$(RUN816) STEP2.PRG --script test.script --out build/test2
	$(RUN816) STEP3.PRG --script test.script --out build/test3 --expect 'STEP3: score'
	$(RUN816) STEP4.PRG --script test.script --out build/test4 --expect 'STEP4: '
	$(RUN816) STEP5.PRG --script test5.script --out build/test5 --expect 'STEP5: play' \
	    --expect 'STEP5: game over' --expect 'STEP5: '

clean:
	rm -rf build $(STEPS) art/*.h

.PHONY: all run test clean

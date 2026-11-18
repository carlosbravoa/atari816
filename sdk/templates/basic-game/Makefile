# A Horizon BASIC game: STARFALL.BAS. Nothing to build: BASIC.PRG runs the text file.
#
#   make run        run it in the emulator: the text shell types "basic -r /APPS/STARFALL.BAS"
#                   (BASIC starts the window system itself), screenshots in build/run/
#   make test       the scripted test: BASIC's test mode (-t) runs test.bas, which loads and
#                   runs the game; the input script plays and stops it with Esc; the console
#                   must show the break and no error
#   make clean
#
# On the machine: copy the .BAS file to the card and open it in Files (or BASIC's
# File > Load..., or "basic -r FILE" in the Terminal). Language: horizon/BASIC.md (2.0: the
# sprites need REV $0B, the samples REV $0A: the emulator's default).

GAME    := STARFALL.BAS
HORIZON ?= ../../../horizon
SDK     ?= ../..
CARD    := $(HORIZON)/build/sd/SYSTEM/HORIZON.SYS
BASIC   := $(HORIZON)/build/sd/BIN/BASIC.PRG
RUN816  := python3 $(SDK)/tools/run816.py --horizon $(HORIZON) --mode shell \
           $(BASIC) --dest /BIN/BASIC.PRG --file $(GAME):/APPS/$(GAME)

all:
	@echo "nothing to build: make run, make test"

$(CARD) $(BASIC):
	$(MAKE) -C $(HORIZON)

run: $(CARD)
	$(RUN816) --args "-r /APPS/$(GAME)" --script test.script --out build/run

test: $(CARD)
	$(RUN816) --file test.bas:/APPS/TEST.BAS --args "-t /APPS/TEST.BAS" \
	    --script test.script --out build/test --expect "Break in" --log-sound
	@if grep -a -i "error" build/test/console.txt; then echo "FAIL  BASIC reported an error"; exit 1; \
	else echo "PASS  no BASIC error"; fi

clean:
	rm -rf build

.PHONY: all run test clean

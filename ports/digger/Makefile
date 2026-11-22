# Digger (ports/digger): Digger Remastered on Horizon (the Atari816).
#
#   make            DIGGER.PRG and DIGGER.DAT (the pictures, from upstream's C files)
#   make run        the scripted game (tests/play.script) in the emulator: build/run/
#   make test       the same, checked (tests/check.sh): the high score file, the sound
#                   writes, the game's own recording played back; pictures at given game
#                   frames of a recorded game against tests/ref/ (tests/frames.sh); and
#                   upstream's recorded games played back as upstream plays them (drf.sh)
#   make refs       new reference pictures (after a change meant to show: look at them)
#   make clean
# HORIZON=DIR: a Horizon tree with a built card, 0.28 or later (a large program).

NAME      := digger
SDK       ?= ../../sdk
RUNMODE   := desktop
HZ_CODE   ?= large
SRCS      := $(wildcard src/*.c) $(wildcard horizon/*.c) horizon/hz_blit.s build/alpha_ok.c
HCCFLAGS  += --map --stack 4096 --heap 4096 -D_HORIZON -Dmain=digger_main -I src -I horizon -fsigned-char
SCRIPT    := tests/play.script
RUNFLAGS  += --file DIGGER.DAT:/APPS/DIGGER.DAT --seconds 74
TESTFLAGS := --log-sound --expect 'digger: paced frames'
TESTCHECK := sh tests/check.sh $(HORIZON)
include $(SDK)/c/c.mk

all: DIGGER.DAT

$(PRG): build/alpha_ok.c $(wildcard src/*.h horizon/*.h)

DIGGER.DAT build/alpha_ok.c: tools/mkdata.py src/data/vgagrafx.c src/data/alpha.c src/data/title_gz.c
	@mkdir -p build
	$(PYTHON) tools/mkdata.py src/data -o DIGGER.DAT --c build/alpha_ok.c

run test: DIGGER.DAT

refs: $(PRG) DIGGER.DAT $(CARD)
	sh tests/frames.sh $(HORIZON) --update
.PHONY: refs

clean: cleandat
cleandat:
	rm -f DIGGER.DAT
.PHONY: cleandat

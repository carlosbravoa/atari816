# Digger (ports/digger): Digger Remastered on Horizon (the Atari816).
#
#   make            DIGGER.PRG and DIGGER.DAT (the pictures, from upstream's C files)
#   make run        the scripted game (tests/play.script) in the emulator: build/run/
#   make test       the same, checked (tests/check.sh): the high score file, the sound
#                   writes, the game's own recording played back; pictures at given game
#                   frames of a recorded game against tests/ref/ (tests/frames.sh); and
#                   upstream's recorded games played back as upstream plays them (drf.sh)
#   make refs       new reference pictures (after a change meant to show: look at them)
#   make app        DIGGER.HZA: the app (APP.INF, the program, its data, its icon) for the
#                   Installer of Horizon 0.29 (sdk/docs/apps.md); make test-app installs
#                   it in the emulator and starts it from the Desktop's Programs menu
#   make clean
# HORIZON=DIR: a Horizon tree with a built card, 0.28 or later (a large program).

NAME      := digger
SDK       ?= ../../sdk
RUNMODE   := desktop
HZ_CODE   ?= large
SRCS      := $(wildcard src/*.c) $(wildcard horizon/*.c) horizon/hz_blit.s build/alpha_ok.c
# --needs: the program says what is missing and ends on a machine without it (sdk/docs/
# apps.md): Horizon 0.28 (a large program), Marga's scrolling (the split view: REV $0B), and
# about 1.2 MB of memory (19 banks: two framebuffers, the pictures, the tables, the code).
# Lau is not needed (without it the sound's clock is the frame counter); nor a joystick.
NEEDS     := horizon=0.28,sprites,mem=1280K
HCCFLAGS  += --needs $(NEEDS) --map --stack 4096 --heap 4096 -D_HORIZON -Dmain=digger_main -I src -I horizon -fsigned-char
SCRIPT    := tests/play.script
RUNFLAGS  += --file DIGGER.DAT:/APPS/DIGGER.DAT --seconds 150
TESTFLAGS := --log-sound --expect 'digger: paced frames'
TESTCHECK := sh tests/check.sh $(HORIZON)
include $(SDK)/c/c.mk

all: DIGGER.DAT

$(PRG): build/alpha_ok.c $(wildcard src/*.h horizon/*.h)

DIGGER.DAT build/alpha_ok.c build/DIGGER.ICN: tools/mkdata.py src/data/vgagrafx.c src/data/alpha.c src/data/title_gz.c
	@mkdir -p build
	$(PYTHON) tools/mkdata.py src/data -o DIGGER.DAT --c build/alpha_ok.c --icon build/DIGGER.ICN

# the app: build/app/DIGGER/ (what the archive holds) -> DIGGER.HZA. Not DIGGER.SCO or
# DIGGER.INI: the program makes them in its folder, and an update keeps them
app: DIGGER.HZA
DIGGER.HZA: $(PRG) DIGGER.DAT build/DIGGER.ICN app/APP.INF $(SDK)/tools/hzapp.py
	rm -rf build/app && mkdir -p build/app/DIGGER
	cp $(PRG) DIGGER.DAT build/DIGGER.ICN build/app/DIGGER/
	grep -v '^#' app/APP.INF > build/app/DIGGER/APP.INF
	$(PYTHON) $(SDK)/tools/hzapp.py pack build/app/DIGGER -o $@ --mtime 0

# the app in the emulator: the Desktop, DIGGER.HZA opened in Files, installed, Digger
# started from Programs > Games, its title (tests/app.script waits for it)
test-app: DIGGER.HZA $(CARD)
	sh tests/app.sh $(HORIZON)

run test: DIGGER.DAT

refs: $(PRG) DIGGER.DAT $(CARD)
	sh tests/frames.sh $(HORIZON) --update
.PHONY: refs app test-app

clean: cleandat
cleandat:
	rm -f DIGGER.DAT DIGGER.HZA
.PHONY: cleandat

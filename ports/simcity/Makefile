# Micropolis (ports/simcity): the city simulator from the original SimCity source
# (Micropolis, GPL-3, Electronic Arts 2008: engine/, our fork) on the Atari816.
#
#   make            MICROPOLIS.PRG (the game) and SIMTEST.PRG (the simulator alone)
#   make host       the simulator's twins on the PC: build/host16/simtest (the engine with
#                   the Atari816's 16-bit int, tools/host16.py) and build/host32/simtest
#                   (upstream's own types: int 32 bits)
#   make data       the game's files (build/card/): tiles, sprites, sounds, cities
#   make run        the game in the emulator (build/run/)
#   make test       the checks (tests/check.sh)
#   make app        MICROPOLIS.HZA, the installable app; make test-app installs it in
#                   the emulator from the Desktop and starts it
#   make test-layouts  make test's simulator checks with the program's layout shifted
#   make clean
# HORIZON=DIR: a Horizon tree with a built card (0.30).

SDK      ?= ../../sdk
HORIZON  ?= $(SDK)/../horizon
PYTHON   ?= python3
HCC      := $(PYTHON) $(SDK)/c/bin/hcc
CC_HOST  ?= cc
CARD     := $(HORIZON)/build/sd/SYSTEM/HORIZON.SYS

all: MICROPOL.PRG SIMTEST.PRG

ENG      := engine/src/sim
# upstream's files the port builds (engine/FORK.md: which and why)
ENGSRC   := g_ani rand s_alloc s_disast s_eval s_fileio s_gen s_init s_msg s_power s_scan \
            s_sim s_traf s_zone w_budget w_con w_eval w_graph w_sprite w_tool w_update w_util
ENGHDR   := $(wildcard $(ENG)/headers/*.h)
PORTHDR  := src/port.h src/proto.h src/hooks.h
STRI     := $(wildcard engine/res/stri.*)

# ---------------------------------------------------------------- the PC's twins
# both: floats as the Atari816's (single precision, constants too, no fused multiply-add)
HOSTFLAGS := -std=gnu99 -O1 -g -DMICROPOLIS_PORT -fsingle-precision-constant \
             -ffp-contract=off -fno-strict-aliasing -fwrapv -w

build/stri.c: tools/mkstri.py $(STRI)
	@mkdir -p build
	$(PYTHON) tools/mkstri.py $@ $(STRI)

host: build/host16/simtest build/host32/simtest

# host32: upstream's sources as they are (int 32 bits, long 32 bits by port.h, char signed)
build/host32/simtest: $(ENGSRC:%=$(ENG)/%.c) src/hooks.c src/simtest.c build/stri.c \
                      $(ENGHDR) $(PORTHDR)
	@mkdir -p build/host32
	$(CC_HOST) $(HOSTFLAGS) -Isrc -I$(ENG)/headers -o $@ $(ENGSRC:%=$(ENG)/%.c) \
	  src/hooks.c src/simtest.c build/stri.c

# host16: every file rewritten (int -> short), plain char unsigned: the Atari816's types
H16      := build/host16/s
H16SRC   := $(ENGSRC:%=$(H16)/%.c) $(H16)/hooks.c $(H16)/simtest.c
$(H16)/.headers: $(ENGHDR) $(PORTHDR) tools/host16.py
	@mkdir -p $(H16)/h
	@for f in $(ENGHDR) $(PORTHDR); do $(PYTHON) tools/host16.py $$f $(H16)/h/$$(basename $$f) $$f || exit 1; done
	touch $@
$(H16)/%.c: $(ENG)/%.c tools/host16.py
	@mkdir -p $(H16)
	$(PYTHON) tools/host16.py $< $@ $<
$(H16)/%.c: src/%.c tools/host16.py
	@mkdir -p $(H16)
	$(PYTHON) tools/host16.py $< $@ $<
build/host16/simtest: $(H16SRC) $(H16)/.headers build/stri.c
	$(CC_HOST) $(HOSTFLAGS) -funsigned-char -I$(H16)/h -o $@ $(H16SRC) build/stri.c

# ---------------------------------------------------------------- the Atari816
# the large code model (the engine is 9,000 lines), the maps in far memory (port.h)
CFLAGS816 := --code large -DMICROPOLIS_PORT -Isrc -I$(ENG)/headers -Wall -Wno-unused-variable \
             -Wno-unused-label -Wno-parentheses
NEEDS     := horizon=0.30,sprites,blitter,mem=2048K
LFLAGS816 := --code large --map --stack 5120 --heap 5120
DEPS816   := $(ENGHDR) $(PORTHDR)

build/816/%.o: $(ENG)/%.c $(DEPS816)
	@mkdir -p build/816
	$(HCC) $(CFLAGS816) -c -o $@ $<
build/816/%.o: src/%.c $(DEPS816)
	@mkdir -p build/816
	$(HCC) $(CFLAGS816) -c -o $@ $<
build/816/%.o: src/%.s
	@mkdir -p build/816
	$(HCC) $(CFLAGS816) -c -o $@ $<
build/816/stri.o: build/stri.c
	@mkdir -p build/816
	$(HCC) $(CFLAGS816) -c -o $@ $<

ENGOBJ   := $(ENGSRC:%=build/816/%.o) build/816/hooks.o build/816/fast.o build/816/stri.o

SIMTEST.PRG: $(ENGOBJ) build/816/simtest.o
	$(HCC) $(LFLAGS816) --needs horizon=0.30,mem=256K -o $@ $^

# the game
GAMESRC  := game view panel dialogs data
GAMEOBJ  := $(GAMESRC:%=build/816/%.o)
build/816/game.o build/816/view.o build/816/panel.o build/816/dialogs.o build/816/data.o: src/ui.h
MICROPOL.PRG: $(ENGOBJ) $(GAMEOBJ)
	$(HCC) $(LFLAGS816) --game --needs $(NEEDS) -o $@ $^

# ---------------------------------------------------------------- the data
# build/card: what the app's folder holds besides the program (and run816 puts on the card)
CITIES   := $(wildcard engine/cities/*.cty)
data: build/card/MICROPOL.GFX
build/card/MICROPOL.GFX: tools/mkdata.py tools/mkcard.sh $(wildcard engine/images/*.xpm) \
                         $(CITIES) $(wildcard engine/res/snro.*)
	$(PYTHON) tools/mkdata.py engine build/card
	sh tools/mkcard.sh engine build/card

# ---------------------------------------------------------------- the app
# build/app/MICROPOLIS/: the program, its files, APP.INF, the icon -> MICROPOLIS.HZA.
# The player's cities (*.CTY in the folder) are made by the game, never in the archive.
build/MICROPOL.ICN: tools/mkdata.py build/card/MICROPOL.GFX
	$(PYTHON) tools/mkdata.py engine build/icon --icon build/icon.png
	$(PYTHON) $(SDK)/tools/hzapp.py icon build/icon.png $@ --preview build/icon-preview.png

app: MICROPOLIS.HZA
MICROPOLIS.HZA: MICROPOL.PRG build/card/MICROPOL.GFX build/MICROPOL.ICN app/APP.INF \
                $(SDK)/tools/hzapp.py
	sh tools/mkapp.sh build/app/MICROPOLIS
	$(PYTHON) $(SDK)/tools/hzapp.py pack build/app/MICROPOLIS -o $@ --mtime 0

# ---------------------------------------------------------------- the tests
$(CARD):
	$(MAKE) -C $(HORIZON)

run: MICROPOL.PRG data $(CARD)
	sh tests/run.sh $(HORIZON) build/run $(RUNFLAGS)

test: MICROPOL.PRG SIMTEST.PRG data host $(CARD)
	sh tests/check.sh $(HORIZON)

# the simulator's equality only, longer (TICKS=n)
TICKS ?= 20000
test-long: SIMTEST.PRG host $(CARD)
	sh tests/simeq.sh $(HORIZON) $(TICKS)

test-app: MICROPOLIS.HZA $(CARD)
	sh tests/app.sh $(HORIZON)

# new picture checksums (tests/*.md5) from the last make test: look at the pictures first
refs:
	sh tests/check.sh $(HORIZON) --refs

.SECONDARY:

clean:
	rm -rf build SIMTEST.PRG SIMTEST.map SIMTEST.lbl MICROPOL.PRG MICROPOL.map \
	  MICROPOL.lbl MICROPOLIS.HZA

.PHONY: all host data run test test-long app test-app refs clean

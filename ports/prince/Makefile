# Prince of Persia (ports/prince): the DOS game, from SDLPoP (GPL-3), on Horizon.
#
#   make data       the game's data: tools/getdata.sh fetches SDLPoP at a pinned commit
#                   (or takes yours: make data SDLPOP=DIR); tools/mkdata.py converts it
#                   into data/card/ (POP.GFX, POP.MSK, POP.DAT, POP.SND)
#   make            PRINCE.PRG
#   make run        the game in the emulator (build/run/)
#   make test       the checks (tests/check.sh)
#   make test-long  every level against upstream on the PC (tests/levels.sh; make host first)
#   make app        PRINCE.HZA, the installable app; make test-app installs it in the
#                   emulator and starts it
#   make host       the reference: upstream SDLPoP built on this PC (host/; needs SDL2)
#   make test-layouts  make test's checks with the program's layout shifted (PAD=n: an
#                   object of n bytes of constants, data, bss and code linked first,
#                   tests/layouts.sh): a fault that depends on where things lie shows
#   make clean
# HORIZON=DIR: a Horizon tree with a built card (0.30).
#
# Rebuilds follow the files' contents, not only their times: every source, the headers
# and the SDK's compiler and libraries have a checksum in build/sum/ that is renewed only
# when the content changed (a copy that kept old times, rsync -a or an unpacked archive,
# still rebuilds what changed).

SDK      ?= ../../sdk
HORIZON  ?= $(SDK)/../horizon
PYTHON   ?= python3
HCC      := $(PYTHON) $(SDK)/c/bin/hcc
RUN816   := $(PYTHON) $(SDK)/tools/run816.py --horizon $(HORIZON)
CARD     := $(HORIZON)/build/sd/SYSTEM/HORIZON.SYS
SDLPOP   ?=
CC_HOST  ?= cc

# upstream's files (src/); seg009.c (SDL), main.c, menu.c, lighting.c, screenshot.c,
# midi.c, opl3.c and stb_vorbis.c are not built: horizon/ has their part
GAMESRC  := data seg000 seg001 seg002 seg003 seg004 seg005 seg006 seg007 seg008 seqtbl \
            replay options
PLATSRC  := hz_main hz_seg009 hz_video hz_data hz_sound hz_sys hz_ref
NEEDS    := horizon=0.30,blitter,mem=3072K
CFLAGS   := --code large -D_HORIZON -I src -I horizon -I horizon/compat -include horizon/hz_heap.h \
            -fsigned-char -Wall
OBJS     := $(GAMESRC:%=build/o/%.o) $(PLATSRC:%=build/o/%.o)
LFLAGS   := --code large --game --map --stack 4096 --heap 12288 --needs $(NEEDS)
HEADERS  := $(wildcard src/*.h horizon/*.h horizon/compat/*/*.h)
# the SDK's compiler, C library and game library: a change rebuilds everything
TOOLSRC  := $(wildcard $(SDK)/c/bin/hcc $(SDK)/c/cc816/cc816/*.py $(SDK)/c/tools/*.py \
            $(SDK)/c/lib/*.[chs] $(SDK)/c/rt/*.[chs] $(SDK)/c/include/*.h $(SDK)/c/include/*/*.h \
            $(SDK)/c/game/*.[chs] $(SDK)/c/game/*.py)
# PAD=n (tests only): build/o/padN.o linked first, everything after it n bytes on
PAD      ?= 0
PADOBJ   := $(if $(filter-out 0,$(PAD)),build/o/pad$(PAD).o)

all: PRINCE.PRG

# build/sum/FILE.sum: FILE's checksum, rewritten (new time) only when it changed
build/sum/%.sum: % FORCE
	@mkdir -p $(dir $@)
	@md5sum $< > $@.new; if cmp -s $@.new $@; then rm $@.new; else mv $@.new $@; fi
build/sum/headers.sum: FORCE
	@mkdir -p build/sum
	@md5sum $(HEADERS) > $@.new; if cmp -s $@.new $@; then rm $@.new; else mv $@.new $@; fi
build/sum/sdk.sum: FORCE
	@mkdir -p build/sum
	@md5sum $(TOOLSRC) > $@.new; if cmp -s $@.new $@; then rm $@.new; else mv $@.new $@; fi
build/sum/pad.sum: FORCE
	@mkdir -p build/sum
	@echo $(PAD) > $@.new; if cmp -s $@.new $@; then rm $@.new; else mv $@.new $@; fi
DEPS     := build/sum/headers.sum build/sum/sdk.sum

build/o/%.o: src/%.c build/sum/src/%.c.sum $(DEPS)
	@mkdir -p build/o
	$(HCC) $(CFLAGS) -c -o $@ $<

build/o/%.o: horizon/%.c build/sum/horizon/%.c.sum $(DEPS)
	@mkdir -p build/o
	$(HCC) $(CFLAGS) -c -o $@ $<

build/o/pad%.o: tools/mkpad.py build/sum/sdk.sum
	@mkdir -p build/o
	$(PYTHON) tools/mkpad.py $* build/pad$*.c
	$(HCC) $(CFLAGS) -c -o $@ build/pad$*.c

PRINCE.PRG: $(PADOBJ) $(OBJS) build/sum/pad.sum build/sum/sdk.sum
	$(HCC) $(LFLAGS) -o $@ $(PADOBJ) $(OBJS)

.SECONDARY:
FORCE:

# ---------------------------------------------------------------- the data

data: data/card/POP.GFX
build/midi2imf: tools/midi2imf.c
	@mkdir -p build
	$(CC_HOST) -O2 -o $@ $< -lm
data/card/POP.GFX: tools/mkdata.py build/midi2imf
	@test -f data/sdlpop/data/KID/res400.pal || sh tools/getdata.sh $(SDLPOP)
	$(PYTHON) tools/mkdata.py data/sdlpop/data data/card --midi2imf build/midi2imf

host:
	@test -f data/sdlpop/data/KID/res400.pal || sh tools/getdata.sh $(SDLPOP)
	$(MAKE) -C host
	printf '[General]\nenable_info_screen = false\n' > data/sdlpop/SDLPoP.ini

# ---------------------------------------------------------------- the app
# build/app/PRINCE/ (what the archive holds) -> PRINCE.HZA. Saves (PRINCE.SAV, PRINCE.HOF,
# QUICKSAVE.SAV) are made by the game in its folder and are never in the archive.
build/PRINCE.ICN: tools/mkicon.py data/card/POP.GFX
	$(PYTHON) tools/mkicon.py data/sdlpop/data build/icon.png
	$(PYTHON) $(SDK)/tools/hzapp.py icon build/icon.png $@ --preview build/icon-preview.png

app: PRINCE.HZA
PRINCE.HZA: PRINCE.PRG data/card/POP.GFX build/PRINCE.ICN app/APP.INF $(SDK)/tools/hzapp.py
	rm -rf build/app && mkdir -p build/app/PRINCE
	cp PRINCE.PRG data/card/POP.* build/PRINCE.ICN build/app/PRINCE/
	grep -v '^#' app/APP.INF > build/app/PRINCE/APP.INF
	$(PYTHON) $(SDK)/tools/hzapp.py pack build/app/PRINCE -o $@ --mtime 0

# the app in the emulator: PRINCE.HZA opened in Files, installed, started from
# Programs > Games, played into level 1, installed again (tests/app.sh)
test-app: PRINCE.HZA $(CARD)
	sh tests/app.sh $(HORIZON)

# ---------------------------------------------------------------- the emulator

FILES = $(foreach f,$(wildcard data/card/*),--file $(f):/APPS/PRINCE/$(notdir $(f)))
RUNFLAGS ?=

$(CARD):
	$(MAKE) -C $(HORIZON)

run: PRINCE.PRG data $(CARD)
	$(RUN816) PRINCE.PRG --dest /APPS/PRINCE/PRINCE.PRG --mode desktop $(FILES) \
	  --out build/run $(RUNFLAGS)

test: PRINCE.PRG data $(CARD)
	sh tests/check.sh $(HORIZON)

# every level against upstream on the PC (needs make host: the level replays are recorded by
# it into build/levels, tests/mklevels.sh): each level's start, the walk through all of
# them with the cheat keys (tests/levels.sh)
test-long: PRINCE.PRG data $(CARD)
	sh tests/levels.sh $(HORIZON)

# make test's checks with the layout shifted: PAD=0 and LAYOUTS (each builds, runs check.sh)
LAYOUTS ?= 0 1 37 250 500
test-layouts: data $(CARD)
	sh tests/layouts.sh $(HORIZON) $(LAYOUTS)

# the replays' pictures of the last make test against upstream's on the PC (make host)
check-host:
	sh tests/hostframes.sh

# new reference results from upstream on the PC (tests/ref/*.ref), new picture checksums
refs-host:
	sh tests/mkref.sh
refs: PRINCE.PRG data $(CARD)
	sh tests/check.sh $(HORIZON) --refs

clean:
	rm -rf build PRINCE.PRG PRINCE.map PRINCE.lbl PRINCE.HZA

.PHONY: all data host run test test-long test-layouts check-host refs-host refs app test-app clean FORCE

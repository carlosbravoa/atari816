# Xargon (ports/xargon): Allen Pilgrim's Xargon (Epic MegaGames, 1993) on Horizon.
#
#   make data       the game's files (tools/getdata.sh: downloaded, or from your copy:
#                   make data GAME=DIR) converted for the port (tools/mkdata.py): data/card/
#   make            XARGON1.PRG, XARGON2.PRG, XARGON3.PRG: the three episodes (one program
#                   each, as upstream's XRFILE01-03.EXE)
#   make run        episode 1 in the emulator with the scripted game (tests/play.script,
#                   its pictures at tests/play.shots): build/run/
#   make test       the checks (tests/check.sh): the scripted game, the saved game, the
#                   sound, the recorded demo, the pictures of both (taken at game frames)
#                   against tests/play.md5 and tests/demo.md5, the heap (no leak, room for
#                   the help on every board: tests/heapcheck.py, tests/help.script)
#   make refs       new reference pictures (tests/play.md5, tests/demo.md5, the pictures
#                   in tests/ref/: after a change meant to show; look at them first)
#   make clean
# HORIZON=DIR: a Horizon tree with a built card, 0.28 or later (a large program).
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
GAME     ?=

# upstream's files (src/); config.c, graphics.c's assembly, keyboard.c, music.c and
# shapeman.c are the platform's (horizon/); routines.c, x_editor.c and _xargon.c are not
# part of the released game
GAMESRC  := xargon x_obj x_obj2 x_obj3 x_objman x_player x_info windows gamectrl graphics
PLATSRC  := hz_main hz_vga hz_frame hz_dos hz_kbd hz_snd hz_cfg hz_shm
CFLAGS   := --code large -D_HORIZON -I src -I horizon -I horizon/compat \
            -include horizon/xcompat.h -include horizon/hz_heap.h -fsigned-char
OBJS     := $(GAMESRC:%=build/o/%.o) $(PLATSRC:%=build/o/%.o) build/o/hz_blit.o
LFLAGS   := --code large --game --map --stack 4096 --heap 7168
HEADERS  := $(wildcard src/*.h src/*.def horizon/*.h horizon/compat/*.h)
# the SDK's compiler, C library and game library: a change rebuilds everything
TOOLSRC  := $(wildcard $(SDK)/c/bin/hcc $(SDK)/c/cc816/cc816/*.py $(SDK)/c/tools/*.py \
            $(SDK)/c/lib/*.[chs] $(SDK)/c/rt/*.[chs] $(SDK)/c/include/*.h $(SDK)/c/include/*/*.h \
            $(SDK)/c/game/*.[chs] $(SDK)/c/game/*.py)

all: XARGON1.PRG XARGON2.PRG XARGON3.PRG

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
DEPS     := build/sum/headers.sum build/sum/sdk.sum

build/o/%.o: src/%.c build/sum/src/%.c.sum $(DEPS)
	@mkdir -p build/o
	$(HCC) $(CFLAGS) -c -o $@ $<

build/o/%.o: horizon/%.c build/sum/horizon/%.c.sum $(DEPS)
	@mkdir -p build/o
	$(HCC) $(CFLAGS) -c -o $@ $<

build/o/hz_blit.o: horizon/hz_blit.s build/sum/horizon/hz_blit.s.sum build/sum/sdk.sum
	@mkdir -p build/o
	$(HCC) --code large -c -o $@ $<

XARGON%.PRG: $(OBJS) build/o/x_vol%.o build/sum/sdk.sum
	$(HCC) $(LFLAGS) -o $@ $(OBJS) build/o/x_vol$*.o

.SECONDARY:
FORCE:

# ---------------------------------------------------------------- the data

data: data/card/XSHAPES.XR1
data/card/XSHAPES.XR1: tools/mkdata.py
	@test -f data/orig/GRAPHICS.XR1 -o -f data/orig/graphics.xr1 || sh tools/getdata.sh $(GAME)
	$(PYTHON) tools/mkdata.py data/orig -o data/card

# ---------------------------------------------------------------- the emulator

# the card: the program and its data in /GAMES/XARGON/
FILES = $(foreach f,$(wildcard data/card/*),--file $(f):/GAMES/XARGON/$(notdir $(f)))
RUNFLAGS ?=

$(CARD):
	$(MAKE) -C $(HORIZON)

run: XARGON1.PRG data $(CARD)
	$(RUN816) XARGON1.PRG --dest /GAMES/XARGON/XARGON1.PRG --mode shell \
	  --args /SHOTS:PLAY.SHT $(FILES) --file tests/play.shots:/GAMES/XARGON/PLAY.SHT \
	  --script tests/play.script --shot-on "xargon: shot" --out build/run $(RUNFLAGS)

test: XARGON1.PRG data $(CARD)
	sh tests/check.sh $(HORIZON)

refs: XARGON1.PRG data $(CARD)
	sh tests/check.sh $(HORIZON) --refs

clean:
	rm -rf build XARGON*.PRG XARGON*.PRX XARGON*.map XARGON*.lbl

.PHONY: all data run test refs clean FORCE

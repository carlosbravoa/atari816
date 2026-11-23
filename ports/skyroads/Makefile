# SkyRoads (ports/skyroads): Bluemoon's SkyRoads (1993) on Horizon, from the C translation
# of SDL-skyroads (C++17, github.com/carlosbravoa/SDL-skyroads).
#
#   make data       the game's files (tools/getdata.sh: downloaded, or your copy: make data
#                   GAME=DIR), their LZ streams decoded (srtool predecode): data/card/
#   make            SKYROADS.PRG
#   make host       the C translation on the PC (build/host/srtool; SDL: make -C host sdl)
#   make check      the demo's 1,708 frames drawn on the Atari816 (emulator) against the C
#                   translation's on the PC, by checksum (tests/framesum.py)
#   make bench      the road-pass experiment (PORTING-NOTES.md): each demo frame's
#                   simulation and drawing timed, build/bench/console.txt
#   make paced      the demo at the game's 36 ticks a second: frames drawn, build/paced/
#   make clean
# HORIZON=DIR: a Horizon tree with a built card (0.29).

SDK      ?= ../../sdk
HORIZON  ?= $(SDK)/../horizon
PYTHON   ?= python3
HCC      := $(PYTHON) $(SDK)/c/bin/hcc
RUN816   := $(PYTHON) $(SDK)/tools/run816.py --horizon $(HORIZON)
CARD     := $(HORIZON)/build/sd/SYSTEM/HORIZON.SYS
GAME     ?=

GAMESRC  := data/byteio data/compression data/image data/roads data/level data/trekdat \
            data/demo data/dashboard data/muzax data/config data/sound core/gameplay \
            core/app core/dos_render_tables core/dos_font renderer/renderer
PLATSRC  := hz_main hz_plat hz_video
CFLAGS   := --code large -I src -I horizon
OBJS     := $(GAMESRC:%=build/o/%.o) $(PLATSRC:%=build/o/%.o) build/o/hz_spans.o build/o/hz_road.o build/o/hz_probe.o
LFLAGS   := --code large --game --map --stack 4096 --heap 6144
HEADERS  := $(wildcard src/*.h src/*/*.h horizon/*.h)

all: SKYROADS.PRG

build/o/%.o: src/%.c $(HEADERS)
	@mkdir -p $(dir $@)
	$(HCC) $(CFLAGS) -c -o $@ $<

build/o/%.o: horizon/%.c $(HEADERS)
	@mkdir -p build/o
	$(HCC) $(CFLAGS) -c -o $@ $<

build/o/%.o: horizon/%.s
	@mkdir -p build/o
	$(HCC) --code large -c -o $@ $<

SKYROADS.PRG: $(OBJS)
	$(HCC) $(LFLAGS) -o $@ $^

host:
	$(MAKE) -C host

# ---------------------------------------------------------------- the data

data: data/card/ROADS.DEC
data/card/ROADS.DEC: host
	@test -f data/orig/ROADS.LZS || sh tools/getdata.sh $(GAME)
	mkdir -p data/card
	cp data/orig/*.LZS data/orig/*.DAT data/orig/*.SND data/orig/DEMO.REC data/card/
	build/host/srtool predecode data/orig data/card

# ---------------------------------------------------------------- the emulator

FILES = $(foreach f,$(wildcard data/card/*),--file $(f):/APPS/SKYROADS/$(notdir $(f)))

$(CARD):
	$(MAKE) -C $(HORIZON)

bench: SKYROADS.PRG data $(CARD)
	$(RUN816) SKYROADS.PRG --dest /APPS/SKYROADS/SKYROADS.PRG --mode shell --args /BENCH \
	  $(FILES) --seconds 900 --out build/bench --expect "skyroads: bench"

paced: SKYROADS.PRG data $(CARD)
	$(RUN816) SKYROADS.PRG --dest /APPS/SKYROADS/SKYROADS.PRG --mode shell --args "/PACED 0" \
	  $(FILES) --seconds 200 --out build/paced --expect "skyroads: paced demo"
	grep "skyroads: paced" build/paced/console.txt

check: SKYROADS.PRG data $(CARD) host
	@mkdir -p build/check
	build/host/srtool demo-frames data/orig build/check/host.raw incr
	$(RUN816) SKYROADS.PRG --dest /APPS/SKYROADS/SKYROADS.PRG --mode shell --args /CHECK \
	  $(FILES) --seconds 700 --out build/check --expect "skyroads: check"
	$(PYTHON) tests/framesum.py --compare build/check/host.raw build/check/console.txt
	rm -f build/check/host.raw

clean:
	rm -rf build SKYROADS.PRG SKYROADS.map SKYROADS.lbl SKYROADS.HZA

.PHONY: all host data bench paced check clean

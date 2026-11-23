# SkyRoads (ports/skyroads): Bluemoon's SkyRoads (1993) on Horizon, from the C translation
# of SDL-skyroads (C++17, github.com/carlosbravoa/SDL-skyroads).
#
#   make data       the game's files (tools/getdata.sh: downloaded, or your copy: make data
#                   GAME=DIR), their LZ streams decoded (srtool predecode), and SKYPREP.DAT
#                   (srtool prepare: TREKDAT's spans, the ship's sprites): data/card/
#   make            SKYROADS.PRG
#   make host       the C translation on the PC (build/host/srtool, build/host/srsimcheck;
#                   SDL: make -C host sdl)
#   make check      the demo's 1,708 frames drawn on the Atari816 (emulator) against the C
#                   translation's on the PC, by checksum (tests/framesum.py), and the demo's
#                   whole state after every tick (srtool demo-state)
#   make bench      each demo tick's simulation and each frame's drawing timed (hz_uptime_us),
#                   build/bench/console.txt
#   make sim        the demo's ticks alone, timed
#   make beat       the demo on a steady beat (RATE=36, 24, 18; 0 adaptive): late frames
#   make paced      the demo at the game's 36 ticks a second: frames drawn, build/paced/
#   make probecheck, movecheck   the assembly probe, move_to and scan against the C
#   make clean
# HORIZON=DIR: a Horizon tree with a built card (0.30: the road by fill_runs; 0.29: by the CPU).

SDK      ?= ../../sdk
HORIZON  ?= $(SDK)/../horizon
PYTHON   ?= python3
HCC      := $(PYTHON) $(SDK)/c/bin/hcc
RUN816   := $(PYTHON) $(SDK)/tools/run816.py --horizon $(HORIZON) $(RUNFLAGS)
CARD     := $(HORIZON)/build/sd/SYSTEM/HORIZON.SYS
GAME     ?=

GAMESRC  := data/byteio data/compression data/image data/roads data/level data/trekdat \
            data/demo data/dashboard data/muzax data/config data/sound core/gameplay \
            core/app core/dos_render_tables core/dos_font renderer/renderer
PLATSRC  := hz_main hz_plat hz_video hz_sim
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

data: data/card/ROADS.DEC data/card/SKYPREP.DAT
data/card/SKYPREP.DAT: data/card/ROADS.DEC
	build/host/srtool prepare data/orig data/card/SKYPREP.DAT
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
	  $(FILES) --seconds 300 --out build/bench --expect "skyroads: bench"
	grep "skyroads: " build/bench/console.txt

# the simulation alone (profile it: make sim RUNFLAGS="--prof build/sim.prof --prof-from S --prof-to S")
sim: SKYROADS.PRG data $(CARD)
	$(RUN816) SKYROADS.PRG --dest /APPS/SKYROADS/SKYROADS.PRG --mode shell --args /SIM \
	  $(FILES) --seconds 200 --out build/sim --expect "skyroads: sim "
	grep "skyroads: " build/sim/console.txt

paced: SKYROADS.PRG data $(CARD)
	$(RUN816) SKYROADS.PRG --dest /APPS/SKYROADS/SKYROADS.PRG --mode shell --args "/PACED 0" \
	  $(FILES) --seconds 200 --out build/paced --expect "skyroads: paced demo"
	grep "skyroads: paced" build/paced/console.txt

# (round 2) the demo on a steady beat: RATE=36, 24, 18, or 0 (adaptive: the default)
RATE ?= 0
beat: SKYROADS.PRG data $(CARD)
	$(RUN816) SKYROADS.PRG --dest /APPS/SKYROADS/SKYROADS.PRG --mode shell --args "/BEAT $(RATE)" \
	  $(FILES) --seconds 200 --out build/beat --expect "skyroads: beat demo"
	grep "skyroads: beat" build/beat/console.txt

# the assembly probe against the C, at random points of every road
probecheck: SKYROADS.PRG data $(CARD)
	$(RUN816) SKYROADS.PRG --dest /APPS/SKYROADS/SKYROADS.PRG --mode shell --args /PROBECHECK \
	  $(FILES) --seconds 300 --out build/probecheck --expect "skyroads: probecheck: 0 of"
	grep "skyroads: probecheck" build/probecheck/console.txt

# the assembly move_to16 and bounce scan against gameplay.c's C
movecheck: SKYROADS.PRG data $(CARD)
	$(RUN816) SKYROADS.PRG --dest /APPS/SKYROADS/SKYROADS.PRG --mode shell --args /MOVECHECK \
	  $(FILES) --seconds 300 --out build/movecheck --expect "skyroads: movecheck: 0 of"
	grep "skyroads: movecheck" build/movecheck/console.txt

check: SKYROADS.PRG data $(CARD) host
	@mkdir -p build/check
	build/host/srtool demo-frames data/orig build/check/host.raw incr
	$(RUN816) SKYROADS.PRG --dest /APPS/SKYROADS/SKYROADS.PRG --mode shell --args /CHECK \
	  $(FILES) --seconds 700 --out build/check --expect "skyroads: check"
	$(PYTHON) tests/framesum.py --compare build/check/host.raw build/check/console.txt
	rm -f build/check/host.raw
	build/host/srtool demo-state data/orig > build/check/host-state.txt
	grep '^s ' build/check/console.txt | diff -q - build/check/host-state.txt
	@echo "check: the demo's state identical for all $$(wc -l < build/check/host-state.txt) ticks"

clean:
	rm -rf build SKYROADS.PRG SKYROADS.map SKYROADS.lbl SKYROADS.HZA

.PHONY: all host data bench sim paced beat probecheck movecheck check clean

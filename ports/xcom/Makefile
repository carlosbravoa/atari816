# XCOM-XT (ports/xcom): X-COM: UFO Defense on an XT engine (GPL-3), on Horizon.
# README.md, PORTING-NOTES.md.
#
#   make src        upstream/ (tools/getsrc.sh, pinned commit) + patches/src-*.patch -> build/src
#   make data GAME=DIR   your X-COM (DOS 1.4 / GOG) -> data/packs (upstream's XCOMCONV)
#   make host       build/host/xcomhost: the engine on Linux (headless, the reference)
#   make host-run ARGS="NOINTRO ..."   run it on data/packs: pictures in build/host/shots
#   make check-host  the reference runs (tests/runs) against tests/runs.md5
#   make            XCOM.PRG (hcc --code large --data far): the engine on the Atari816
#   make test       tests/check.sh: every run of tests/runs on the host and on the Atari816
#                   in the emulator, compared (LOG, pictures, saves)
#   make run ARGS="..."  XCOM.PRG in the emulator with the packs, shell mode (build/run)
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
CC_HOST  ?= cc
GAME     ?=

# upstream files replaced by the port (plat/): timer.c (PIT, INT 08h), vgainit.c and
# vgageo.c (self-modifying hooks into vgaasm.asm / vgxasm.asm copied to the heap)
REPLACED := timer vgainit vgageo
UPSRC     = $(filter-out $(REPLACED:%=build/src/%.c),$(wildcard build/src/*.c))
# plat/ files of the battle view and the game's assembly in C (plat/asm.c keeps a stub
# of each until its file is on: PLAT_ON="vgabat rend losfan voxrun way")
PLAT_ON  ?= vgabat rend losfan voxrun way
PLAT_ALL := vgabat rend losfan voxrun way
PLAT_MAC := vgabat=VGABAT rend=REND losfan=LOS voxrun=VOX way=WAY
PLATSRC  := $(filter-out $(addprefix plat/,$(addsuffix .c,$(filter-out $(PLAT_ON),$(PLAT_ALL)))),$(wildcard plat/*.c))
PLATDEFS := $(foreach f,$(PLAT_ON),$(foreach m,$(PLAT_MAC),$(if $(filter $f=%,$m),-DXD_HAVE_$(patsubst $f=%,%,$m))))
HEADERS   = $(wildcard build/src/*.h compat/*.h plat/*.h horizon/*.h)
# the SDK's compiler, C library and game library: a change rebuilds the Atari816's objects
TOOLSRC  := $(wildcard $(SDK)/c/bin/hcc $(SDK)/c/cc816/cc816/*.py $(SDK)/c/tools/*.py \
            $(SDK)/c/lib/*.[chs] $(SDK)/c/rt/*.[chs] $(SDK)/c/include/*.h $(SDK)/c/include/*/*.h \
            $(SDK)/c/game/*.[chs] $(SDK)/c/game/*.py)

all: XCOM.PRG

# build/sum/FILE.sum: FILE's checksum, rewritten (new time) only when it changed
build/sum/%.sum: % FORCE
	@mkdir -p $(dir $@)
	@md5sum $< > $@.new; if cmp -s $@.new $@; then rm $@.new; else mv $@.new $@; fi
build/sum/headers.sum: FORCE build/src/.stamp
	@mkdir -p build/sum
	@md5sum $(HEADERS) > $@.new; if cmp -s $@.new $@; then rm $@.new; else mv $@.new $@; fi
build/sum/sdk.sum: FORCE
	@mkdir -p build/sum
	@md5sum $(TOOLSRC) > $@.new; if cmp -s $@.new $@; then rm $@.new; else mv $@.new $@; fi
build/sum/patches.sum: FORCE
	@mkdir -p build/sum
	@cat upstream/COMMIT $(sort $(wildcard patches/src-*.patch)) 2>/dev/null | md5sum > $@.new; \
	  if cmp -s $@.new $@; then rm $@.new; else mv $@.new $@; fi

# ---------------------------------------------------------------- upstream + patches
src: build/src/.stamp
build/src/.stamp: build/sum/patches.sum
	@test -f upstream/COMMIT || sh tools/getsrc.sh
	rm -rf build/src && mkdir -p build && cp -r upstream/src build/src
	for p in $(sort $(wildcard patches/src-*.patch)); do patch -s -p1 -d build < $$p || exit 1; done
	touch $@

# ---------------------------------------------------------------- the data
data: data/packs/PACKS.VER
data/packs/PACKS.VER:
	@test -n "$(GAME)" || { echo "make data GAME=/path/to/your/X-COM (see README.md)"; exit 1; }
	sh tools/getdata.sh "$(GAME)" --skip-check

# ---------------------------------------------------------------- host
# The host compiles copies of the engine's files with DOS's 16-bit int (tools/host16.py:
# int -> short, unsigned -> unsigned short; long is 32 bits by xcompat.h; structures
# packed as cc816 packs them), so that its arithmetic, LOGs and files are the DOS
# program's: build/host/s16/{src,plat,compat,host} mirror build/src, plat, compat, host.
S16       := build/host/s16
HOST16    := $(PYTHON) tools/host16.py
HOSTWARN  ?= -w
HOSTFLAGS := -std=gnu99 -O1 -g -fno-strict-aliasing -funsigned-char $(HOSTWARN) -I$(S16)/compat -I$(S16)/plat \
             -I$(S16)/src -include xcompat.h $(PLATDEFS)
HOSTHDRS   = $(wildcard build/src/*.h compat/*.h plat/*.h)
host: build/host/xcomhost
# every header, rewritten (a copy that came out the same keeps its time); a source is
# rewritten when its content changed (its checksum, build/sum)
$(S16)/.headers: build/sum/headers.sum build/sum/tools/host16.py.sum
	@mkdir -p $(S16)/src $(S16)/plat $(S16)/compat $(S16)/host
	@for f in $(HOSTHDRS); do $(HOST16) $$f $(S16)/$${f#build/} $$f || exit 1; done
	touch $@
$(S16)/src/%.c: build/sum/build/src/%.c.sum build/sum/tools/host16.py.sum
	@mkdir -p $(S16)/src
	$(HOST16) build/src/$*.c $@ build/src/$*.c && touch $@
$(S16)/plat/%.c: build/sum/plat/%.c.sum build/sum/tools/host16.py.sum
	@mkdir -p $(S16)/plat
	$(HOST16) plat/$*.c $@ plat/$*.c && touch $@
$(S16)/host/%.c: build/sum/host/%.c.sum build/sum/tools/host16.py.sum
	@mkdir -p $(S16)/host
	$(HOST16) host/$*.c $@ host/$*.c && touch $@
build/host/o/%.o: $(S16)/src/%.c $(S16)/.headers
	@mkdir -p build/host/o
	$(CC_HOST) $(HOSTFLAGS) $(if $(filter main,$*),-Dmain=xcom_main) -c -o $@ $<
build/host/p/%.o: $(S16)/plat/%.c $(S16)/.headers
	@mkdir -p build/host/p
	$(CC_HOST) $(HOSTFLAGS) -c -o $@ $<
build/host/h/%.o: $(S16)/host/%.c $(S16)/.headers
	@mkdir -p build/host/h
	$(CC_HOST) $(HOSTFLAGS) -c -o $@ $<
build/host/xcomhost: build/src/.stamp FORCE
	$(MAKE) build/host/xcomhost.real
	cp build/host/xcomhost.real $@
build/host/xcomhost.real: $(patsubst build/src/%.c,build/host/o/%.o,$(UPSRC)) \
                          $(patsubst plat/%.c,build/host/p/%.o,$(PLATSRC)) \
                          $(patsubst host/%.c,build/host/h/%.o,$(wildcard host/*.c))
	$(CC_HOST) -o $@ $^
check-host: build/host/xcomhost
	sh tests/host.sh
refs-host: build/host/xcomhost
	sh tests/host.sh --refs
host-run: build/host/xcomhost
	rm -rf build/host/shots && mkdir -p build/host/shots
	build/host/xcomhost -C data/packs -o build/host/shots $(ARGS)

# ---------------------------------------------------------------- Atari816
# the far data model (hcc --data far): the engine's plain pointers are DOS far pointers,
# its strings and constant tables in far data (sdk/docs/c/reference.md)
CFLAGS816 := --code large --data far -Icompat -Iplat -Ibuild/src -include compat/xcompat.h -w $(PLATDEFS)
# what XCOM.PRG checks before it starts (hcc --needs; APP.INF gets it from the program):
# Horizon 0.30, Marga's scrolling and split (sprites, REV $0B), the blitter; the memory:
# NEEDS_MEM (PORTING-NOTES.md "The app": the banks a big battle holds, MUSD.PRG's)
NEEDS_MEM ?= 2304K
NEEDS    := horizon=0.30,sprites,blitter,mem=$(NEEDS_MEM)
LFLAGS816 := --code large --data far --game --map --sizes --stack 8192 --heap 2048 --needs $(NEEDS)
DEPS816   := build/sum/headers.sum build/sum/sdk.sum
build/816/o/%.o: build/src/%.c build/src/.stamp $(DEPS816)
	@mkdir -p build/816/o
	$(HCC) $(CFLAGS816) $(if $(filter main,$*),-Dmain=xcom_main) -c -o $@ $<
build/816/p/%.o: plat/%.c build/sum/plat/%.c.sum $(DEPS816)
	@mkdir -p build/816/p
	$(HCC) $(CFLAGS816) -c -o $@ $<
build/816/p/%.o: plat/%.s build/sum/plat/%.s.sum $(DEPS816)
	@mkdir -p build/816/p
	$(HCC) $(CFLAGS816) -c -o $@ $<
build/816/h/%.o: horizon/%.c build/sum/horizon/%.c.sum $(DEPS816)
	@mkdir -p build/816/h
	$(HCC) $(CFLAGS816) -c -o $@ $<
build/816/h/%.o: horizon/%.s build/sum/horizon/%.s.sum $(DEPS816)
	@mkdir -p build/816/h
	$(HCC) $(CFLAGS816) -c -o $@ $<
OBJS816 = $(patsubst build/src/%.c,build/816/o/%.o,$(UPSRC)) \
          $(patsubst plat/%.c,build/816/p/%.o,$(PLATSRC)) \
          $(patsubst horizon/%.c,build/816/h/%.o,$(wildcard horizon/*.c)) \
          $(patsubst horizon/%.s,build/816/h/%.o,$(wildcard horizon/*.s))
XCOM.PRG: build/src/.stamp FORCE
	$(MAKE) build/816/XCOM.PRG
	cp build/816/XCOM.PRG $@
build/sum/lflags.sum: FORCE
	@mkdir -p build/sum
	@echo "$(LFLAGS816)" > $@.new; if cmp -s $@.new $@; then rm $@.new; else mv $@.new $@; fi
build/816/XCOM.PRG: $(OBJS816) build/sum/sdk.sum build/sum/lflags.sum
	$(HCC) $(LFLAGS816) -o $@ $(OBJS816) > build/816/link.txt || { cat build/816/link.txt; exit 1; }
	@grep -i "bytes on the card\|main bank" build/816/link.txt | head -4

# ---------------------------------------------------------------- the emulator
$(CARD):
	$(MAKE) -C $(HORIZON)

# (the two builds one after the other: each runs make src, which must not race)
builds:
	$(MAKE) XCOM.PRG
	$(MAKE) build/host/xcomhost
test: builds $(CARD)
	@test -f data/packs/PACKS.VER || { echo "make test needs the packs: make data GAME=..."; exit 1; }
	sh tests/check.sh $(HORIZON); a=$$?; sh tests/sound.sh $(HORIZON); b=$$?; \
	  if [ $$a = 0 ] && [ $$b = 0 ]; then echo "make test: all passed"; else echo "make test: FAILED"; exit 1; fi
# the longer runs (tests/runs-long): the screens walked through, the campaign soak
test-long: builds $(CARD)
	@test -f data/packs/PACKS.VER || { echo "make test-long needs the packs: make data GAME=..."; exit 1; }
	RUNS=tests/runs-long O=build/test-long sh tests/check.sh $(HORIZON)

# ---- speed (the speed helper's block): the felt figures with the real clock (tests/speed.sh)
speed: XCOM.PRG $(CARD)
	sh tests/speed.sh
# ----
refs: builds $(CARD)
	sh tests/check.sh $(HORIZON) --refs
refs-long: builds $(CARD)
	RUNS=tests/runs-long O=build/test-long sh tests/check.sh $(HORIZON) --refs

RUNFILES = $(foreach f,$(wildcard data/packs/*.PAK) data/packs/PACKS.VER,--file $(f):/GAMES/XCOM/$(notdir $(f))) \
           $(foreach f,$(wildcard data/packs/VGA/*),--file $(f):/GAMES/XCOM/VGA/$(notdir $(f))) \
           $(foreach f,$(wildcard tests/*.keys),--file $(f):/GAMES/XCOM/$(shell echo $(basename $(notdir $(f))) | tr a-z A-Z).KEY)
ARGS     ?= VGA NOINTRO
RUNFLAGS ?=
run: XCOM.PRG $(CARD)
	$(RUN816) XCOM.PRG --mode shell --dest /GAMES/XCOM/XCOM.PRG --cd /GAMES/XCOM --args "$(ARGS)" \
	  $(RUNFILES) --out build/run $(RUNFLAGS)

# ---------------------------------------------------------------- the music task (sound)
# MUSD.PRG (mus/musd.c + upstream's music.c, hcc's small model): XCOM.PRG spawns it from
# its own folder at the start; it owns the music timer and the OPL2 (horizon/hz_snd.c).
# It goes next to XCOM.PRG (the app folder, the tests' card).
MUSDSRC := mus/musd.c $(wildcard mus/inc/*.h)
all: MUSD.PRG
MUSD.PRG: build/src/.stamp FORCE
	$(MAKE) build/mus/MUSD.PRG
	cp build/mus/MUSD.PRG $@
build/mus/MUSD.PRG: $(foreach f,$(MUSDSRC),build/sum/$(f).sum) build/src/.stamp build/sum/sdk.sum
	@mkdir -p build/mus
	$(HCC) -Imus/inc -Ibuild/src -DXCOM_MUSD -w -o $@ mus/musd.c build/src/music.c > build/mus/link.txt || { cat build/mus/link.txt; exit 1; }
RUNFILES += --file MUSD.PRG:/GAMES/XCOM/MUSD.PRG
run: MUSD.PRG
builds: MUSD.PRG
sound: builds $(CARD)
	sh tests/sound.sh $(HORIZON)
.PHONY: sound
# ---------------------------------------------------------------- (sound end)

# ---------------------------------------------------------------- the app
# XCOM.HZA (make app): XCOM.PRG, MUSD.PRG, APP.INF, XCOM.ICN (app/XCOM-ICON.txt, drawn
# for the port), README.TXT: no game data, the archive one may give away. The player puts
# the packs made by XCOMCONV from their own copy into /APPS/XCOM/ (README.TXT); an update
# keeps them (the Installer keeps the files the archive has not).
# make app DATA=1: build/XCOM-DATA.HZA, the same app with the packs of data/packs in it
# (one's own card only: never to give away). make card: build/card/APPS/XCOM/, the app's
# folder with the packs, to copy onto one's card.
APPFILES = XCOM.PRG MUSD.PRG build/XCOM.ICN app/APP.INF app/README.TXT
PACKFILES = $(wildcard data/packs/*.PAK) data/packs/PACKS.VER
build/XCOM.ICN: app/XCOM-ICON.txt
	@mkdir -p build
	$(PYTHON) $(HORIZON)/tools/mkicons.py $< $@ /dev/null
build/app/XCOM/APP.INF: $(APPFILES) $(SDK)/tools/hzapp.py FORCE
	rm -rf build/app && mkdir -p build/app/XCOM
	cp XCOM.PRG MUSD.PRG build/XCOM.ICN app/README.TXT build/app/XCOM/
	grep -v '^#' app/APP.INF > build/app/XCOM/APP.INF
app: builds build/app/XCOM/APP.INF
	$(PYTHON) $(SDK)/tools/hzapp.py pack build/app/XCOM -o XCOM.HZA --mtime 0
	@if [ "$(DATA)" = 1 ]; then \
	  test -f data/packs/PACKS.VER || { echo "make app DATA=1 needs the packs: make data GAME=..."; exit 1; }; \
	  rm -rf build/appdata && mkdir -p build/appdata && cp -r build/app/XCOM build/appdata/ && \
	  cp $(PACKFILES) build/appdata/XCOM/ && mkdir -p build/appdata/XCOM/VGA && \
	  cp data/packs/VGA/* build/appdata/XCOM/VGA/ && \
	  $(PYTHON) $(SDK)/tools/hzapp.py pack build/appdata/XCOM -o build/XCOM-DATA.HZA --mtime 0 && \
	  echo "build/XCOM-DATA.HZA: the app with YOUR game data: for your own card only"; fi
card: builds build/app/XCOM/APP.INF
	@test -f data/packs/PACKS.VER || { echo "make card needs the packs: make data GAME=..."; exit 1; }
	rm -rf build/card && mkdir -p build/card/APPS
	cp -r build/app/XCOM build/card/APPS/ && cp $(PACKFILES) build/card/APPS/XCOM/
	mkdir -p build/card/APPS/XCOM/VGA && cp data/packs/VGA/* build/card/APPS/XCOM/VGA/
	@echo "build/card/APPS/XCOM: copy it to the card's /APPS (your own data: not to give away)"
# the app in the emulator (tests/app.sh): XCOM.HZA installed by the Installer from the
# Desktop and started from Programs > Games without data (the message), then with the
# packs in its folder: the start menu, a new game, a save in the app's folder; installed
# again (Replace): the data and the save kept
test-app: app $(CARD)
	sh tests/app.sh $(HORIZON)

clean:
	rm -rf build XCOM.PRG MUSD.PRG XCOM.HZA XCOM.map XCOM.lbl

.SECONDARY:
.PHONY: all src data host host-run check-host refs-host builds test test-long refs refs-long run app card test-app speed clean FORCE
FORCE:

# XCOM-XT (ports/xcom): X-COM: UFO Defense on an XT engine (GPL-3), on Horizon.
# STAGE 1: assessment and foundation (README.md, PORTING-NOTES.md).
#
#   make src        upstream/ (tools/getsrc.sh, pinned commit) + patches/src-*.patch -> build/src
#   make data GAME=DIR   your X-COM (DOS 1.4 / GOG) -> data/packs (upstream's XCOMCONV)
#   make host       build/host/xcomhost: the engine on Linux (headless, the reference)
#   make host-run ARGS="NOINTRO ..."   run it on data/packs: pictures in build/host/shots
#   make check-host  the reference runs (tests/host.runs) against tests/host.md5
#   make            XCOM.PRG (hcc --code large): the engine on the Atari816
#   make run        XCOM.PRG in the emulator with the packs (build/run)
#   make clean
# HORIZON=DIR: a Horizon tree with a built card (0.30).

SDK      ?= ../../sdk
HORIZON  ?= $(SDK)/../horizon
PYTHON   ?= python3
HCC      := $(PYTHON) $(SDK)/c/bin/hcc
RUN816   := $(PYTHON) $(SDK)/tools/run816.py --horizon $(HORIZON)
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
HEADERS   = $(wildcard build/src/*.h compat/*.h plat/*.h)

all: XCOM.PRG

# ---------------------------------------------------------------- upstream + patches
src: build/src/.stamp
build/src/.stamp: $(wildcard patches/src-*.patch)
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
HOSTFLAGS := -std=gnu99 -O1 -g -fno-strict-aliasing -w -Icompat -Iplat -Ibuild/src -include xcompat.h $(PLATDEFS)
host: build/host/xcomhost
build/host/o/%.o: build/src/%.c $(HEADERS) build/src/.stamp
	@mkdir -p build/host/o
	$(CC_HOST) $(HOSTFLAGS) $(if $(filter main,$*),-Dmain=xcom_main) -c -o $@ $<
build/host/p/%.o: plat/%.c $(HEADERS) build/src/.stamp
	@mkdir -p build/host/p
	$(CC_HOST) $(HOSTFLAGS) -c -o $@ $<
build/host/h/%.o: host/%.c $(HEADERS) build/src/.stamp
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
CFLAGS816 := --code large --data far -Icompat -Iplat -Ibuild/src -include compat/xcompat.h -fsigned-char -w $(PLATDEFS)
LFLAGS816 := --code large --data far --game --map --sizes --stack 8192 --heap 2048
build/816/o/%.o: build/src/%.c $(HEADERS) build/src/.stamp
	@mkdir -p build/816/o
	$(HCC) $(CFLAGS816) $(if $(filter main,$*),-Dmain=xcom_main) -c -o $@ $<
build/816/p/%.o: plat/%.c $(HEADERS) build/src/.stamp
	@mkdir -p build/816/p
	$(HCC) $(CFLAGS816) -c -o $@ $<
build/816/h/%.o: horizon/%.c $(HEADERS) build/src/.stamp
	@mkdir -p build/816/h
	$(HCC) $(CFLAGS816) -c -o $@ $<
XCOM.PRG: build/src/.stamp FORCE
	$(MAKE) build/816/XCOM.PRG
	cp build/816/XCOM.PRG $@
build/816/XCOM.PRG: $(patsubst build/src/%.c,build/816/o/%.o,$(UPSRC)) \
                    $(patsubst plat/%.c,build/816/p/%.o,$(PLATSRC)) \
                    $(patsubst horizon/%.c,build/816/h/%.o,$(wildcard horizon/*.c))
	$(HCC) $(LFLAGS816) -o $@ $^

clean:
	rm -rf build XCOM.PRG XCOM.map XCOM.lbl

.PHONY: all src data host host-run check-host refs-host clean FORCE
FORCE:

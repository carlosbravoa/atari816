# host/Makefile - upstream's SDLPoP (data/sdlpop/src, the pinned commit) built on the PC as
# the reference: with host/ref.patch (a state and picture hook, an OPL log; refhook.c) and
# a small SDL_image of its own (sdl_image_shim.c: SDL2 is enough). Needs SDL2's headers and
# libraries, zlib and a C compiler.
#
#   make -C host          ../data/sdlpop/prince-ref (beside SDLPoP's data/, where it looks)
UP      := ../data/sdlpop/src
OUT     := ../build/host
CC      ?= gcc
SRCS    := main data seg000 seg001 seg002 seg003 seg004 seg005 seg006 seg007 seg008 seg009 \
           seqtbl replay options lighting screenshot menu midi opl3 stb_vorbis
CFLAGS  := -std=gnu99 -O2 -w -D_GNU_SOURCE=1 -I. -I$(OUT)/src $(shell sdl2-config --cflags)
LIBS    := $(shell sdl2-config --libs) -lz -lm

all: ../data/sdlpop/prince-ref

../data/sdlpop/prince-ref: $(OUT)/prince
	cp $< $@

$(OUT)/src/.patched: $(UP)/seg003.c ref.patch
	rm -rf $(OUT)/src && mkdir -p $(OUT) && cp -r $(UP) $(OUT)/src
	cd $(OUT) && patch -s -p0 < $(CURDIR)/ref.patch
	touch $@

$(OUT)/prince: $(OUT)/src/.patched refhook.c sdl_image_shim.c SDL2/SDL_image.h
	$(CC) $(CFLAGS) -o $@ $(SRCS:%=$(OUT)/src/%.c) refhook.c sdl_image_shim.c $(LIBS)

.PHONY: all

# host/Makefile - the C translation on a PC (gcc or clang, C99): the reference checks.
#   make -C host            build/host/srtool (the CLI and the test tools)
#   make -C host sdl        build/host/skyroads-sdl (needs SDL2: sdl2-config)
CC      ?= cc
CFLAGS  ?= -O2 -g -std=c99 -Wall -Wextra -Wno-unused-parameter -D_DEFAULT_SOURCE
B       := ../build/host
GAME    := data/byteio data/compression data/image data/roads data/level data/trekdat \
           data/demo data/dashboard data/muzax data/config data/sound core/gameplay \
           core/app core/dos_render_tables core/dos_font renderer/renderer
OBJS    := $(GAME:%=$(B)/%.o)
HDRS    := $(wildcard ../src/*.h ../src/*/*.h)

all: $(B)/srtool $(B)/srsimcheck

$(B)/%.o: ../src/%.c $(HDRS)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -I../src -c -o $@ $<

$(B)/host_plat.o: host_plat.c $(HDRS)
	@mkdir -p $(B)
	$(CC) $(CFLAGS) -I../src -c -o $@ $<

$(B)/srtool: $(OBJS) $(B)/host_plat.o cli_main.c $(HDRS)
	$(CC) $(CFLAGS) -I../src -o $@ cli_main.c $(OBJS) $(B)/host_plat.o -lm

# the simulation against the one before round 2 (ref_gameplay.c): simcheck.c includes
# gameplay.c itself (its static functions are tested too)
NOSIM   := $(filter-out $(B)/core/gameplay.o,$(OBJS))
$(B)/srsimcheck: $(NOSIM) $(B)/host_plat.o simcheck.c ref_gameplay.c ../src/core/gameplay.c $(HDRS)
	$(CC) $(CFLAGS) -I../src -o $@ simcheck.c ref_gameplay.c $(NOSIM) $(B)/host_plat.o -lm

sdl: $(B)/skyroads-sdl
$(B)/skyroads-sdl: $(OBJS) $(B)/host_plat.o sdl_main.c $(HDRS)
	$(CC) $(CFLAGS) -I../src $(shell sdl2-config --cflags) -o $@ sdl_main.c $(OBJS) \
	  $(B)/host_plat.o $(shell sdl2-config --libs) -lm

clean:
	rm -rf $(B)

.PHONY: all sdl clean

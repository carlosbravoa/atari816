# emu816 — Atari816 native-side emulator.   make [SDL=1]   make test
CC      ?= gcc
CFLAGS  ?= -O2 -Wall -std=c11 -D_DEFAULT_SOURCE
LDLIBS  = -lm
# (Horizon 0.23) the firmware's converter of the classic Atari's printer output (plain C; no -I
# there: core/firmware has its own bare-metal stdlib.h, string.h)
FW      = ../core/firmware
# (Horizon 0.27) the OPL2's sound: Nuked OPL3 (nuked-opl3/, LGPL-2.1-or-later, unmodified)
SRCS    = main.c cpu65816.c freddie.c sysblock.c mailbox.c net.c nvc.c blitter.c audio.c opl.c $(FW)/prnconv.c \
          nuked-opl3/opl3.c
HDRS    = nvc_palette.h machine.h cpu65816.h freddie.h sysblock.h mailbox.h net.h nvc.h blitter.h audio.h opl.h $(FW)/prnconv.h \
          nuked-opl3/opl3.h

ifeq ($(SDL),1)
CFLAGS  += -DHAVE_SDL $(shell sdl2-config --cflags)
LDLIBS  += $(shell sdl2-config --libs)
endif

all: emu816

# built under a temporary name, so a running or failed build never leaves a broken emu816
emu816: $(SRCS) $(HDRS)
	$(CC) $(CFLAGS) -o $@.new $(SRCS) $(LDLIBS) && mv -f $@.new $@

tests/cputest: tests/cputest.c cpu65816.c cpu65816.h
	$(CC) $(CFLAGS) -o $@ tests/cputest.c cpu65816.c $(LDLIBS)

ASMTESTS = tests/asm/mbdemo.bin tests/asm/nvcdemo.bin tests/asm/cpuirq.bin tests/asm/nvcmode1.bin tests/asm/nvcmode2.bin \
           tests/asm/copabort.bin tests/asm/eirq.bin tests/asm/kbtest.bin tests/asm/nmihold.bin tests/asm/mousetest.bin tests/asm/pctest.bin \
           tests/asm/slowtest.bin tests/asm/nettest1.bin tests/asm/nettest2.bin tests/asm/nettest3.bin \
           tests/asm/opltimer.bin tests/asm/opltone.bin

# the test programs are rebuilt when ca65 is available (the .bin files are kept)
tests/asm/%.bin: tests/asm/%.s tests/asm/common.inc tests/asm/a816.cfg
	cd tests/asm && ca65 -o $*.o $*.s && ld65 -C a816.cfg -o $*.bin $*.o && rm -f $*.o
tests/asm/nvcdemo.bin: tests/asm/pointer.inc
tests/asm/nvcmode1.bin: tests/asm/nvcmodes.s tests/asm/common.inc tests/asm/a816.cfg
	cd tests/asm && ca65 -o m1.o nvcmodes.s && ld65 -C a816.cfg -o nvcmode1.bin m1.o && rm -f m1.o
tests/asm/nvcmode2.bin: tests/asm/nvcmodes.s tests/asm/common.inc tests/asm/a816.cfg
	cd tests/asm && ca65 -D MODE2 -o m2.o nvcmodes.s && ld65 -C a816.cfg -o nvcmode2.bin m2.o && rm -f m2.o
tests/asm/nettest%.bin: tests/asm/nettest.s tests/asm/common.inc tests/asm/a816.cfg
	cd tests/asm && ca65 -D RUN=$* -o nt$*.o nettest.s && ld65 -C a816.cfg -o nettest$*.bin nt$*.o && rm -f nt$*.o

test: emu816 tests/cputest $(ASMTESTS)
	./tests/run_tests.sh

# download a 200-tests-per-file sample of SingleStepTests/65816 (~40 MB) for make test
sst:
	python3 tests/fetch_sst.py tests/sst 200

clean:
	rm -f emu816 tests/cputest tests/asm/*.o

.PHONY: all test clean sst

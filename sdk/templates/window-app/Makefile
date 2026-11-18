# A Horizon program (Atari816): NAME.PRG from main.s (and any other .s files here).
#
#   make            build HELLOWIN.PRG
#   make run        run it in the emulator (the Desktop starts it), screenshot in build/run/
#   make test       the scripted test (test.script): screenshots and the file it saved
#   make clean
#
# Copy this folder to start a program of your own and change NAME.

NAME    := hellowin
# Desktop mode: the Desktop boots and starts the program from its Programs menu.
RUNMODE := desktop
# 1 = link Horizon's controls library (user/ui.inc, build/ui.lib)
UI      := 1

# The Horizon tree to build against: its user/ (horizon.inc, ui.inc, prog.cfg), its
# build/ (ulib.o, ui.lib) and its build/sd (the SD card the emulator boots).
HORIZON ?= ../../../horizon
SDK     ?= ../..
CA65    ?= ca65
LD65    ?= ld65

PRG     := $(shell echo $(NAME) | tr a-z A-Z).PRG
# main.s first: the program starts at the first byte of CODE, which is main.o's
SRCS    := main.s $(filter-out main.s,$(wildcard *.s))
OBJS    := $(patsubst %.s,build/%.o,$(SRCS))
LIBS    := $(HORIZON)/build/ulib.o $(if $(filter 1,$(UI)),$(HORIZON)/build/ui.lib)
INCS    := $(HORIZON)/user/horizon.inc $(if $(filter 1,$(UI)),$(HORIZON)/user/ui.inc)
CARD    := $(HORIZON)/build/sd/SYSTEM/HORIZON.SYS
RUN816  := python3 $(SDK)/tools/run816.py --horizon $(HORIZON) --mode $(RUNMODE)

all: $(PRG)

build/%.o: %.s $(wildcard *.inc) $(INCS) | build
	$(CA65) -I . -I $(HORIZON)/user -o $@ $<

$(PRG): $(OBJS) $(LIBS) $(HORIZON)/user/prog.cfg
	$(LD65) -C $(HORIZON)/user/prog.cfg -o $@ $(OBJS) $(LIBS)

# Horizon's user library and controls library, built in the Horizon tree
$(HORIZON)/build/ulib.o $(HORIZON)/build/ui.lib:
	$(MAKE) -C $(HORIZON) build/ulib.o build/ui.lib

# the SD card the emulator boots (the whole of Horizon)
$(CARD):
	$(MAKE) -C $(HORIZON)

build:
	mkdir -p build

run: $(PRG) $(CARD)
	$(RUN816) $(PRG) --shot 1 --out build/run

# (a program made from this template: replace the NAME.TXT check with its own)
test: $(PRG) $(CARD)
	$(RUN816) $(PRG) --script test.script --out build/test
	test "$$(cat build/test/card/NAME.TXT)" = "Ada"
	@echo "PASS  the file saved by the program holds the name"

clean:
	rm -rf build $(PRG)

.PHONY: all run test clean

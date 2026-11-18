# A Horizon program (Atari816): NAME.PRG from main.s (and any other .s files here).
#
#   make            build GREET.PRG
#   make run        run it in the emulator (text shell), screenshot in build/run/
#   make test       the scripted test (test.script), checked by its output
#   make clean
#
# Copy this folder to start a program of your own and change NAME (8 letters at most is
# the shell's habit; any FAT name works).

NAME    := greet
# Shell mode: a console program (its output goes to the screen and to the console log).
RUNMODE := shell
# 1 = link Horizon's controls library (user/ui.inc, build/ui.lib): window programs only.
UI      := 0

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
CARD    := $(HORIZON)/build/sd/SYSTEM/HORIZON.SYS
RUN816  := python3 $(SDK)/tools/run816.py --horizon $(HORIZON) --mode $(RUNMODE)

all: $(PRG)

build/%.o: %.s $(wildcard *.inc) $(HORIZON)/user/horizon.inc | build
	$(CA65) -I . -I $(HORIZON)/user -o $@ $<

$(PRG): $(OBJS) $(LIBS) $(HORIZON)/user/prog.cfg
	$(LD65) -C $(HORIZON)/user/prog.cfg -o $@ $(OBJS) $(LIBS)

# Horizon's user library (and the controls library), built in the Horizon tree
$(HORIZON)/build/ulib.o $(HORIZON)/build/ui.lib:
	$(MAKE) -C $(HORIZON) build/ulib.o build/ui.lib

# the SD card the emulator boots (the whole of Horizon)
$(CARD):
	$(MAKE) -C $(HORIZON)

build:
	mkdir -p build

run: $(PRG) $(CARD)
	$(RUN816) $(PRG) --args 'one "two words"' --script test.script --out build/run

test: $(PRG) $(CARD)
	$(RUN816) $(PRG) --args 'one "two words"' --script test.script --out build/test \
	    --expect 'argument 2: two words' --expect 'Hello, Ada! Your name has 3 letters.' \
	    --expect 'GREET.LOG now has 1 line(s).'

clean:
	rm -rf build $(PRG)

.PHONY: all run test clean

# Tune - play a module with the replayer library (Horizon 0.26, Atari816): TUNE.PRG from main.s,
# linked with Horizon's build/modplay.o.
#
#   make            build TUNE.PRG
#   make run        play /Music/LAU.MOD in the emulator (build/run/; emu816 records Lau's sound
#                   in build/run/tune.wav: listen to it on the PC)
#   make test       the same: it must play to the end ("tune: the end")
#   make clean
#
# Pass HORIZON=... (and SDK=...) when your Horizon tree is somewhere else.

NAME    := tune
RUNMODE := shell

HORIZON ?= ../../../horizon
SDK     ?= ../..
CA65    ?= ca65
LD65    ?= ld65

PRG     := $(shell echo $(NAME) | tr a-z A-Z).PRG
SRCS    := main.s
OBJS    := build/main.o
LIBS    := $(HORIZON)/build/modplay.o $(HORIZON)/build/ulib.o
CARD    := $(HORIZON)/build/sd/SYSTEM/HORIZON.SYS
RUN816  := python3 $(SDK)/tools/run816.py --horizon $(HORIZON) --mode $(RUNMODE)
SECS    := 18

all: $(PRG)

build/%.o: %.s $(HORIZON)/user/horizon.inc $(HORIZON)/user/modplay.inc | build
	$(CA65) -I . -I $(HORIZON)/user -o $@ $<

$(PRG): $(OBJS) $(LIBS) $(HORIZON)/user/prog.cfg
	$(LD65) -C $(HORIZON)/user/prog.cfg -o $@ $(OBJS) $(LIBS)

$(HORIZON)/build/ulib.o $(HORIZON)/build/modplay.o:
	$(MAKE) -C $(HORIZON) build/ulib.o build/modplay.o

$(CARD):
	$(MAKE) -C $(HORIZON)

build:
	mkdir -p build

run: $(PRG) $(CARD)
	$(RUN816) $(PRG) --args /Music/LAU.MOD --seconds $(SECS) --out build/run --wav build/run/tune.wav

test: $(PRG) $(CARD)
	$(RUN816) $(PRG) --args /Music/LAU.MOD --seconds $(SECS) --out build/test --log-lau \
	    --expect 'tune: the end'
	@echo "PASS  the module played to its end"

clean:
	rm -rf build $(PRG)

.PHONY: all run test clean

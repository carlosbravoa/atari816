# Slider: the 4 x 4 sliding-tile puzzle for Horizon (Atari816). SLIDER.PRG from main.s.
#
#   make            build SLIDER.PRG
#   make run        run it in the emulator (the Desktop starts it, a shuffled board),
#                   screenshot in build/run/
#   make test       1. shell mode, "slider -e": solve the two moves by script (a click and
#                      a key), screenshots, the console line checked
#                   2. Desktop mode, a normal shuffle: one screenshot (build/test-desk/)
#   make clean
#
# Build against another Horizon tree: make HORIZON=/path/to/horizon

NAME    := slider
# Desktop mode: the Desktop boots and starts the program from its Programs menu.
RUNMODE := desktop
# 1 = link Horizon's controls library (this program draws everything itself)
UI      := 0

# The Horizon tree to build against: its user/ (horizon.inc, prog.cfg), its build/
# (ulib.o) and its build/sd (the SD card the emulator boots).
HORIZON ?= ../../../horizon
SDK     ?= ../..
CA65    ?= ca65
LD65    ?= ld65

PRG     := $(shell echo $(NAME) | tr a-z A-Z).PRG
SRCS    := $(wildcard *.s)
OBJS    := $(patsubst %.s,build/%.o,$(SRCS))
LIBS    := $(HORIZON)/build/ulib.o $(if $(filter 1,$(UI)),$(HORIZON)/build/ui.lib)
INCS    := $(HORIZON)/user/horizon.inc $(if $(filter 1,$(UI)),$(HORIZON)/user/ui.inc)
CARD    := $(HORIZON)/build/sd/SYSTEM/HORIZON.SYS
RUN816  := python3 $(SDK)/tools/run816.py --horizon $(HORIZON)

all: $(PRG)

build/%.o: %.s $(wildcard *.inc) $(INCS) | build
	$(CA65) -I . -I $(HORIZON)/user -o $@ $<

$(PRG): $(OBJS) $(LIBS) $(HORIZON)/user/prog.cfg
	$(LD65) -C $(HORIZON)/user/prog.cfg -m build/$(NAME).map -o $@ $(OBJS) $(LIBS)

# Horizon's user library, built in the Horizon tree
$(HORIZON)/build/ulib.o $(HORIZON)/build/ui.lib:
	$(MAKE) -C $(HORIZON) build/ulib.o build/ui.lib

# the SD card the emulator boots (the whole of Horizon)
$(CARD):
	$(MAKE) -C $(HORIZON)

build:
	mkdir -p build

run: $(PRG) $(CARD)
	$(RUN816) $(PRG) --mode $(RUNMODE) --shot 1 --out build/run

test: $(PRG) $(CARD)
	$(RUN816) $(PRG) --mode shell --args "-e" --script test.script --out build/test \
	  --log-sound --expect "slider: solved in 2 moves"
	@grep -q 'DB01' build/test/emu.err && echo "PASS  sound: POKEY 2 written" || \
	  { echo "FAIL  no sound written (build/test/emu.err)"; exit 1; }
	$(RUN816) $(PRG) --mode desktop --shot 1 --out build/test-desk
	@echo "PASS  solved by script; Desktop screenshot in build/test-desk/shot1.png"

clean:
	rm -rf build $(PRG)

.PHONY: all run test clean

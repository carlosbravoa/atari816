# Hex View - a hex dump viewer for Horizon (Atari816): HEXVIEW.PRG from main.s.
#
#   make            build HEXVIEW.PRG
#   make run        run it in the emulator (the Desktop starts it), screenshot in build/run/
#   make test       the scripted tests: shell mode with a file argument (test.script),
#                   then desktop mode with File > Open... (desktop.script)
#   make clean
#
# Pass HORIZON=... (and SDK=...) when your Horizon tree is somewhere else.

NAME    := hexview
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

# Horizon's user library and controls library, built in the Horizon tree
$(HORIZON)/build/ulib.o $(HORIZON)/build/ui.lib:
	$(MAKE) -C $(HORIZON) build/ulib.o build/ui.lib

# the SD card the emulator boots (the whole of Horizon)
$(CARD):
	$(MAKE) -C $(HORIZON)

build:
	mkdir -p build

# A test file of 70,000 bytes (more than the 64 KB Hex View shows): the 256 byte values,
# then lines of text, and "END" markers at 65,520 (the last line shown) and at the end.
build/BIG.BIN: | build
	python3 -c "import sys; \
	d = bytearray(range(256)); \
	d += b''.join(b'Line %05d of the Hex View test file.\n' % i for i in range(1900)); \
	d = d[:65520] + b'-- 64 KB here --'; \
	d += bytes((i * 7) & 255 for i in range(70000 - 16 - len(d))) + b'END OF BIG.BIN!\n'; \
	sys.stdout.buffer.write(d)" > $@

run: $(PRG) $(CARD)
	$(RUN816) $(PRG) --mode $(RUNMODE) --shot 1 --out build/run

# 1. shell mode: "HEXVIEW.PRG /BIG.BIN" (scrolling, Go to, a resize)
# 2. desktop mode: File > Open... picks /LONG.TXT (a file on Horizon's card), then
#    README.TXT is dragged from Files onto the window
test: $(PRG) $(CARD) build/BIG.BIN
	$(RUN816) $(PRG) --mode shell --args /BIG.BIN --file build/BIG.BIN:/BIG.BIN \
	    --script test.script --out build/test \
	    --expect 'hexview: BIG.BIN, 70000 bytes'
	@echo "PASS  shell mode: the argument was loaded (see build/test/shot*.png)"
	$(RUN816) $(PRG) --mode desktop --script desktop.script --out build/desk \
	    --expect 'hexview: LONG.TXT, 9635 bytes' --expect 'hexview: README.TXT, 110 bytes'
	@echo "PASS  desktop mode: File > Open... loaded LONG.TXT, a drop README.TXT (build/desk/)"

clean:
	rm -rf build $(PRG)

.PHONY: all run test clean

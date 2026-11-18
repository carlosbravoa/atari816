# Deep Dive (Atari816, Horizon 0.18): DEEPDIVE.PRG from main.s and the art in art/*.txt.
#
#   make            build DEEPDIVE.PRG (the art first: art/*.txt -> art/*.inc)
#   make run        run it in the emulator (the Desktop starts it), screenshot in build/run/
#   make test       the scripted test (test.script): screenshots, console lines, Lau written
#   make preview    pictures of the art, magnified: build/art-*.png (needs Pillow; shown in
#                   the system palette's colours, not the game's own)
#   make clean
#
# See README.md.

NAME    := deepdive
# Desktop mode: the Desktop boots and starts the program from its Programs menu.
RUNMODE := desktop
UI      := 0

# The Horizon tree to build against: its user/ (horizon.inc, prog.cfg), its build/
# (ulib.o) and its build/sd (the SD card the emulator boots).
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
ART     := $(patsubst %.txt,%.inc,$(wildcard art/*.txt))
CARD    := $(HORIZON)/build/sd/SYSTEM/HORIZON.SYS
RUN816  := python3 $(SDK)/tools/run816.py --horizon $(HORIZON) --mode $(RUNMODE)

all: $(PRG)

build/%.o: %.s $(wildcard *.inc) $(ART) $(INCS) | build
	$(CA65) -I . -I $(HORIZON)/user -o $@ $<

$(PRG): $(OBJS) $(LIBS) $(HORIZON)/user/prog.cfg
	$(LD65) -C $(HORIZON)/user/prog.cfg -o $@ $(OBJS) $(LIBS)

# the pictures: text art to 8 bpp pixels (entries of the game's own palette)
art/%.inc: art/%.txt $(SDK)/tools/img2inc.py
	python3 $(SDK)/tools/img2inc.py $< -o $@ --name $*

# the panel's letters: 1 bpp, drawn with LS_EXPAND records
art/font.inc: art/font.txt $(SDK)/tools/font2inc.py
	python3 $(SDK)/tools/font2inc.py $< -o $@ --name font

# Horizon's user library, built in the Horizon tree
$(HORIZON)/build/ulib.o $(HORIZON)/build/ui.lib:
	$(MAKE) -C $(HORIZON) build/ulib.o build/ui.lib

# the SD card the emulator boots (the whole of Horizon)
$(CARD):
	$(MAKE) -C $(HORIZON)

build:
	mkdir -p build

run: $(PRG) $(CARD)
	$(RUN816) $(PRG) --shot 2 --out build/run

# played by test.script in the Desktop: the dive, the pause (Alt+Esc), back (Alt+Tab), Esc;
# the console lines checked; Lau's register writes logged (--log-lau) and looked for
test: $(PRG) $(CARD)
	$(RUN816) $(PRG) --script test.script --out build/test --log-lau \
	    --expect 'deepdive: diving' --expect 'deepdive: pearl 2' \
	    --expect 'deepdive: sound on Lau' --expect 'deepdive: paused' \
	    --expect 'deepdive: resumed' --expect 'deepdive: bye'
	@grep -q '^lau ' build/test/emu.err && echo "PASS  sound: Lau written" || \
	  { echo "FAIL  Lau not written (build/test/emu.err)"; exit 1; }

preview: $(ART) | build
	for f in art/*.txt; do [ $$f = art/font.txt ] || python3 $(SDK)/tools/img2inc.py $$f \
	  -o /dev/null --preview build/art-$$(basename $$f .txt).png --scale 8; done
	python3 $(SDK)/tools/font2inc.py art/font.txt -o /dev/null --preview build/art-font.png

clean:
	rm -rf build $(PRG) art/*.inc

.PHONY: all run test preview clean

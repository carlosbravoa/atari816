# Lantern (Atari816): LANTERN.PRG from main.s, bigtext.s and the art in art/*.txt.
#
#   make            build LANTERN.PRG (the art first: art/*.txt -> art/*.inc)
#   make run        run it in the emulator (the Desktop starts it), screenshot in build/run/
#   make test       the scripted test (test.script): screenshots, sound writes checked
#   make preview    pictures of the art, magnified: build/art-*.png (needs Pillow)
#   make clean
#
# See README.md.

NAME    := lantern
# Desktop mode: the Desktop boots and starts the program from its Programs menu.
RUNMODE := desktop
# 1 = link Horizon's controls library (a game does not need it)
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

# the art: text pictures to 8 bpp pixels (sdk/tools/img2inc.py)
art/%.inc: art/%.txt $(SDK)/tools/img2inc.py
	python3 $(SDK)/tools/img2inc.py $< -o $@ --name $*

# the big letters: a 1 bpp font with advance widths (sdk/tools/font2inc.py)
art/bigfont.inc: art/bigfont.txt $(SDK)/tools/font2inc.py
	python3 $(SDK)/tools/font2inc.py $< -o $@ --name bigfont --prop

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

# 1. played by test.script in the Desktop (screenshots; the sound writes checked)
# 2. the demo (any argument: autopilot) in the text shell until the dawn and the game over
test: $(PRG) $(CARD)
	$(RUN816) $(PRG) --script test.script --out build/test --log-sound
	@grep -q 'DB01' build/test/emu.err && echo "PASS  sound: POKEY 2 written" || \
	  { echo "FAIL  no sound written (build/test/emu.err)"; exit 1; }
	python3 $(SDK)/tools/run816.py --horizon $(HORIZON) --mode shell $(PRG) --args demo \
	    --seconds 150 --shot 3 --shot 148 --out build/demo \
	    --expect 'lantern: night 1 cleared' --expect 'lantern: game over'

preview: $(ART) | build
	for f in art/*.txt; do [ $$f = art/bigfont.txt ] || python3 $(SDK)/tools/img2inc.py $$f \
	  -o /dev/null --preview build/art-$$(basename $$f .txt).png --scale 8; done
	python3 $(SDK)/tools/font2inc.py art/bigfont.txt -o /dev/null --prop --preview build/art-bigfont.png

clean:
	rm -rf build $(PRG) art/*.inc

.PHONY: all run test preview clean

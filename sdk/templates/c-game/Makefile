# Gem Run in C (Atari816, Horizon): GEMRUNC.PRG from main.c and the art in art/*.txt, on
# hgame, the C SDK's game library (sdk/docs/c/games.md).
#
#   make            build GEMRUNC.PRG (the art first: art/*.txt -> art/*.h, by img2c.py)
#   make run        run it in the emulator (the Desktop starts it), screenshot in build/run/
#   make test       the scripted test (test.script): console lines checked, screenshots in
#                   build/test/, the POKEY writes logged (--log-sound) and looked for
#   make preview    pictures of the art, magnified: build/art-*.png (needs Pillow)
#   make clean
#
# Copy this folder to start a game of your own, change NAME and, if the copy is not two
# levels below the sdk folder, SDK. The rules are in sdk/c/c.mk.

NAME      := gemrunc
SDK       ?= ../..
RUNMODE   := desktop
SRCS      := main.c
ART       := $(patsubst %.txt,%.h,$(wildcard art/*.txt))
TESTFLAGS := --log-sound --expect 'GEMRUN: title' --expect 'GEMRUN: level 1' \
             --expect 'GEMRUN: gem, score 10' --expect ' frames, '
TESTCHECK := grep -q 'DB01' build/test/emu.err && echo "PASS  sound: POKEY written" || \
             { echo "FAIL  no sound written (build/test/emu.err)"; exit 1; }
include $(SDK)/c/c.mk

$(PRG): $(ART)

# the art: text pictures to C arrays of 8 bpp pixels (sdk/tools/img2c.py)
art/%.h: art/%.txt $(SDK)/tools/img2c.py
	$(PYTHON) $(SDK)/tools/img2c.py $< -o $@ --name $*

preview: $(ART)
	@mkdir -p build
	for f in art/*.txt; do $(PYTHON) $(SDK)/tools/img2c.py $$f -o /dev/null \
	  --preview build/art-$$(basename $$f .txt).png --scale 8; done

.PHONY: preview

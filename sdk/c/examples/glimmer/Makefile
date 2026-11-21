# Glimmer (sdk/c/examples/glimmer): a full-screen scrolling game in C on hgame.
#
#   make            GLIMMER.PRG (the art first: art/*.txt -> art/*.h, by img2c.py)
#   make run        run it in the emulator (the Desktop starts it): build/run/shot1.png
#   make test       test.script: the flight, the pause, Esc; console lines checked,
#                   Lau's register writes logged (--log-lau) and looked for
#   make clean

NAME      := glimmer
SDK       ?= ../../..
RUNMODE   := desktop
SRCS      := main.c
ART       := art/tiles.h art/fly.h art/spark.h art/bat.h
RUNFLAGS  := --shot 2
TESTFLAGS := --log-lau --expect 'GLIMMER: flying' --expect 'GLIMMER: sound on Lau' \
             --expect 'GLIMMER: spark 1' --expect 'GLIMMER: spark 2' \
             --expect 'GLIMMER:' --expect ' frames, '
TESTCHECK := grep -q '^lau ' build/test/emu.err && echo "PASS  sound: Lau written" || \
             { echo "FAIL  Lau not written (build/test/emu.err)"; exit 1; }
include $(SDK)/c/c.mk

$(PRG): $(ART)

# tiles are opaque; the sprites keep colour 0 transparent (Marga's rule)
art/tiles.h: art/tiles.txt $(SDK)/tools/img2c.py
	$(PYTHON) $(SDK)/tools/img2c.py $< -o $@ --name tiles --key none
art/%.h: art/%.txt $(SDK)/tools/img2c.py
	$(PYTHON) $(SDK)/tools/img2c.py $< -o $@ --name $* --key 0

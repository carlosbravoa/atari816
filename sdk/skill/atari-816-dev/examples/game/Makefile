# A game in C (made like sdk/templates/c-game, on hgame): make, make run, make test.
NAME      := dot
SDK       ?= ../../../..
RUNMODE   := desktop
TESTFLAGS := --expect 'DOT: start' --expect 'DOT: at 210 80' --expect ' frames, '
# the picture: the square where the program said it is (each pixel 4 x 4 on the 1280 x 720
# screenshot), the text's light grey at the top left
TESTCHECK := python3 -c "from PIL import Image; im = Image.open('build/test/shot1.png').convert('RGB'); \
  assert im.getpixel((210 * 4 + 32, 80 * 4 + 32)) != (0, 0, 0), 'no square'; \
  assert (238, 238, 238) in [im.getpixel((x, y)) for x in range(32, 400) for y in range(32, 72)], 'no text'" \
  && echo "PASS  the square and the text are in the picture"
include $(SDK)/c/c.mk

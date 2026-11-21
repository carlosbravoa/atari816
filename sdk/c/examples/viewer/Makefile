# viewer - a text file viewer in C with the controls library (hui.h): a list fed by a C
# function, scroll bars, a resizable window, the file dialog, drag and drop.
#
#   make            build VIEWER.PRG
#   make run        run it (the text shell starts "viewer /VIEWTEST.TXT")
#   make test       two scripted runs: the shell with a file argument (test.script:
#                   keys, the scroll bar, two resizes), then the Desktop (desktop.script:
#                   File > Open..., a file dragged from Files)
NAME := viewer
SDK  ?= ../../..
ARGS := /VIEWTEST.TXT
RUNFLAGS := --file viewtest.txt:/VIEWTEST.TXT
TESTFLAGS := --expect 'viewer: VIEWTEST.TXT, 7311 bytes, 120 lines' \
             --expect 'viewer: line 120: Line 120: a long line' \
             --expect 'viewer: resized to 394x168, 8 rows shown' \
             --expect 'viewer: resized to 624x300, 17 rows shown'
TESTCHECK = python3 $(SDK)/tools/run816.py --horizon $(HORIZON) $(PRG) --mode desktop \
             --script desktop.script --out build/desk \
             --expect 'viewer: LONG.TXT, 9635 bytes' --expect 'viewer: README.TXT, 110 bytes'
include $(SDK)/c/c.mk

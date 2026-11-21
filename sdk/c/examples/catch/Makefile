# Catch (sdk/c/examples/catch): a text-mode game on cc65's conio.h only.
#
#   make            CATCH.PRG
#   make run        run it in the emulator (the Desktop starts it)
#   make test       test.script: the title, a game played to its end, Q
#   make clean

NAME      := catch
SDK       ?= ../../..
RUNMODE   := desktop
TESTFLAGS := --expect 'CATCH: game over'
include $(SDK)/c/c.mk

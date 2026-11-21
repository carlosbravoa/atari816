# A window program in C (Atari816): HELLOWIN.PRG from every .c (and .s) here, with
# Horizon's controls library (hui.h: hcc links it because the program uses it).
#
#   make            build HELLOWIN.PRG
#   make run        run it in the emulator (the Desktop starts it), output in build/run/
#   make test       the scripted test (test.script): screenshots and the file it saved
#   make clean
#
# Copy this folder to start a program of your own, change NAME and, if the copy is not two
# levels below the sdk folder, SDK. The rules are in sdk/c/c.mk; the tutorial is
# sdk/docs/c/apps.md.

NAME    := hellowin
SDK     ?= ../..
# Desktop mode: the Desktop boots and starts the program from its Programs menu
RUNMODE := desktop
RUNFLAGS := --shot 1
# (a program made from this template: replace the NAME.TXT check with its own)
TESTCHECK := test "$$(cat build/test/card/NAME.TXT)" = "Ada" && \
             echo "PASS  the file saved by the program holds the name"
include $(SDK)/c/c.mk

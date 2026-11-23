# A Horizon program in C (Atari816): GREET.PRG from every .c (and .s) here.
#
#   make            build GREET.PRG
#   make run        run it in the emulator (text shell), output in build/run/
#   make test       the scripted test (test.script), checked by its output
#   make clean
#
# Copy this folder to start a program of your own, change NAME and, if the copy is not two
# levels below the sdk folder, SDK. The rules are in sdk/c/c.mk (its comment lists the
# settings: HZ_CODE, HCCFLAGS, ARGS, ...).

NAME := greet
SDK  ?= ../..
ARGS := one "two words"
TESTFLAGS := --expect 'argument 2: two words' --expect 'Hello, Ada! Your name has 3 letters.' \
             --expect 'GREET.LOG now has 1 line(s).'
include $(SDK)/c/c.mk

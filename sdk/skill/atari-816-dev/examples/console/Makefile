# A console program in C (made like sdk/templates/c-console): make, make run, make test.
NAME      := sum
SDK       ?= ../../../..
ARGS      := 2 40
TESTFLAGS := --expect 'sum of 2 arguments: 42' --expect 'saved Ada in SUM.TXT'
TESTCHECK := test "$$(cat build/test/card/SUM.TXT)" = "Ada 42" && echo "PASS  SUM.TXT"
include $(SDK)/c/c.mk

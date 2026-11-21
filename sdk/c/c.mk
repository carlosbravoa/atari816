# c.mk - make rules for a Horizon program in C. A program's Makefile:
#
#   NAME := greet
#   SDK  ?= ../..
#   include $(SDK)/c/c.mk
#
# (SDK: the sdk folder, relative to the program's folder.) Then:
#
#   make            NAME.PRG (in capitals) from every .c and .s here (hcc)
#   make run        run it in the emulator (sdk/tools/run816.py), output in build/run/
#   make test       the same with TESTFLAGS (--expect lines): the program checks itself
#   make clean
#
# Set any of these before the include line to change them:
#   SRCS      the sources (default: every .c and .s in the folder)
#   MODEL     large (default) or tiny (docs/c/reference.md, "Memory models")
#   HCCFLAGS  more hcc options (-O2, --float, -I dir, --stack N, --debug, ...)
#   RUNMODE   shell (default: a console program, typed at the shell's prompt) or desktop
#             (a window program, chosen from the Desktop's Programs menu)
#   ARGS      the argument string for make run / make test (shell mode)
#   SCRIPT    the input script (default: test.script if there is one)
#   RUNFLAGS  more run816 options (--shot 2, --seconds 10, --file SRC:DEST, ...)
#   TESTFLAGS run816 options for make test, usually --expect 'TEXT' (repeatable)
#   HORIZON   the Horizon tree with a built card (default: $(SDK)/../horizon)

ifndef SDK
$(error set SDK (the sdk folder) before including c.mk)
endif
HORIZON  ?= $(SDK)/../horizon
NAME     ?= $(notdir $(CURDIR))
PRG      := $(shell echo $(NAME) | tr a-z A-Z).PRG
SRCS     ?= $(wildcard *.c *.s)
MODEL    ?= large
HCCFLAGS ?=
RUNMODE  ?= shell
ARGS     ?=
SCRIPT   ?= $(wildcard test.script)
RUNFLAGS ?=
TESTFLAGS ?=
PYTHON   ?= python3
HCC      := $(PYTHON) $(SDK)/c/bin/hcc
RUN816   := $(PYTHON) $(SDK)/tools/run816.py --horizon $(HORIZON) --mode $(RUNMODE) \
            $(if $(ARGS),--args '$(ARGS)') $(if $(SCRIPT),--script $(SCRIPT))
CARD     := $(HORIZON)/build/sd/SYSTEM/HORIZON.SYS

all: $(PRG)

$(PRG): $(SRCS) $(wildcard *.h) $(MAKEFILE_LIST)
	$(HCC) --model $(MODEL) $(HCCFLAGS) -o $@ $(SRCS)

# the SD card the emulator boots (the whole of Horizon)
$(CARD):
	$(MAKE) -C $(HORIZON)

run: $(PRG) $(CARD)
	$(RUN816) $(PRG) --out build/run $(RUNFLAGS)

test: $(PRG) $(CARD)
	$(RUN816) $(PRG) --out build/test $(RUNFLAGS) $(TESTFLAGS)

clean:
	rm -rf build $(PRG)

.PHONY: all run test clean

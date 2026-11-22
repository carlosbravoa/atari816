# c.mk - make rules for a Horizon program in C. A program's Makefile:
#
#   NAME := greet
#   SDK  ?= ../..
#   include $(SDK)/c/c.mk
#
# (SDK: the sdk folder, relative to the program's folder.) A program that includes hui.h
# (the controls library: docs/c/apps.md) gets the library linked by hcc by itself. Then:
#
#   make            NAME.PRG (in capitals) from every .c and .s here (hcc)
#   make run        run it in the emulator (sdk/tools/run816.py), output in build/run/
#   make test       the same with TESTFLAGS (--expect lines): the program checks itself
#   make clean
#
# Set any of these before the include line (or on make's command line) to change them:
#   SRCS      the sources (default: every .c and .s in the folder)
#   HZ_CC     the compiler: cc816 or vbcc (default: hcc's, cc816; docs/c/reference.md)
#   MODEL     vbcc only: large (its default) or tiny (docs/c/reference.md, "Memory")
#   HZ_CODE   cc816 only: the code model, small (the default) or large (hcc --code large:
#             code in several banks, NAME.PRX next to NAME.PRG; docs/c/reference.md)
#   HCCFLAGS  more hcc options (-O1, --stack N, --debug, -I dir, vbcc's --float, ...)
#   RUNMODE   shell (default: a console program, typed at the shell's prompt) or desktop
#             (a window program, chosen from the Desktop's Programs menu)
#   ARGS      the argument string for make run / make test (shell mode)
#   SCRIPT    the input script (default: test.script if there is one)
#   RUNFLAGS  more run816 options (--shot 2, --seconds 10, --file SRC:DEST, ...)
#   TESTFLAGS run816 options for make test, usually --expect 'TEXT' (repeatable)
#   TESTCHECK a shell command run after make test's run, which fails the test when it
#             fails (e.g. a check of a file the program wrote on the card, build/test/card)
#   HORIZON   the Horizon tree with a built card (default: $(SDK)/../horizon)

ifndef SDK
$(error set SDK (the sdk folder) before including c.mk)
endif
HORIZON  ?= $(SDK)/../horizon
NAME     ?= $(notdir $(CURDIR))
PRG      := $(shell echo $(NAME) | tr a-z A-Z).PRG
SRCS     ?= $(wildcard *.c *.s)
MODEL    ?=
HZ_CC    ?=
export HZ_CC
HZ_CODE  ?=
export HZ_CODE
HCCFLAGS ?=
RUNMODE  ?= shell
ARGS     ?=
SCRIPT   ?= $(wildcard test.script)
RUNFLAGS ?=
TESTFLAGS ?=
TESTCHECK ?=
PYTHON   ?= python3
HCC      := $(PYTHON) $(SDK)/c/bin/hcc
RUN816   := $(PYTHON) $(SDK)/tools/run816.py --horizon $(HORIZON) --mode $(RUNMODE) \
            $(if $(ARGS),--args '$(ARGS)') $(if $(SCRIPT),--script $(SCRIPT))
CARD     := $(HORIZON)/build/sd/SYSTEM/HORIZON.SYS

# the compiler (and model) the program was built with: another one rebuilds it
CCSTAMP  := build/.cc-$(or $(HZ_CC),default)$(if $(MODEL),-$(MODEL))$(if $(HZ_CODE),-$(HZ_CODE))

all: $(PRG)

$(CCSTAMP):
	@mkdir -p build
	@rm -f build/.cc-*
	@touch $@

$(PRG): $(SRCS) $(wildcard *.h) $(MAKEFILE_LIST) $(CCSTAMP)
	$(HCC) $(if $(MODEL),--model $(MODEL)) $(HCCFLAGS) -o $@ $(SRCS)

# the SD card the emulator boots (the whole of Horizon)
$(CARD):
	$(MAKE) -C $(HORIZON)

run: $(PRG) $(CARD)
	$(RUN816) $(PRG) --out build/run $(RUNFLAGS)

test: $(PRG) $(CARD)
	$(RUN816) $(PRG) --out build/test $(RUNFLAGS) $(TESTFLAGS)
	$(if $(TESTCHECK),$(TESTCHECK))

clean:
	rm -rf build $(PRG) $(PRG:.PRG=.PRX)

.PHONY: all run test clean

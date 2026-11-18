# Echo - a TCP client (Horizon 0.22, Atari816): ECHO.PRG from main.s.
#
#   make            build ECHO.PRG
#   make run        run it in the emulator against an echo server on this PC (build/run/)
#   make test       two runs: a line sent to the echo server and its answer printed, then
#                   a port nobody listens on (E_REFUSED)
#   make clean
#
# The emulator's --net makes tcp://host:port a real connection of this PC, as the gateway
# (tools/atari816-link) does on the real machine. echoserver.py runs a small echo server
# on a free port while the emulator runs ("{port}" in the command becomes that port).
#
# Pass HORIZON=... (and SDK=...) when your Horizon tree is somewhere else.

NAME    := echo
RUNMODE := shell
UI      := 0

HORIZON ?= ../../../horizon
SDK     ?= ../..
CA65    ?= ca65
LD65    ?= ld65

PRG     := $(shell echo $(NAME) | tr a-z A-Z).PRG
SRCS    := main.s $(filter-out main.s,$(wildcard *.s))
OBJS    := $(patsubst %.s,build/%.o,$(SRCS))
LIBS    := $(HORIZON)/build/ulib.o $(if $(filter 1,$(UI)),$(HORIZON)/build/ui.lib)
CARD    := $(HORIZON)/build/sd/SYSTEM/HORIZON.SYS
RUN816  := python3 $(SDK)/tools/run816.py --horizon $(HORIZON) --mode $(RUNMODE)
SERVE   := python3 echoserver.py --run
SECS    := 8

all: $(PRG)

build/%.o: %.s $(wildcard *.inc) $(HORIZON)/user/horizon.inc | build
	$(CA65) -I . -I $(HORIZON)/user -o $@ $<

$(PRG): $(OBJS) $(LIBS) $(HORIZON)/user/prog.cfg
	$(LD65) -C $(HORIZON)/user/prog.cfg -o $@ $(OBJS) $(LIBS)

$(HORIZON)/build/ulib.o $(HORIZON)/build/ui.lib:
	$(MAKE) -C $(HORIZON) build/ulib.o build/ui.lib

$(CARD):
	$(MAKE) -C $(HORIZON)

build:
	mkdir -p build

run: $(PRG) $(CARD)
	$(SERVE) $(RUN816) $(PRG) --net --args 'tcp://127.0.0.1:{port} "Hello there"' \
	    --seconds $(SECS) --shot 4 --out build/run

test: $(PRG) $(CARD)
	$(SERVE) $(RUN816) $(PRG) --net --args 'tcp://127.0.0.1:{port} "Hello there"' \
	    --seconds $(SECS) --shot 4 --out build/test \
	    --expect 'echo: connected to tcp://127.0.0.1:' --expect 'answer: Hello there'
	@echo "PASS  the line came back from the echo server"
	$(RUN816) $(PRG) --net --args tcp://127.0.0.1:1 --seconds $(SECS) --out build/testrefused \
	    --expect 'echo: refused or unreachable'
	@echo "PASS  a port nobody listens on: E_REFUSED"

clean:
	rm -rf build $(PRG)

.PHONY: all run test clean

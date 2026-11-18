# Fetch - print a URL on the console (Horizon 0.22, Atari816): FETCH.PRG from main.s.
#
#   make            build FETCH.PRG
#   make run        fetch a page of the test web folder in the emulator (build/run/)
#   make test       three runs in the emulator: a page, a missing page (HTTP 404), and
#                   a PC link without the internet service (E_NOSVC)
#   make clean
#
# In the emulator, --net-root DIR stands in for the web: http://host/path is the file
# DIR/host/path (build/www here). On the real machine the gateway (tools/atari816-link)
# fetches real URLs on the PC.
#
# Pass HORIZON=... (and SDK=...) when your Horizon tree is somewhere else.

NAME    := fetch
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
# the command is typed at the shell's prompt: give it time to finish
SECS    := 6

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

# The test web: http://example.test/hello.txt is 40 lines of 27 bytes (1080 bytes:
# three reads of 512 bytes, the last one short).
build/www/example.test/hello.txt: | build
	mkdir -p build/www/example.test
	python3 -c "import sys; \
	sys.stdout.write(''.join('Line %02d of the fetch test.\n' % i for i in range(1, 41)))" > $@

run: $(PRG) $(CARD) build/www/example.test/hello.txt
	$(RUN816) $(PRG) --net-root build/www --args http://example.test/hello.txt \
	    --seconds $(SECS) --shot 3 --out build/run

test: $(PRG) $(CARD) build/www/example.test/hello.txt
	$(RUN816) $(PRG) --net-root build/www --args http://example.test/hello.txt \
	    --seconds $(SECS) --shot 3 --out build/test \
	    --expect 'Line 01 of the fetch test.' --expect 'Line 40 of the fetch test.' \
	    --expect 'fetch: 1080 bytes'
	@echo "PASS  a page: all 1080 bytes printed"
	$(RUN816) $(PRG) --net-root build/www --args http://example.test/missing.txt \
	    --seconds $(SECS) --out build/test404 \
	    --expect 'fetch: HTTP status 404'
	@echo "PASS  a missing page: HTTP status 404 (from X of the failed open)"
	$(RUN816) $(PRG) --net --args http://example.test/hello.txt \
	    --seconds $(SECS) --out build/testnosvc \
	    --expect 'fetch: no internet service'
	@echo "PASS  no web service on the PC link: E_NOSVC"

clean:
	rm -rf build $(PRG)

.PHONY: all run test clean

# cc65 C for Horizon (Atari816) - feasibility spike.
#
#   make                 the runtime library and the three programs (HELLO, CWIN, CBENCH)
#   make run-hello       run them in emu816 (sdk/tools/run816.py), output in build/run-*
#   make run-window
#   make run-bench
#   make run-ui run-rtcheck run-membench   (C + ui.lib; 32-bit mul/div check; memcpy speed)
#   make zpcheck         scan the linked programs for absolute accesses to $00xx (see below)
#   make CPU=6502 ...    compile C (and the runtime: LIBCPU) for another cc65 CPU (default
#                        65c02; 65816 gives the same code as 65c02)
#   make FASTRT=1 ...    link the 65816-tuned runtime routines in fastrt/ first
#
# The runtime library is cc65's own libsrc/runtime + libsrc/common (commit 547d923, the
# installed cc65), vendored in cc65-libsrc/, assembled/compiled for target "none", with
# the files in rt/ replacing their namesakes (65816 fixes), plus hz/ (syscall gate, write).

HORIZON ?= ../../../horizon
SDK     ?= ../..
CC65    ?= cc65
CA65    ?= ca65
LD65    ?= ld65
AR65    ?= ar65
# cc65's include/ and asminc/ (cc65 could not find them by itself here)
CC65_HOME ?= $(abspath $(dir $(shell command -v $(CC65)))../share/cc65)
export CC65_HOME

CPU     ?= 65c02
LIBCPU  ?= $(CPU)
CFLAGS  ?= -Oirs
FASTRT  ?= 0

B       := build/$(CPU)$(if $(filter 1,$(FASTRT)),-fast)
LB      := build/lib-$(LIBCPU)
LIB     := build/hz-$(LIBCPU).lib

# ---- runtime library ---------------------------------------------------------------
UPSTREAM := $(wildcard cc65-libsrc/runtime/*.s cc65-libsrc/common/*.s cc65-libsrc/common/*.c)
OVERRIDE := $(wildcard rt/*.s)
LIBSRC   := $(filter-out $(addprefix %/,$(notdir $(OVERRIDE))),$(UPSTREAM)) $(OVERRIDE) \
            hz/hzsys.s hz/write.c
LIBOBJ   := $(addprefix $(LB)/,$(addsuffix .o,$(basename $(notdir $(LIBSRC)))))
vpath %.s cc65-libsrc/runtime cc65-libsrc/common
vpath %.c cc65-libsrc/common

$(LB)/%.o: rt/%.s | $(LB)
	$(CA65) -t none --cpu $(LIBCPU) -o $@ $<
$(LB)/%.o: hz/%.s | $(LB)
	$(CA65) -t none --cpu $(LIBCPU) -o $@ $<
$(LB)/%.o: hz/%.c | $(LB)
	$(CC65) -t none --cpu $(LIBCPU) -Or -I hz -o $(LB)/$*.s $<
	$(CA65) -t none --cpu $(LIBCPU) -o $@ $(LB)/$*.s
$(LB)/%.o: %.s | $(LB)
	$(CA65) -t none --cpu $(LIBCPU) -o $@ $<
$(LB)/%.o: %.c | $(LB)
	$(CC65) -t none --cpu $(LIBCPU) -Or -o $(LB)/$*.s $<
	$(CA65) -t none --cpu $(LIBCPU) -o $@ $(LB)/$*.s

$(LIB): $(LIBOBJ)
	rm -f $@
	@echo "ar65 a $@ ($(words $(LIBOBJ)) modules)"; $(AR65) a $@ $(LIBOBJ)

# ---- programs ----------------------------------------------------------------------
CRT0    := $(B)/crt0.o
FASTOBJ := $(if $(filter 1,$(FASTRT)),$(patsubst fastrt/%.s,$(B)/fast_%.o,$(wildcard fastrt/*.s)))

$(B)/crt0.o: hz/crt0.s | $(B)
	$(CA65) --cpu 65816 -o $@ $<
$(B)/fast_%.o: fastrt/%.s | $(B)
	$(CA65) --cpu 65816 -o $@ $<
define PROG_C
$(B)/%.o: $(1)/%.c hz/horizon.h | $(B)
	$(CC65) -t none --cpu $(CPU) $(CFLAGS) -I hz -o $(B)/$$*.s $$<
	$(CA65) -t none --cpu $(CPU) -o $$@ $(B)/$$*.s
endef
$(foreach d,hello window bench,$(eval $(call PROG_C,$(d))))

$(B)/HELLO.PRG:  $(CRT0) $(B)/hello.o $(FASTOBJ) $(LIB) hz/horizon.cfg
	$(LD65) -C hz/horizon.cfg -m $(@:.PRG=.map) -o $@ $(CRT0) $(B)/hello.o $(FASTOBJ) $(LIB)
$(B)/CWIN.PRG:   $(CRT0) $(B)/window.o $(FASTOBJ) $(LIB) hz/horizon.cfg
	$(LD65) -C hz/horizon.cfg -m $(@:.PRG=.map) -o $@ $(CRT0) $(B)/window.o $(FASTOBJ) $(LIB)
$(B)/CBENCH.PRG: $(CRT0) $(B)/bench_hz.o $(B)/bench.o $(FASTOBJ) $(LIB) hz/horizon.cfg
	$(LD65) -C hz/horizon.cfg -m $(@:.PRG=.map) -o $@ $(CRT0) $(B)/bench_hz.o $(B)/bench.o $(FASTOBJ) $(LIB)

# C + the controls library: ui.lib and ulib.o from the Horizon tree, after the C runtime
UILIBS := $(HORIZON)/build/ui.lib $(HORIZON)/build/ulib.o
$(B)/uibind.o: hz/uibind.s | $(B)
	$(CA65) --cpu 65816 -o $@ $<
$(B)/CUI.PRG:    $(CRT0) $(B)/uidemo.o $(B)/uibind.o $(FASTOBJ) $(LIB) hz/horizon.cfg
	$(LD65) -C hz/horizon.cfg -m $(@:.PRG=.map) -o $@ $(CRT0) $(B)/uidemo.o $(B)/uibind.o $(FASTOBJ) $(LIB) $(UILIBS)

$(B)/RTCHECK.PRG: $(CRT0) $(B)/rtcheck.o $(FASTOBJ) $(LIB) hz/horizon.cfg
	$(LD65) -C hz/horizon.cfg -m $(@:.PRG=.map) -o $@ $(CRT0) $(B)/rtcheck.o $(FASTOBJ) $(LIB)
run-rtcheck: $(B)/RTCHECK.PRG
	$(RUN816) $< --mode shell --seconds 30 --out $(B)/run-rtcheck --expect 'rtcheck 1970914798 1696788329 248557 1069850960'

$(B)/MEMBENCH.PRG: $(CRT0) $(B)/membench.o $(FASTOBJ) $(LIB) hz/horizon.cfg
	$(LD65) -C hz/horizon.cfg -m $(@:.PRG=.map) -o $@ $(CRT0) $(B)/membench.o $(FASTOBJ) $(LIB)
run-membench: $(B)/MEMBENCH.PRG
	$(RUN816) $< --mode shell --seconds 20 --out $(B)/run-membench --expect 'check 61765'

PROGS := $(B)/MEMBENCH.PRG $(B)/RTCHECK.PRG $(B)/HELLO.PRG $(B)/CWIN.PRG $(B)/CBENCH.PRG $(B)/CUI.PRG
all: $(PROGS)

$(B) $(LB):
	mkdir -p $@

RUN816 := python3 $(SDK)/tools/run816.py --horizon $(HORIZON)

run-hello: $(B)/HELLO.PRG
	$(RUN816) $< --mode shell --args 'one "two words" three' --shot 1 --out $(B)/run-hello \
	    --expect 'Hello from C' --expect 'argv[2] = two words'
run-window: $(B)/CWIN.PRG
	$(RUN816) $< --script window/test.script --out $(B)/run-window --expect 'CWIN: closed'
run-ui: $(B)/CUI.PRG
	$(RUN816) $< --script window/ui.script --out $(B)/run-ui --expect 'CUI: Clicked 2 times' --expect 'CUI: closed'
run-bench: $(B)/CBENCH.PRG
	$(RUN816) $< --mode shell --seconds 60 --out $(B)/run-bench --expect 'bench done'

zpcheck: $(PROGS)
	for p in $(PROGS); do python3 tools/zpcheck.py $$p $${p%.PRG}.map; done

clean:
	rm -rf build

.PHONY: all run-membench run-rtcheck run-hello run-window run-ui run-bench zpcheck clean

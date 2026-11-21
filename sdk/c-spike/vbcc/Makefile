# vbcc 65816 C for Horizon (Atari816) - feasibility spike.
#
#   make                 HELLO.PRG, CWIN.PRG, CBENCH.PRG in build/
#   make run-hello       run them in emu816 (sdk/tools/run816.py), output in build/run-*
#   make run-window
#   make run-bench
#   make OPT="..."       other vbcc optimisation flags (default: OPT below)
#   make MODEL=tiny ...  vbcc's tiny data model (see below); build/tiny
#   make FASTRT=1 ...    link the 65816-tuned runtime routines in fastrt/ first; build/*-fast
#
# Toolchain: toolchain/vbcc (see README in the report): vbcc65816 and vc built from the
# vbcc source, vasm6502_oldstyle, vlink and the 65816-sim C library from vbcc65816_r2.
# A program is linked three times by vlink as a raw binary (at banks 0, $5A, $A5) and
# hz/mko65.py turns the three into the o65 file Horizon's loader takes.

HORIZON ?= ../../../horizon
SDK     ?= ../..
VBCC    ?= $(abspath toolchain/vbcc)
export VBCC
export PATH := $(VBCC)/bin:$(PATH)

# MODEL=large (default): vbcc's large data model, 32-bit data pointers, data in the code
#   bank, locals on the stack in bank 0 (hz/horizon.cmd, hz/startup.s, libvc).
# MODEL=tiny: -mtiny, 16-bit data pointers, all data + stack in the window (bank 0), DBR = 0
#   (hz/horizon-tiny.cmd, hz/startup-tiny.s, libvcs).
MODEL   ?= large
OPT     ?= -O3 -speed
LIBDIR  := $(VBCC)/targets/65816-sim/lib
ifeq ($(MODEL),tiny)
MFLAGS  := -mtiny
LIBS    ?= -lvcs
LDSCRIPT := hz/horizon-tiny.cmd
STARTUP := startup-tiny
else
MFLAGS  :=
LIBS    ?= -lvc
LDSCRIPT := hz/horizon.cmd
STARTUP := startup
endif
CFLAGS  ?= -Ihz $(MFLAGS) $(OPT)

B       := build/$(MODEL)$(if $(filter 1,$(FASTRT)),-fast)
VC      := vc +hz/vc.config
VASM    := vasm6502_oldstyle -816 -vobj3 -quiet -nowarn=62 -opt-branch -ldots -Fvobj
VLINK   := vlink -b rawbin1 -nowarn=22 -Cvbcc -gc-all -T $(LDSCRIPT) -L$(LIBDIR)

FASTRT  ?= 0
RT      := $(B)/$(STARTUP).o $(B)/hzsys.o $(B)/write.o \
           $(if $(filter 1,$(FASTRT)),$(patsubst fastrt/%.s,$(B)/%.o,$(wildcard fastrt/*.s)))

$(B)/%.o: hz/%.s | $(B)
	$(VASM) $< -o $@
$(B)/%.o: fastrt/%.s | $(B)
	$(VASM) $< -o $@
$(B)/%.o: hz/%.c hz/horizon.h | $(B)
	$(VC) $(CFLAGS) -c $< -o $@
define PROG_C
$(B)/%.o: $(1)/%.c hz/horizon.h | $(B)
	$(VC) $(CFLAGS) -c $$< -o $$@
	$(VC) $(CFLAGS) -S $$< -o $(B)/$$*.s
endef
$(foreach d,hello window bench test,$(eval $(call PROG_C,$(d))))

# link at three banks, then o65 (startup.o first: the entry is text $0100)
define LINK
	$(VLINK) -DBASE=0        -M$(1).0.map -o $(1).0.bin $(2) $(LIBS)
	$(VLINK) -DBASE=0x5a0000 -M$(1).a.map -o $(1).a.bin $(2) $(LIBS)
	$(VLINK) -DBASE=0xa50000 -M$(1).b.map -o $(1).b.bin $(2) $(LIBS)
	python3 hz/mko65.py $(1) $(1).0.bin $(1).0.map $(1).a.bin $(1).a.map $(1).b.bin $(1).b.map $(3)
endef

$(B)/HELLO.PRG: $(RT) $(B)/hello.o $(LDSCRIPT) hz/mko65.py
	$(call LINK,$@,$(RT) $(B)/hello.o)
$(B)/CWIN.PRG: $(RT) $(B)/window.o $(LDSCRIPT) hz/mko65.py
	$(call LINK,$@,$(RT) $(B)/window.o)
$(B)/CBENCH.PRG: $(RT) $(B)/bench_hz.o $(B)/bench.o $(LDSCRIPT) hz/mko65.py
	$(call LINK,$@,$(RT) $(B)/bench_hz.o $(B)/bench.o)

$(B)/MULTEST.PRG: $(RT) $(B)/multest.o $(LDSCRIPT) hz/mko65.py
	$(call LINK,$@,$(RT) $(B)/multest.o)

all: $(B)/HELLO.PRG $(B)/CWIN.PRG $(B)/CBENCH.PRG

$(B):
	mkdir -p $@

RUN816 := python3 $(SDK)/tools/run816.py --horizon $(HORIZON)

run-hello: $(B)/HELLO.PRG
	$(RUN816) $< --mode shell --args 'one "two words" three' --shot 2 --out $(B)/run-hello \
	    --expect 'Hello from C' --expect '&local passed: 42 (42)  local array: 6 (6)  global: 100 (100)' \
	    --expect 'sum 124716 (124716)' --expect ' ok'
run-window: $(B)/CWIN.PRG
	$(RUN816) $< --script window/test.script --out $(B)/run-window --expect 'CWIN: closed'
run-bench: $(B)/CBENCH.PRG
	$(RUN816) $< --mode shell --seconds 40 --out $(B)/run-bench --expect 'bench done' \
	    --expect 'check 1899' --expect 'check 27824' --expect 'check 1071602483' \
	    --expect 'check 17711' --expect 'check 3160' --expect 'check 4275534039'

# (d) C + ulib (ca65 code, an ld65 object) as a block at the start of the text, large model
# only (ulib wants DBR = the code bank). asmlib/blob.s + ulib.o -> ld65 o65 -> raw block.
CA65    ?= ca65
LD65    ?= ld65
$(B)/blob.o65: asmlib/blob.s asmlib/blob.cfg $(HORIZON)/build/ulib.o | $(B)
	$(CA65) --cpu 65816 -I $(HORIZON)/user -o $(B)/blob.o asmlib/blob.s
	$(LD65) -C asmlib/blob.cfg -m $(B)/blob.ld65map -o $@ $(B)/blob.o $(HORIZON)/build/ulib.o
build/blob.bin: $(B)/blob.o65
	python3 tools/o65blob.py $< build/blob.bin build/blob.banks
$(B)/ulibwrap.o: asmlib/ulibwrap.s build/blob.bin | $(B)
	$(VASM) $< -o $@
$(B)/ULIBDEMO.PRG: $(RT) $(B)/ulibwrap.o $(B)/ulibdemo.o $(LDSCRIPT) hz/mko65.py
	$(call LINK,$@,$(B)/ulibwrap.o $(RT) $(B)/ulibdemo.o,build/blob.banks)
run-ulib: $(B)/ULIBDEMO.PRG
	$(RUN816) $< --mode shell --seconds 3 --out $(B)/run-ulib \
	    --expect 'ULIB from C: 12345 $$BEEF, a string in the code bank, a local'

MULCHECK := D3DBE645 1C011DC3 216DA321 1FCFAD8F 00000006 0000C3B6 00011CE1 0000DEAD FFFE1DC0 FFFFFCEB 4166E5F8 00000000
run-multest: $(B)/MULTEST.PRG
	$(RUN816) $< --mode shell --seconds 3 --out $(B)/run-multest --expect '$(MULCHECK)' \
	    --expect '3554403909 4275534039 3735928559'

clean:
	rm -rf $(B)

.PHONY: all run-hello run-window run-bench run-multest run-ulib clean

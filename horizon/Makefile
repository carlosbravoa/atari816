# Horizon: kernel + programs for the Atari816.
#   make          build/sd    the normal SD card: SYSTEM/HORIZON.SYS, SYSTEM/INIT.PRG (runs the
#                             Desktop), the system programs in SYSTEM, the tests in SYSTEM/TESTS,
#                             the applications in BIN/*.PRG, README.TXT
#                 build/tsd   the test SD card: the same, but its INIT runs SELFTEST and exits
#   make run      the normal SD card in emu816
#   make test     1. SELFTEST on the test card at console speeds 0, 90 and 2000 us/byte
#                 2. a scripted shell session (tests/shell.keys) on the normal card
#                 each compared with tests/*.txt by tests/compare.py
CA65   ?= ca65
LD65   ?= ld65
AR65   ?= ar65
EMUDIR ?= ../emu
EMU    ?= $(EMUDIR)/emu816
# EMUFLAGS="--rev 7": test without the blitter (REV $07: the software drawing paths)
EMUFLAGS ?=
B      := build
SD     := $(B)/sd
TSD    := $(B)/tsd

# The card (0.13): /SYSTEM the kernel, INIT and the system programs; /SYSTEM/TESTS the test
# and demo programs (the shell finds them too); /BIN the applications (lowercase source names).
PROGS  := wfiles term paint settings cat files dir mem edit basic sheet
PROGS  += calc solitair quabrick
SYSPROGS := desk sh about
TESTPROGS := selftest bench mouse mtest wdemo hello count spin tick regs crash ping pong keys ftest leak hog ktest stest gtest
# programs linked with the controls library (build/ui.lib from user/ui*.s, API in user/ui.inc)
UIPROGS := edit wfiles desk paint settings basic sheet about
UIPROGS += calc solitair quabrick
# (0.14) the shell links the library for the date (uidate.s)
UIPROGS += sh
UISRC  := $(wildcard user/ui*.s)
# Write (the word processor): one assembly unit of user/write*.s, its type faces made from
# the console font (tools/mkwfont.py)
PROGS  += write
UIPROGS += write

# self test keys: 'a' 1.0-1.2 s with F12 (system key NMI) in between. SELFTEST holds the
# keyboard from its start, so they queue up whenever they come; KEYS reads them at the end.
TKEYS  := 1000:04:1,1100:45:1,1150:45:0,1200:04:0
SPEEDS := 0 90 2000
# shell session: console speeds and emulated length
SHSPEEDS := 0 2000
SHSECS := 185
# screen pictures: shot times (s) in the tests/screen.keys session; md5 in tests/pictures
SHOTS  := 13.5 20 22 26.5
# browser pictures: shot times in the tests/browse.keys session
BSHOTS := 7 14 22 32.5 41.5 44 47.5 1.9
# window system pictures: shot times in the tests/wdemo.keys session
WSHOTS := 6.5 7.8 9 10.5 11.5 13
# Desktop pictures (DESK=1: no NODESK): shot times in the tests/desk.keys session
DSHOTS := 5 7 10 15.8 17.2 19 11.3
# Paint (text shell) and Settings (Desktop) sessions: shot times
PSHOTS := 12.1 13.2 15.4 16.4 17.9 21.9 24.5 25.9
SSHOTS := 8.8 10.4 12.4 17.2 20.5
# Settings, the Classic Atari page (tests/classic.keys; the card gets sdfiles/atari.ini, a
# sample of the I/O processor's file): shot times; /atari.ini must then be tests/atari-ini.txt
CLSHOTS := 7 9.8 12 14.5
# Files (Desktop session; it moves, copies, renames and deletes on its copy of the card; 16 shots: emu816's most)
FSHOTS := 5.4 10.6 11.2 15.8 17.6 19.0 19.8 22 26.6 29.5 32.5 35.5 39.5 42.2 43.9 45.5
# BASIC: the -t script run (tests/basic-t.keys), emulated seconds; the picture session
# (tests/basic.keys) shot times. Its pictures are the same with and without the blitter.
BASSECS := 160
BASSHOTS := 16.2 18.6 31.0 36.0 38.5
# Edit pictures: shot times in the tests/edit.keys session
ESHOTS := 8.9 9.9 12.0 14.2 16.4 19.6
# Sheet: the -t script run (tests/sheet-t.keys, tests/sheet.sht), emulated seconds; the picture
# session (tests/sheet.keys) shot times. Its pictures are the same with and without the blitter.
SHTSECS := 24
SHTSHOTS := 7.0 11.0 13.8 15.6 17.0 18.6
# Write: the -t script run (tests/write-t.keys, tests/write.wt), emulated seconds; the picture
# session (tests/write.keys) and the editing session (tests/writee.keys, it saves W1.MD and
# NOTES.md) shot
# times. Their pictures are the same with and without the blitter.
WRSECS := 30
WRSHOTS := 6.0 8.0 10.5 13.0 21.0 24.0 31.0 33.2 35.5
WESHOTS := 18.0 34.0 39.5 41.0 43.0
# (without the blitter Edit is slower: the same session, later states, its own md5)
EMD5   := $(if $(findstring --rev 7,$(EMUFLAGS)),edit-rev7.md5,edit.md5)
# Edit, second session (tests/editw.keys: undo, word wrap, Find / Replace, ...): shot times
# (the same pictures with and without the blitter); the file it saves must be tests/editw.txt
EWSHOTS := 15.9 17.6 19.6 21.0 23.2 24.1 27.3 29.7 32.2
# The Desktop's system functions (tests/system.keys, made from tests/system.src; the card gets
# tests/system.programs as /SYSTEM/PROGRAMS): out-of-memory alerts, Force quit, one About,
# Shut down (cancelled by a program, then done), the "safe" screen, Restart, /Desktop icons
SYSSHOTS := 6.3 11 13 15.5 18.5 21.5 28.5 31 34 37.5 42 46 49 52 56
# Keyboard menus, Alt+Tab, ctrl+W, Alt+F4, menu check marks, dimmed items and shortcuts
# (tests/kmenu.keys)
KMSHOTS := 10.5 13 14.5 15.5 18 24.7 25.5 27.9 29.1 30.5 31.5 32.5
# (0.14) window buttons, the Windows menu, Alt+Tab with a minimized window (tests/wins.keys,
# made from tests/wins.src)
WINSHOTS := 6.5 8.5 10.5 14.5 16.0 17.5 20.0
# (0.14) the Desktop: shortcuts (File > Add to desktop, a drag from Files), the Atari icon (a
# drop, its panel, Eject), the clock, icons moved, the right-click menu, Tidy up, Delete,
# About's date (tests/desk14.keys, made from tests/desk14.src; the card gets /GAME.ATR)
D14SHOTS := 16 21.5 23 24.5 28 29.5 33 34.5 36 38 39.5 41 45
# (0.15) pop-up menus: the Atari icon's (Attach disk... with the dialog's filter and type-
# ahead, an Eject line), Files' rows and background, a text field's, the desktop's, a
# /Desktop icon's (New folder..., Rename...), Edit's text, the menu key (tests/desk15.keys,
# made from tests/desk15.src; the card gets /GAME.ATR)
D15SHOTS := 6.0 8.5 11.5 14.0 16.8 18.3 20.5 24.0 27.5 31.0 35.0 38.0
# (0.18) the Atari panel's attach buttons and menu; a cartridge attached or ejected is a power
# cycle (the executable ejected, classic_boot CB_STAY: the desktop stays) (tests/desk18.keys,
# made from tests/desk18.src; its classic-machine ops compared with tests/desk18.err)
D18SHOTS := 10.0 14.5 17.0 19.0 26.0
# (0.17) STEST: without Lau (--rev 9 or lower) the short output and no Lau writes
NOLAU   = $(or $(findstring --rev 9,$(EMUFLAGS)),$(findstring --rev 8,$(EMUFLAGS)),$(findstring --rev 7,$(EMUFLAGS)))
STESTTXT = $(if $(NOLAU),stest-nolau.txt,stest.txt)
STESTERR = $(if $(NOLAU),/dev/null,tests/stest.err)
# (0.18) GTEST: REV $0B (sprites, scrolling), $09-$0A (lists, raster, no sprites), below (none)
OLD8    = $(or $(findstring --rev 8,$(EMUFLAGS)),$(findstring --rev 7,$(EMUFLAGS)))
NOSPR   = $(or $(NOLAU),$(findstring --rev 10,$(EMUFLAGS)))
GTESTTXT = $(if $(OLD8),gtest-r8.txt,$(if $(NOSPR),gtest-r10.txt,gtest.txt))
# (About says how it draws: without the blitter, its own md5; so do the next two)
# (0.18) and boards without Lau (REV $08, $09): About says "Sound: POKEY 2": $(1)-rev9.md5 where
# the session shows About (only that line differs from the default)
REV9F   = $(if $(OLD89),$(if $(wildcard tests/pictures/$(1)-rev9.md5),$(1)-rev9.md5,$(1).md5),$(1).md5)
OLD89   = $(or $(findstring --rev 9,$(EMUFLAGS)),$(findstring --rev 8,$(EMUFLAGS)))
REV7    = $(if $(findstring --rev 7,$(EMUFLAGS)),$(1)-rev7.md5,$(call REV9F,$(1)))
DMD5    = $(call REV7,desk)

KSRC   := $(wildcard kernel/*.s kernel/*.inc)
UPPER   = $(shell echo $(1) | tr a-z A-Z)
BINS   := $(foreach p,$(PROGS),$(SD)/BIN/$(call UPPER,$(p)).PRG) \
          $(foreach p,$(SYSPROGS),$(SD)/SYSTEM/$(call UPPER,$(p)).PRG) \
          $(foreach p,$(TESTPROGS),$(SD)/SYSTEM/TESTS/$(call UPPER,$(p)).PRG) \
          $(SD)/SYSTEM/PROGRAMS $(SD)/SYSTEM/ICONS

all: $(SD)/SYSTEM/HORIZON.SYS $(SD)/SYSTEM/INIT.PRG $(BINS) $(SD)/README.TXT $(SD)/LONG.TXT $(SD)/BLUE.XEX $(B)/tree.stamp $(B)/bas.stamp $(TSD)/SYSTEM/INIT.PRG

$(B) $(SD)/SYSTEM $(SD)/BIN $(SD)/SYSTEM/TESTS:
	mkdir -p $@

# the Desktop's Programs menu: "Title=/path" lines
$(SD)/SYSTEM/PROGRAMS: sdfiles/PROGRAMS | $(SD)/SYSTEM
	cp $< $@

# (0.14) the Desktop's icons: sdfiles/icons.txt (text art) -> /SYSTEM/ICONS (32 x 32 each)
# and user/icons.inc (their numbers, ICO_*)
$(SD)/SYSTEM/ICONS: sdfiles/icons.txt tools/mkicons.py | $(SD)/SYSTEM
	python3 tools/mkicons.py $< $@ $(B)/icons.inc.tmp && rm $(B)/icons.inc.tmp
user/icons.inc: sdfiles/icons.txt tools/mkicons.py
	python3 tools/mkicons.py $< $(B)/ICONS.tmp $@ && rm $(B)/ICONS.tmp

kernel/font.inc: kernel/font8x12.txt tools/mkfont.py
	python3 tools/mkfont.py $< $@ 12

kernel/pointer_drag.inc: kernel/pointer_drag.txt tools/mkpointer.py
	python3 tools/mkpointer.py $< $@

kernel/pointer_cross.inc: kernel/pointer_cross.txt tools/mkpointer.py
	python3 tools/mkpointer.py $< $@

kernel/pointer.inc: kernel/pointer.txt tools/mkpointer.py
	python3 tools/mkpointer.py $< $@

# the resize pointers: only their 21 rows of 6 bytes (mouse.s adds the transparent rest)
kernel/pointer_hsize.inc kernel/pointer_vsize.inc: kernel/pointer_%.inc: kernel/pointer_%.txt tools/mkpointer.py
	python3 tools/mkpointer.py $< $@.tmp && head -n 22 $@.tmp | cut -d, -f1-6 > $@ && rm $@.tmp

kernel/uifont.inc: kernel/font8x12.txt tools/mkuifont.py
	python3 tools/mkuifont.py $< $@

kernel/palette.inc: tools/mkpalette.py
	python3 tools/mkpalette.py $@

$(SD)/SYSTEM/HORIZON.SYS: $(KSRC) user/version.inc kernel/font.inc kernel/pointer.inc kernel/pointer_drag.inc kernel/pointer_cross.inc kernel/pointer_hsize.inc kernel/pointer_vsize.inc kernel/uifont.inc kernel/palette.inc kernel/kernel.cfg | $(SD)/SYSTEM $(B)
	$(CA65) -I kernel -I user -o $(B)/horizon.o kernel/horizon.s
	$(CA65) -I kernel -I user -o $(B)/k2.o kernel/k2.s
	$(LD65) -C kernel/kernel.cfg -m $(B)/horizon.map -o $(B)/horizon.sys $(B)/horizon.o $(B)/k2.o
	@# (0.18) the I/O processor reads at most $$FF00 bytes of the file (bank $$01 image + k2.s)
	@python3 tools/kspace.py $(B)/horizon.map $(B)/horizon.sys
	cp $(B)/horizon.sys $@

$(B)/ulib.o: user/ulib.s user/horizon.inc user/version.inc | $(B)
	$(CA65) -I user -o $@ $<

$(SD)/SYSTEM/INIT.PRG: user/init.s user/horizon.inc user/version.inc user/prog.cfg $(B)/ulib.o | $(SD)/SYSTEM
	$(CA65) -I user -o $(B)/init.o $<
	$(LD65) -C user/prog.cfg -o $@ $(B)/init.o $(B)/ulib.o

$(B)/ui.lib: $(UISRC) user/ui.inc user/horizon.inc user/version.inc user/icons.inc | $(B)
	for f in $(UISRC); do $(CA65) -I user -o $(B)/$$(basename $$f .s).o $$f || exit 1; \
	  $(AR65) a $@ $(B)/$$(basename $$f .s).o || exit 1; done

# programs whose relocation entries that add 0 are dropped (tools/o65strip.py)
STRIPPROGS := basic
# PROG_rule: $(1) the file name, $(2) the source name, $(3) the folder on the card
define PROG_rule
$(SD)/$(3)/$(1).PRG: user/$(2).s user/horizon.inc user/version.inc user/prog.cfg $(B)/ulib.o $(if $(filter $(2),$(UIPROGS)),$(B)/ui.lib user/ui.inc) | $(SD)/$(3)
	$(CA65) -I user -o $(B)/$(2).o $$<
	$(LD65) -C user/prog.cfg -o $$@ $(B)/$(2).o $(B)/ulib.o $(if $(filter $(2),$(UIPROGS)),$(B)/ui.lib)
	$(if $(filter $(2),$(STRIPPROGS)),python3 tools/o65strip.py $$@)
endef
$(foreach p,$(PROGS),$(eval $(call PROG_rule,$(call UPPER,$(p)),$(p),BIN)))
$(foreach p,$(SYSPROGS),$(eval $(call PROG_rule,$(call UPPER,$(p)),$(p),SYSTEM)))
$(foreach p,$(TESTPROGS),$(eval $(call PROG_rule,$(call UPPER,$(p)),$(p),SYSTEM/TESTS)))
# BASIC is one assembly unit of several files (and the console font for TEXT). (2.0) Its
# relocation entries that add 0 are dropped (tools/o65strip.py), or the file would be over
# the loader's 64 KB
$(SD)/BIN/BASIC.PRG: $(wildcard user/bas_*.s) kernel/font.inc tools/o65strip.py
# Sheet is one assembly unit of several files
$(SD)/BIN/SHEET.PRG: $(wildcard user/sht_*.s)
$(SD)/BIN/WRITE.PRG: $(wildcard user/write_*.s) user/wfont.inc
user/wfont.inc: kernel/font8x12.txt tools/mkwfont.py
	python3 tools/mkwfont.py $< $@
# the sample document of Write
all: $(SD)/docs/Welcome.md
$(TSD)/SYSTEM/INIT.PRG: $(SD)/docs/Welcome.md
$(SD)/docs/Welcome.md: sdfiles/docs/Welcome.md $(B)/tree.stamp
	mkdir -p $(SD)/docs
	cp $< $@
# Calculator and Solitaire are one assembly unit each
$(SD)/BIN/CALC.PRG: $(wildcard user/calc_*.s)
$(SD)/BIN/SOLITAIR.PRG: $(wildcard user/sol_*.s user/sol_*.inc)
# (0.17) Quabricks: one assembly unit; its art (tools/mkqbart.py) and its samples
# (tools/mkqbsfx.py: /BIN/QUABRICK.SFX) are made here
$(SD)/BIN/QUABRICK.PRG: $(wildcard user/qb_*.s) user/qb_art.inc
user/qb_art.inc: kernel/font8x12.txt tools/mkqbart.py
	python3 tools/mkqbart.py $< $@
all: $(SD)/BIN/QUABRICK.SFX
$(SD)/BIN/QUABRICK.SFX: tools/mkqbsfx.py | $(SD)/BIN
	python3 tools/mkqbsfx.py $@

$(SD)/README.TXT: sdfiles/README.TXT
	cp $< $@
$(SD)/LONG.TXT: sdfiles/LONG.TXT
	cp $< $@
$(SD)/BLUE.XEX: sdfiles/BLUE.XEX
	cp $< $@
# the test tree: long and odd names, a folder of 250 entries (tools/mktree.py)
$(B)/tree.stamp: tools/mktree.py $(SD)/BLUE.XEX $(SD)/SYSTEM/TESTS/HELLO.PRG
	python3 tools/mktree.py $(SD)
	touch $@

# the BASIC examples and self test, the Sheet examples in /programs
BASFILES := $(wildcard sdfiles/programs/*.BAS) $(wildcard sdfiles/programs/*.SHT)
$(B)/bas.stamp: $(BASFILES) $(B)/tree.stamp
	mkdir -p $(SD)/programs
	cp $(BASFILES) $(SD)/programs/
	touch $@

# the test SD card
$(TSD)/SYSTEM/INIT.PRG: user/tinit.s user/horizon.inc user/version.inc user/prog.cfg $(B)/ulib.o \
                        $(SD)/SYSTEM/HORIZON.SYS $(BINS) $(SD)/README.TXT $(SD)/LONG.TXT $(SD)/BLUE.XEX $(B)/tree.stamp $(B)/bas.stamp
	rm -rf build/tsd
	mkdir -p build/tsd/SYSTEM
	cp -r $(SD)/BIN $(SD)/README.TXT $(SD)/LONG.TXT $(SD)/BLUE.XEX $(SD)/carts $(SD)/disks $(SD)/docs $(SD)/many $(SD)/programs $(TSD)/
	cp -r $(SD)/SYSTEM/HORIZON.SYS $(SD)/SYSTEM/TESTS $(SD)/SYSTEM/ICONS $(TSD)/SYSTEM/
	$(CA65) -I user -o $(B)/tinit.o $<
	$(LD65) -C user/prog.cfg -o $@ $(B)/tinit.o $(B)/ulib.o

$(EMU):
	$(MAKE) -C $(EMUDIR)

run: all $(EMU)
	$(EMU) --sd $(SD) $(SD)/SYSTEM/HORIZON.SYS

test: all $(EMU)
	@set -e; for cu in $(SPEEDS); do \
	  rm -rf build/run-sd; cp -r $(TSD) build/run-sd; \
	  $(EMU) $(EMUFLAGS) --headless --sd build/run-sd --console-us $$cu --max-seconds 120 --keys $(TKEYS) \
	      $(TSD)/SYSTEM/HORIZON.SYS > $(B)/selftest-$$cu.out 2> $(B)/selftest-$$cu.err || echo "emu816 exit $$?" >> $(B)/selftest-$$cu.out; \
	  if python3 tests/compare.py tests/selftest.txt $(B)/selftest-$$cu.out; then \
	    echo "PASS  selftest, console $$cu us/byte"; \
	  else echo "FAIL  selftest, console $$cu us/byte ($(B)/selftest-$$cu.out)"; exit 1; fi; \
	done
	@set -e; for cu in $(SHSPEEDS); do \
	  rm -rf build/run-sd; cp -r $(SD) build/run-sd; touch build/run-sd/SYSTEM/NODESK; \
	  $(EMU) $(EMUFLAGS) --headless --sd build/run-sd --console-us $$cu --max-seconds $(SHSECS) \
	      --keys $$(python3 tests/keyscript.py tests/shell.keys) \
	      --mouse $$(python3 tests/keyscript.py --mouse tests/shell.keys) \
	      $(SD)/SYSTEM/HORIZON.SYS > $(B)/shell-$$cu.out 2> $(B)/shell-$$cu.err || echo "emu816 exit $$?" >> $(B)/shell-$$cu.out; \
	  if python3 tests/compare.py tests/shell.txt $(B)/shell-$$cu.out; then \
	    echo "PASS  shell session, console $$cu us/byte"; \
	  else echo "FAIL  shell session, console $$cu us/byte ($(B)/shell-$$cu.out)"; exit 1; fi; \
	done
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) screen 28 $(SHOTS)
	@if diff -u tests/pictures/screen.md5 $(B)/screen.md5; then echo "PASS  screen pictures"; \
	else echo "FAIL  screen pictures (look at $(B)/screen*.ppm, then make pictures)"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS) --log-sound" $(SD) browse 51 $(BSHOTS)
	@if diff -u tests/pictures/browse.md5 $(B)/browse.md5; then echo "PASS  browser pictures"; \
	else echo "FAIL  browser pictures (look at $(B)/browse*.ppm, then make pictures)"; exit 1; fi
	@if diff -u tests/browse.err $(B)/browse.err; then echo "PASS  browser: classic ops (run = start this, and only this)"; \
	else echo "FAIL  browser: classic ops"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) wdemo 15 $(WSHOTS)
	@if diff -u tests/pictures/wdemo.md5 $(B)/wdemo.md5; then echo "PASS  window system pictures"; \
	else echo "FAIL  window system pictures (look at $(B)/wdemo*.ppm, then make pictures)"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) wcopy 6 5.5
	@if diff -u tests/pictures/wcopy.md5 $(B)/wcopy.md5; then echo "PASS  window copy (WD_COPY): the same picture with and without the blitter"; \
	else echo "FAIL  window copy (look at $(B)/wcopy1.ppm, then make pictures)"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) wdraw 9 5.5 7.5
	@if diff -u tests/pictures/wdraw.md5 $(B)/wdraw.md5; then echo "PASS  win_draw expand (WD_EXPAND), keyed blit with a stride (WD_KSBLIT), win_geom: the same with and without the blitter"; \
	else echo "FAIL  win_draw expand / keyed blit / win_geom (look at $(B)/wdraw*.ppm)"; exit 1; fi
	@DESK=1 sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) desk 20 $(DSHOTS)
	@if diff -u tests/pictures/$(DMD5) $(B)/desk.md5; then echo "PASS  desktop pictures"; \
	else echo "FAIL  desktop pictures (look at $(B)/desk*.ppm, then make pictures)"; exit 1; fi
	@python3 -c "import os; from PIL import Image, ImageChops as C; a, b = (Image.open(('$(B)/desk%d.ppm' if os.path.exists('$(B)/desk%d.ppm' % i) else '$(B)/desk%d.png') % i).convert('RGB').crop((0, 32, 1280, 720)) for i in (4, 6)); exit(C.difference(a, b).getbbox() is not None)" \
	&& echo "PASS  desktop: F12 to the classic machine and back leaves the desktop as it was" \
	|| { echo "FAIL  desktop: not the same after F12"; exit 1; }
	@PREP='cp ../../tests/system.programs SYSTEM/PROGRAMS' DESK=1 sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) system 57 $(SYSSHOTS)
	@if diff -u tests/pictures/$(call REV7,system) $(B)/system.md5; then echo "PASS  Desktop: Programs list, out of memory, Force quit, single instance, Shut down, Restart, /Desktop"; \
	else echo "FAIL  Desktop system pictures (look at $(B)/system*.ppm, then make pictures)"; exit 1; fi
	@if grep -q 'SYS_RESTART 1 -> 00' $(B)/system.err && test -e $(B)/run-pic/Desktop/README.TXT; then echo "PASS  Desktop: SYS_SYNC, SYS_RESTART, README.TXT moved into /Desktop"; \
	else echo "FAIL  Desktop: no restart, or README.TXT not in /Desktop ($(B)/system.err)"; exit 1; fi
	@DESK=1 sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) wins 21 $(WINSHOTS)
	@if diff -u tests/pictures/$(call REV7,wins) $(B)/wins.md5; then echo "PASS  maximize, restore, minimize, the Windows menu, Alt+Tab"; \
	else echo "FAIL  window buttons / Windows menu pictures (look at $(B)/wins*.ppm)"; exit 1; fi
	@PREP='cp "disks/Caverns of Mars.atr" GAME.ATR' DESK=1 sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) desk14 46 $(D14SHOTS)
	@if diff -u tests/pictures/$(call REV7,desk14) $(B)/desk14.md5; then echo "PASS  Desktop 0.14: shortcuts, the Atari panel and drops, the clock, icons, Tidy up, Delete"; \
	else echo "FAIL  Desktop 0.14 pictures (look at $(B)/desk14*.ppm)"; exit 1; fi
	@if grep -q 'CLASSIC_MOUNT kind 1 slot 1 /GAME.ATR -> 00' $(B)/desk14.err && test -e $(B)/run-pic/Desktop/LONG.TXT.LNK \
	  && ! test -e $(B)/run-pic/Desktop/README.TXT.LNK && grep -q '^2026-11-17 14:05' $(B)/run-pic/SYSTEM/CLOCK; \
	then echo "PASS  Desktop 0.14: the disk on D2:, the shortcuts, /SYSTEM/CLOCK"; \
	else echo "FAIL  Desktop 0.14: mount, shortcuts or clock ($(B)/desk14.err, $(B)/run-pic)"; exit 1; fi
	@PREP='cp "disks/Caverns of Mars.atr" GAME.ATR' DESK=1 sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) desk15 40 $(D15SHOTS)
	@if diff -u tests/pictures/$(call REV7,desk15) $(B)/desk15.md5; then echo "PASS  Desktop 0.15: pop-up menus (the Atari icon, Files, a text field, the desktop, an icon, Edit), the dialog's filter and type-ahead"; \
	else echo "FAIL  Desktop 0.15 pictures (look at $(B)/desk15*.ppm)"; exit 1; fi
	@if test -d "$(B)/run-pic/Desktop/Games" && grep -q 'CLASSIC_MOUNT kind 1 slot 0 /GAME.ATR -> 00' $(B)/desk15.err; then echo "PASS  Desktop 0.15: the folder made and renamed, GAME.ATR attached and loaded"; \
	else echo "FAIL  Desktop 0.15: /Desktop/Games or the mounts ($(B)/desk15.err, $(B)/run-pic)"; exit 1; fi
	@DESK=1 sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) desk18 27 $(D18SHOTS)
	@if diff -u tests/pictures/$(call REV7,desk18) $(B)/desk18.md5; then echo "PASS  Desktop 0.18: the Atari panel's Attach buttons and menu"; \
	else echo "FAIL  Desktop 0.18 pictures (look at $(B)/desk18*.ppm)"; exit 1; fi
	@if grep 'emu816: CLASSIC' $(B)/desk18.err | diff -u tests/desk18.err -; then echo "PASS  Desktop 0.18: a cartridge attached / ejected: the executable ejected, a cold boot each time"; \
	else echo "FAIL  Desktop 0.18: classic ops ($(B)/desk18.err)"; exit 1; fi
	@DESK=1 sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) kmenu 33 $(KMSHOTS)
	@if diff -u tests/pictures/$(call REV7,kmenu) $(B)/kmenu.md5; then echo "PASS  keyboard menus, Alt+Tab, ctrl+W, Alt+F4, menu states and shortcuts"; \
	else echo "FAIL  keyboard menu pictures (look at $(B)/kmenu*.ppm, then make pictures)"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) edit 22 $(ESHOTS)
	@if diff -u tests/pictures/$(EMD5) $(B)/edit.md5; then echo "PASS  Edit pictures"; \
	else echo "FAIL  Edit pictures (look at $(B)/edit*.ppm, then make pictures)"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) editw 34 $(EWSHOTS)
	@if diff -u tests/pictures/editw.md5 $(B)/editw.md5; then echo "PASS  Edit pictures: undo, word wrap, Find, Replace"; \
	else echo "FAIL  Edit pictures, second session (look at $(B)/editw*.ppm, then make pictures)"; exit 1; fi
	@if cmp $(B)/run-pic/E2.TXT tests/editw.txt; then echo "PASS  Edit: the file the second session saved"; \
	else echo "FAIL  Edit: build/run-pic/E2.TXT is not tests/editw.txt"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) paint 27 $(PSHOTS)
	@if diff -u tests/pictures/$(subst edit,paint,$(EMD5)) $(B)/paint.md5; then echo "PASS  Paint pictures"; \
	else echo "FAIL  Paint pictures (look at $(B)/paint*.ppm, then make pictures)"; exit 1; fi
	@DESK=1 sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) settings 22 $(SSHOTS)
	@if diff -u tests/pictures/$(subst edit,settings,$(EMD5)) $(B)/settings.md5; then echo "PASS  Settings pictures"; \
	else echo "FAIL  Settings pictures (look at $(B)/settings*.ppm, then make pictures)"; exit 1; fi
	@PREP='cp ../../sdfiles/atari.ini atari.ini' DESK=1 sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) classic 16 $(CLSHOTS)
	@if diff -u tests/pictures/classic.md5 $(B)/classic.md5; then echo "PASS  Settings pictures: the Classic Atari page"; \
	else echo "FAIL  Settings pictures, Classic Atari (look at $(B)/classic*.ppm, then make pictures)"; exit 1; fi
	@if cmp $(B)/run-pic/atari.ini tests/atari-ini.txt; then echo "PASS  Settings: the /atari.ini it saved"; \
	else echo "FAIL  Settings: build/run-pic/atari.ini is not tests/atari-ini.txt"; exit 1; fi
	@DESK=1 sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) files 46 $(FSHOTS)
	@if diff -u tests/pictures/$(subst edit,files,$(EMD5)) $(B)/files.md5; then echo "PASS  Files pictures"; \
	else echo "FAIL  Files pictures (look at $(B)/files*.ppm, then make pictures)"; exit 1; fi
	@rm -rf build/run-sd; cp -r $(SD) build/run-sd; touch build/run-sd/SYSTEM/NODESK; cp tests/basic.bas build/run-sd/BT.BAS
	@$(EMU) $(EMUFLAGS) --headless --sd build/run-sd --max-seconds $(BASSECS) \
	    --keys "$$(python3 tests/keyscript.py tests/basic-t.keys)" \
	    $(SD)/SYSTEM/HORIZON.SYS > $(B)/basic-t.out 2> $(B)/basic-t.err || true
	@python3 -c "L = open('$(B)/basic-t.out', encoding='latin-1').read().split('\n'); i = [k for k, l in enumerate(L) if '> basic -t /BT.BAS' in l][0]; open('$(B)/basic-t.txt', 'w', encoding='latin-1').write('\n'.join(L[i + 1:]))"
	@if python3 tests/compare.py tests/basic.txt $(B)/basic-t.txt; then echo "PASS  BASIC: self test, errors, LIST, INPUT, SAVE / LOAD ($$(grep -h 'empty FOR' $(B)/basic-t.txt))"; \
	else echo "FAIL  BASIC ($(B)/basic-t.out)"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) basic 39 $(BASSHOTS)
	@if diff -u tests/pictures/basic.md5 $(B)/basic.md5; then echo "PASS  BASIC pictures"; \
	else echo "FAIL  BASIC pictures (look at $(B)/basic*.ppm, then make pictures)"; exit 1; fi
	@rm -rf build/run-sd; cp -r $(SD) build/run-sd; touch build/run-sd/SYSTEM/NODESK; cp tests/sheet.sht build/run-sd/ST.SHT
	@$(EMU) $(EMUFLAGS) --headless --sd build/run-sd --max-seconds $(SHTSECS) \
	    --keys "$$(python3 tests/keyscript.py tests/sheet-t.keys)" \
	    $(SD)/SYSTEM/HORIZON.SYS > $(B)/sheet-t.out 2> $(B)/sheet-t.err || true
	@python3 -c "L = open('$(B)/sheet-t.out', encoding='latin-1').read().split('\n'); i = [k for k, l in enumerate(L) if '> sheet -t /ST.SHT' in l][0]; open('$(B)/sheet-t.txt', 'w', encoding='latin-1').write('\n'.join(L[i + 1:]))"
	@if python3 tests/compare.py tests/sheet-t.txt $(B)/sheet-t.txt; then echo "PASS  Sheet: self test ($$(grep -h 'full recalc' $(B)/sheet-t.txt | cut -c8-))"; \
	else echo "FAIL  Sheet self test ($(B)/sheet-t.out)"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) sheet 20 $(SHTSHOTS)
	@if diff -u tests/pictures/sheet.md5 $(B)/sheet.md5; then echo "PASS  Sheet pictures"; \
	else echo "FAIL  Sheet pictures (look at $(B)/sheet*.ppm, then make pictures)"; exit 1; fi
	@rm -rf build/run-sd; cp -r $(SD) build/run-sd; touch build/run-sd/SYSTEM/NODESK
	@$(EMU) $(EMUFLAGS) --headless --sd build/run-sd --max-seconds 60 \
	    --keys "$$(python3 tests/keyscript.py tests/leak.keys)" \
	    $(SD)/SYSTEM/HORIZON.SYS > $(B)/leak.out 2> $(B)/leak.err || true
	@if grep -a 'leak: 200 runs:.*: PASS' $(B)/leak.out; then echo "PASS  every resource comes back after 200 programs (exited or killed)"; \
	else echo "FAIL  leak ($(B)/leak.out)"; exit 1; fi
	@rm -rf build/run-sd; cp -r $(SD) build/run-sd; touch build/run-sd/SYSTEM/NODESK
	@$(EMU) $(EMUFLAGS) --headless --log-sound --sd build/run-sd --max-seconds 19 \
	    --keys "$$(python3 tests/keyscript.py tests/ktest.keys)" --mouse "$$(python3 tests/keyscript.py --mouse tests/ktest.keys)" \
	    $(SD)/SYSTEM/HORIZON.SYS > $(B)/ktest.out 2> $(B)/ktest.err || true
	@python3 -c "L = open('$(B)/ktest.out', encoding='latin-1').read().split('\n'); i = [k for k, l in enumerate(L) if l.startswith('ktest 1')][0]; j = ([k for k, l in enumerate(L) if l.startswith('ktest: done')] + [len(L) - 1])[0]; open('$(B)/ktest.txt', 'w', encoding='latin-1').write('\n'.join(L[i:j + 1]) + '\n')"
	@if python3 tests/compare.py tests/ktest.txt $(B)/ktest.txt; then echo "PASS  0.15 kernel: joystick, vsync, focus events and held keys, pop-up menus, no phantom button after a menu"; \
	else echo "FAIL  KTEST ($(B)/ktest.out)"; exit 1; fi
	@if grep sound $(B)/ktest.err | diff -u tests/ktest.err -; then echo "PASS  0.15 sound: the four chimes (two notes, the volume falling every tick), a task's channels silenced at its exit, a channel borrowed and given back"; \
	else echo "FAIL  KTEST sound log ($(B)/ktest.err)"; exit 1; fi
	@rm -rf build/run-sd; cp -r $(SD) build/run-sd; touch build/run-sd/SYSTEM/NODESK
	@$(EMU) $(EMUFLAGS) --headless --log-lau --sd build/run-sd --max-seconds 9 \
	    --keys "$$(python3 tests/keyscript.py tests/stest.keys)" \
	    $(SD)/SYSTEM/HORIZON.SYS > $(B)/stest.out 2> $(B)/stest.err || true
	@python3 -c "L = open('$(B)/stest.out', encoding='latin-1').read().split('\n'); i = [k for k, l in enumerate(L) if l.startswith('stest 1')][0]; j = [k for k, l in enumerate(L) if k > i and l.startswith('>')][0]; open('$(B)/stest.txt', 'w').write('\n'.join(L[i:j]) + '\n')"
	@if python3 tests/compare.py tests/$(STESTTXT) $(B)/stest.txt; then echo "PASS  0.17 samples (Lau): played from own memory, foreign ranges refused, voices stopped by bank_free, exit and kill, voice taking, ENODEV without Lau"; \
	else echo "FAIL  STEST ($(B)/stest.out)"; exit 1; fi
	@if grep lau $(B)/stest.err | diff -u $(STESTERR) -; then echo "PASS  0.17 Lau writes: the voices' registers, KEYOFF at bank_free, exit and kill, the master volume following the setting"; \
	else echo "FAIL  STEST Lau log ($(B)/stest.err)"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) gtest 12 5.2
	@python3 -c "L = open('$(B)/gtest.out', encoding='latin-1').read().split('\n'); i = [k for k, l in enumerate(L) if l.startswith('gtest 1')][0]; j = [k for k, l in enumerate(L) if k > i and l.startswith('gtest: done')][0]; open('$(B)/gtest.txt', 'w').write('\n'.join(L[i:j + 1]) + '\n')"
	@if python3 tests/compare.py tests/$(GTESTTXT) $(B)/gtest.txt; then echo "PASS  0.18 games round: frame, palette entries, sprites, full screen, draw lists, WE_VBL, sound volume (foreign memory refused, cleanup at exit, kill and bank_free, ENODEV on older boards)"; \
	else echo "FAIL  GTEST ($(B)/gtest.out)"; exit 1; fi
	@if diff -u tests/pictures/gtest.md5 $(B)/gtest.md5; then echo "PASS  0.18 draw lists: the same picture by Ali's list, its single blits and the CPU"; \
	else echo "FAIL  GTEST picture (look at $(B)/gtest1.ppm)"; exit 1; fi
	@if [ -z "$(NOSPR)$(OLD8)" ]; then \
	  sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) gtests 12 5.5 7.5 9.5; \
	  if diff -u tests/pictures/gtests.md5 $(B)/gtests.md5; then echo "PASS  0.18 sprites over a window: shown while it has the focus and nothing covers it, wholly inside its content"; \
	  else echo "FAIL  sprite pictures (look at $(B)/gtests*.ppm)"; exit 1; fi; \
	  sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) gtestf 14 5.5 7.5 9.5 11.5; \
	  if diff -u tests/pictures/gtestf.md5 $(B)/gtestf.md5; then echo "PASS  0.18 full screen: split, scrolling, sprites, raster table; Alt+Esc back to the desktop, Alt+Tab to it again, its end"; \
	  else echo "FAIL  full-screen pictures (look at $(B)/gtestf*.ppm)"; exit 1; fi; \
	  DESK=1 sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) gtestk 22 12 14.3 20; \
	  if diff -u tests/pictures/gtestk.md5 $(B)/gtestk.md5; then echo "PASS  0.18 full screen under the Desktop: Alt+Esc, then killed from the Terminal: the desktop as it was"; \
	  else echo "FAIL  full screen and kill (look at $(B)/gtestk*.ppm)"; exit 1; fi; \
	else echo "SKIP  0.18 sprite and full-screen pictures (REV \$$0B only)"; fi
	@$(MAKE) --no-print-directory test-games
	@if grep -l 'emu816: blitter:' $(B)/selftest-*.err $(B)/shell-*.err $(B)/screen.err $(B)/browse.err $(B)/wdemo.err $(B)/wcopy.err $(B)/wdraw.err $(B)/desk.err $(B)/edit.err $(B)/editw.err $(B)/paint.err $(B)/settings.err $(B)/files.err $(B)/basic-t.err $(B)/basic.err $(B)/sheet-t.err $(B)/sheet.err $(B)/classic.err $(B)/system.err $(B)/wins.err $(B)/desk14.err $(B)/kmenu.err $(B)/leak.err $(B)/ktest.err $(B)/desk15.err $(B)/desk18.err $(B)/stest.err $(B)/gtest.err $(B)/gtests.err $(B)/gtestf.err $(B)/gtestk.err; \
	then echo "FAIL  blitter rules (START or a register write while BUSY, or a read without CACHE_FLUSH)"; exit 1; \
	else echo "PASS  blitter rules: no violations"; fi
	@echo "TEST PASSED"

# after checking build/screen*.ppm, build/browse*.ppm and build/wdemo*.ppm by eye: freeze their md5, keep
# PNG copies, and freeze the browser session's classic-op log
pictures:
	cp $(B)/screen.md5 $(B)/browse.md5 $(B)/wdemo.md5 $(B)/wcopy.md5 $(B)/wdraw.md5 tests/pictures/
	cp $(B)/edit.md5 tests/pictures/$(EMD5)
	cp $(B)/editw.md5 tests/pictures/editw.md5
	cp $(B)/paint.md5 tests/pictures/$(subst edit,paint,$(EMD5))
	cp $(B)/settings.md5 tests/pictures/$(subst edit,settings,$(EMD5))
	cp $(B)/classic.md5 tests/pictures/classic.md5
	cp $(B)/files.md5 tests/pictures/$(subst edit,files,$(EMD5))
	cp $(B)/desk.md5 tests/pictures/$(DMD5)
	cp $(B)/system.md5 tests/pictures/$(call REV7,system)
	cp $(B)/kmenu.md5 tests/pictures/$(call REV7,kmenu)
	cp $(B)/wins.md5 tests/pictures/$(call REV7,wins)
	cp $(B)/desk14.md5 tests/pictures/$(call REV7,desk14)
	cp $(B)/desk15.md5 tests/pictures/$(call REV7,desk15)
	cp $(B)/desk18.md5 tests/pictures/$(call REV7,desk18)
	cp $(B)/basic.md5 tests/pictures/basic.md5
	cp $(B)/sheet.md5 tests/pictures/sheet.md5
	cp $(B)/browse.err tests/browse.err
	python3 -c "from PIL import Image; import glob; [Image.open(f).save('tests/pictures/' + f.split('/')[-1][:-4] + '.png') for f in sorted(glob.glob('$(B)/screen[0-9]*.ppm') + glob.glob('$(B)/browse[0-9]*.ppm') + glob.glob('$(B)/wdemo[0-9]*.ppm') + glob.glob('$(B)/wcopy[0-9]*.ppm') + glob.glob('$(B)/wdraw[0-9]*.ppm') + glob.glob('$(B)/desk[0-9]*.ppm') + glob.glob('$(B)/edit[0-9]*.ppm') + glob.glob('$(B)/editw[0-9]*.ppm') + glob.glob('$(B)/paint[0-9]*.ppm') + glob.glob('$(B)/settings[0-9]*.ppm') + glob.glob('$(B)/classic[0-9]*.ppm') + glob.glob('$(B)/system[0-9]*.ppm') + glob.glob('$(B)/kmenu[0-9]*.ppm') + glob.glob('$(B)/wins[0-9]*.ppm') + glob.glob('$(B)/desk14[0-9]*.ppm') + glob.glob('$(B)/desk15[0-9]*.ppm') + glob.glob('$(B)/files[0-9]*.ppm') + glob.glob('$(B)/basic[0-9]*.ppm') + glob.glob('$(B)/sheet[0-9]*.ppm'))]"

# Calculator and Solitaire: their self tests (tests/calc-t.keys, tests/solitair-t.keys; the
# output compared with tests/calc-t.txt, tests/solitair-t.txt) and picture sessions
# (tests/calc.keys, tests/solitair.keys: the same pictures with and without the blitter).
# Run by make test; make pictures-games freezes their pictures.
CALCSHOTS := 7.8 10.0 11.8 17.5 19.5
SOLSHOTS := 5.5 6.8 11.0 14.5 17.4 20.4 58
# (0.17) Quabricks: its self test (tests/quabrick-t.keys, compared with tests/quabrick-t.txt)
# and its picture session (tests/quabrick.keys; the shot times are explained there). Without
# the blitter (REV $07) it draws slower: the same session, some later states, its own md5.
QBSHOTS := 5 6.5 10.25 11.1 16.4 17.2 22.5 24 24.8 26.5 31.5 33 37 41 42
test-games: all $(EMU)
	@rm -rf build/run-sd; cp -r $(SD) build/run-sd; touch build/run-sd/SYSTEM/NODESK
	@$(EMU) $(EMUFLAGS) --headless --sd build/run-sd --max-seconds 12 --keys "$$(python3 tests/keyscript.py tests/calc-t.keys)" \
	    $(SD)/SYSTEM/HORIZON.SYS > $(B)/calc-t.out 2> $(B)/calc-t.err || true
	@python3 -c "L = open('$(B)/calc-t.out', encoding='latin-1').read().split('\n'); i = [k for k, l in enumerate(L) if '> calc -t' in l][0]; open('$(B)/calc-t.txt', 'w', encoding='latin-1').write('\n'.join(L[i + 1:]))"
	@if python3 tests/compare.py tests/calc-t.txt $(B)/calc-t.txt; then echo "PASS  Calculator: self test ($$(grep -h 'CALC TEST END' $(B)/calc-t.txt | cut -c16-))"; \
	else echo "FAIL  Calculator self test ($(B)/calc-t.out)"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) calc 21 $(CALCSHOTS)
	@if diff -u tests/pictures/calc.md5 $(B)/calc.md5; then echo "PASS  Calculator pictures"; \
	else echo "FAIL  Calculator pictures (look at $(B)/calc*.ppm, then make pictures-games)"; exit 1; fi
	@rm -rf build/run-sd; cp -r $(SD) build/run-sd; touch build/run-sd/SYSTEM/NODESK
	@$(EMU) $(EMUFLAGS) --headless --sd build/run-sd --max-seconds 70 --keys "$$(python3 tests/keyscript.py tests/solitair-t.keys)" \
	    $(SD)/SYSTEM/HORIZON.SYS > $(B)/solitair-t.out 2> $(B)/solitair-t.err || true
	@python3 -c "L = open('$(B)/solitair-t.out', encoding='latin-1').read().split('\n'); i = [k for k, l in enumerate(L) if '> solitair -t' in l][0]; open('$(B)/solitair-t.txt', 'w', encoding='latin-1').write('\n'.join(L[i + 1:]))"
	@if python3 tests/compare.py tests/solitair-t.txt $(B)/solitair-t.txt; then echo "PASS  Solitaire: self test ($$(grep -h 'random play' $(B)/solitair-t.txt | cut -c19-))"; \
	else echo "FAIL  Solitaire self test ($(B)/solitair-t.out)"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) solitair 60 $(SOLSHOTS)
	@if diff -u tests/pictures/solitair.md5 $(B)/solitair.md5; then echo "PASS  Solitaire pictures"; \
	else echo "FAIL  Solitaire pictures (look at $(B)/solitair*.ppm, then make pictures-games)"; exit 1; fi
	@rm -rf build/run-sd; cp -r $(SD) build/run-sd; touch build/run-sd/SYSTEM/NODESK
	@$(EMU) $(EMUFLAGS) --headless --sd build/run-sd --max-seconds 30 --keys "$$(python3 tests/keyscript.py tests/quabrick-t.keys)" \
	    $(SD)/SYSTEM/HORIZON.SYS > $(B)/quabrick-t.out 2> $(B)/quabrick-t.err || true
	@python3 -c "L = open('$(B)/quabrick-t.out', encoding='latin-1').read().split('\n'); i = [k for k, l in enumerate(L) if '> quabrick -t' in l][0]; open('$(B)/quabrick-t.txt', 'w', encoding='latin-1').write('\n'.join(L[i + 1:]))"
	@if python3 tests/compare.py tests/quabrick-t.txt $(B)/quabrick-t.txt; then echo "PASS  Quabricks: self test (turns and kicks, the bag, points, spins, back-to-back, combos, the lock delay, Time Attack, levels)"; \
	else echo "FAIL  Quabricks self test ($(B)/quabrick-t.out)"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) quabrick 46 $(QBSHOTS)
	@if diff -u tests/pictures/$(call REV7,quabrick) $(B)/quabrick.md5; then echo "PASS  Quabricks pictures"; \
	else echo "FAIL  Quabricks pictures (look at $(B)/quabrick*.ppm, then make pictures-games)"; exit 1; fi
	@if grep -q '^QBK1' $(B)/run-pic/BIN/QUABRICK.DAT && grep -q 'TESTER' $(B)/run-pic/BIN/QUABRICK.DAT; then echo "PASS  Quabricks: the high score saved in /BIN/QUABRICK.DAT"; \
	else echo "FAIL  Quabricks: no /BIN/QUABRICK.DAT with the name"; exit 1; fi
	@if grep -l 'emu816: blitter:' $(B)/calc-t.err $(B)/calc.err $(B)/solitair-t.err $(B)/solitair.err $(B)/quabrick-t.err $(B)/quabrick.err; \
	then echo "FAIL  blitter rules (Calculator, Solitaire, Quabricks)"; exit 1; \
	else echo "PASS  blitter rules: Calculator, Solitaire, Quabricks"; fi

pictures-games:
	cp $(B)/calc.md5 $(B)/solitair.md5 tests/pictures/
	cp $(B)/quabrick.md5 tests/pictures/$(call REV7,quabrick)
	python3 -c "from PIL import Image; import glob; [Image.open(f).save('tests/pictures/' + f.split('/')[-1][:-4] + '.png') for f in sorted(glob.glob('$(B)/calc[0-9]*.ppm') + glob.glob('$(B)/solitair[0-9]*.ppm') + glob.glob('$(B)/quabrick[0-9]*.ppm'))]"

.PHONY: test-games pictures-games

clean:
	rm -rf build

# Write's tests (also run first by make test; make write-test runs them alone)
test: write-test
write-test: all $(EMU)
	@rm -rf build/run-sd; cp -r $(SD) build/run-sd; touch build/run-sd/SYSTEM/NODESK; cp tests/write.wt build/run-sd/WT.WT
	@cp tests/write-rt.md build/run-sd/WRT.MD; cp tests/write-rt2.md build/run-sd/WRT2.MD; cp tests/write-ex.txt build/run-sd/WEX.TXT; cp tests/write-new.md build/run-sd/WNEWX.MD
	@$(EMU) $(EMUFLAGS) --headless --sd build/run-sd --max-seconds $(WRSECS) \
	    --keys "$$(python3 tests/keyscript.py tests/write-t.keys)" \
	    $(SD)/SYSTEM/HORIZON.SYS > $(B)/write-t.out 2> $(B)/write-t.err || true
	@python3 -c "L = open('$(B)/write-t.out', encoding='latin-1').read().split('\n'); i = [k for k, l in enumerate(L) if '> write -t /WT.WT' in l][0]; open('$(B)/write-t.txt', 'w', encoding='latin-1').write('\n'.join(L[i + 1:]))"
	@if python3 tests/compare.py tests/write-t.txt $(B)/write-t.txt; then echo "PASS  Write: self test (Markdown, format commands, styles armed, toolbar state, round trip, save as, export)"; \
	else echo "FAIL  Write self test ($(B)/write-t.out)"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) write 38 $(WRSHOTS)
	@if diff -u tests/pictures/write.md5 $(B)/write.md5; then echo "PASS  Write pictures"; \
	else echo "FAIL  Write pictures (look at $(B)/write*.ppm, then make pictures)"; exit 1; fi
	@sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) writee 45 $(WESHOTS)
	@if diff -u tests/pictures/writee.md5 $(B)/writee.md5; then echo "PASS  Write pictures: an editing session"; \
	else echo "FAIL  Write pictures, editing session (look at $(B)/writee*.ppm, then make pictures)"; exit 1; fi
	@if cmp $(B)/run-pic/W1.MD tests/write-w1.md; then echo "PASS  Write: the file the editing session saved"; \
	else echo "FAIL  Write: build/run-pic/W1.MD is not tests/write-w1.md"; exit 1; fi
	@if cmp $(B)/run-pic/NOTES.md tests/write-notes.md; then echo "PASS  Write: a new document saved as NOTES.md (Markdown)"; \
	else echo "FAIL  Write: build/run-pic/NOTES.md is not tests/write-notes.md"; exit 1; fi
	@if grep -l 'emu816: blitter:' $(B)/write-t.err $(B)/write.err $(B)/writee.err; \
	then echo "FAIL  blitter rules (Write)"; exit 1; else echo "PASS  blitter rules (Write): no violations"; fi
	@echo "WRITE TESTS PASSED"

# Write's pictures (after checking build/write*.ppm by eye)
pictures: write-pictures
write-pictures:
	cp $(B)/write.md5 $(B)/writee.md5 tests/pictures/
	python3 -c "from PIL import Image; import glob; [Image.open(f).save('tests/pictures/' + f.split('/')[-1][:-4] + '.png') for f in sorted(glob.glob('$(B)/write[0-9]*.ppm') + glob.glob('$(B)/writee[0-9]*.ppm'))]"

.PHONY: all run test clean pictures write-pictures write-test

# (BASIC 2.0) the games statements (also run first by make test; make basic2-test runs them
# alone): tests/basic2.bas as a -t script with the sound files of tests/mkwav.py on the card,
# compared with tests/basic2.txt (REV $0A: basic2-r10.txt, $09: -r9, $08 and $07: -r8: the
# missing hardware says "Not available on this machine", the rest is the same), its writes to
# Lau with tests/basic2.err (REV $0A: basic2-r10.err; none without Lau); on REV $0B a picture session of the examples
# (tests/basic2s.keys: sprites, the game, full screen with a panel and raster bands, Break,
# Alt+Tab, CONT).
BAS2SECS := 75
BAS2SHOTS := 7.0 9.0 13.0 17.5 19.5 26.5 28.5 31.0 33.5 36.5
BREV10  = $(findstring --rev 10,$(EMUFLAGS))
BREV9   = $(findstring --rev 9,$(EMUFLAGS))
BAS2TXT = $(if $(OLD8),basic2-r8.txt,$(if $(BREV9),basic2-r9.txt,$(if $(BREV10),basic2-r10.txt,basic2.txt)))
BAS2ERR = $(if $(NOLAU),/dev/null,$(if $(BREV10),tests/basic2-r10.err,tests/basic2.err))
test: basic2-test
basic2-test: all $(EMU)
	@rm -rf build/run-sd; cp -r $(SD) build/run-sd; touch build/run-sd/SYSTEM/NODESK; cp tests/basic2.bas build/run-sd/B2.BAS
	@python3 tests/mkwav.py build/run-sd
	@$(EMU) $(EMUFLAGS) --headless --log-lau --sd build/run-sd --max-seconds $(BAS2SECS) \
	    --keys "$$(python3 tests/keyscript.py tests/basic2-t.keys)" \
	    $(SD)/SYSTEM/HORIZON.SYS > $(B)/basic2-t.out 2> $(B)/basic2-t.err || true
	@python3 -c "L = open('$(B)/basic2-t.out', encoding='latin-1').read().split('\n'); i = [k for k, l in enumerate(L) if '> basic -t /B2.BAS' in l][0]; open('$(B)/basic2-t.txt', 'w', encoding='latin-1').write('\n'.join(L[i + 1:]))"
	@if python3 tests/compare.py tests/$(BAS2TXT) $(B)/basic2-t.txt; then echo "PASS  BASIC 2.0: pictures, sprites, HIT, full screen, SCROLL, PANEL, RASTER, WAVE, PLAY, NOTE, errors, cleanup ($(BAS2TXT))"; \
	else echo "FAIL  BASIC 2.0 ($(B)/basic2-t.out)"; exit 1; fi
	@if grep lau $(B)/basic2-t.err | diff -u $(BAS2ERR) -; then echo "PASS  BASIC 2.0 Lau writes: WAVE and file samples played, voices, pitch, volume and pan, PLAY OFF, END"; \
	else echo "FAIL  BASIC 2.0 Lau log ($(B)/basic2-t.err)"; exit 1; fi
	@if [ -z "$(NOSPR)$(OLD8)" ]; then \
	  sh tests/shots.sh "$(EMU) $(EMUFLAGS)" $(SD) basic2s 38 $(BAS2SHOTS); \
	  if diff -u tests/pictures/basic2s.md5 $(B)/basic2s.md5; then echo "PASS  BASIC 2.0 pictures: SPRITES.BAS, DRIFT.BAS, SCROLLER.BAS, Break, Alt+Tab, CONT, the BASIC window back"; \
	  else echo "FAIL  BASIC 2.0 pictures (look at $(B)/basic2s*.ppm, then make basic2-pictures)"; exit 1; fi; \
	else echo "SKIP  BASIC 2.0 pictures (REV \$$0B only)"; fi
	@if grep -l 'emu816: blitter:' $(B)/basic2-t.err $(wildcard $(B)/basic2s.err); \
	then echo "FAIL  blitter rules (BASIC 2.0)"; exit 1; else echo "PASS  blitter rules (BASIC 2.0): no violations"; fi

# BASIC 2.0's pictures (after checking build/basic2s*.ppm by eye)
pictures: basic2-pictures
basic2-pictures:
	cp $(B)/basic2s.md5 tests/pictures/basic2s.md5
	python3 -c "from PIL import Image; import glob; [Image.open(f).save('tests/pictures/' + f.split('/')[-1][:-4] + '.png') for f in sorted(glob.glob('$(B)/basic2s[0-9]*.ppm'))]"

.PHONY: basic2-test basic2-pictures

# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
# Atari816 native test programs (ca65/ld65). The I/O processor loads /A816.BIN from the SD card.
#   A816.BIN      self test: FREDDIE II + system block (current)
#   KBTEST.BIN    keyboard events, system key, joystick (python3 tools/atari.py run816 sw/a816/KBTEST.BIN)
#   BRINGUP1.BIN  bring-up 1: RAM test and speed measurements (rename to A816.BIN to run)
#   BLITTEST.BIN  blitter: every op against a 65C816 reference, also the simulation's test (+prog=BLITTEST.BIN)
#   BLITLIST.BIN  REV $09: blitter command lists, raster events (VBLANK, LINE, NV_FRAME), list speed
#   SAMPLER.BIN   REV $0A: sample player self test (rate, end IRQ, loop, mix, no late samples under load)
#   PLAYDEMO.BIN  REV $0A: sample player listening demo (chord, pan sweep, looped note, noise)
#   SPRTEST.BIN   REV $0B: sprites and fine scrolling, self test (registers, COMMIT, line limit, load);
#                 sprtest_sim.bin adds random scenes whose pixels the testbench checks;
#                 sprsceneN.bin (make scenes): fixed scenes for comparing the RTL's frame with emu816's
#   SPRDEMO.BIN   REV $0B: sprite demo for the eye (16 sprites, flips, MAG, BEHIND, pointer, 20 s)
#   SCROLLDEMO.BIN REV $0B: fine scrolling demo (1024x512 wrapping playfield, split status panel, 20 s)
#   SPLIT.BIN     REV $09: palette split at a raster line for the eye, interrupt counts in the log
#   FSBENCH.BIN   SD card throughput through the mailbox (512 KB write, read, load)
#   PCBENCH.BIN   the same on the PC volume (/PC:, needs the gateway)
#   INTEST.BIN    key and mouse events during long card and PC requests (core/tools/intest.py)
#   SYSTEST.BIN   firmware SYS_SYNC + SYS_RESTART 0 (Horizon comes back); SYSTEST1.BIN: SYS_RESTART 1
#   TIMING.BIN    CPU and Ali timing by access kind and video mode (calibrates emu816's memory model)
SCENES = sprscene1.bin sprscene2.bin sprscene3.bin sprscene4.bin sprscene5.bin sprscene6.bin sprscene7.bin sprscene8.bin sprscene9.bin sprscene10.bin
all: INTEST.BIN TIMING.BIN SPRTEST.BIN sprtest_sim.bin $(SCENES) SPRDEMO.BIN SCROLLDEMO.BIN FSBENCH.BIN PCBENCH.BIN SAMPLER.BIN sampler_sim.bin PLAYDEMO.BIN BLITLIST.BIN blitlist_sim.bin SPLIT.BIN A816.BIN SYSTEST.BIN SYSTEST1.BIN BRINGUP1.BIN KBTEST.BIN NVTEST.BIN BLITTEST.BIN SNDTEST.BIN SNDTEST2.BIN SNDTEST3.BIN a816_sim.bin bringup1_sim.bin nvtest_sim.bin
A816.BIN a816_sim.bin: freddie2.s irqtest.inc mbtest.inc bringup1.cfg
	ca65 -o freddie2.o freddie2.s && ld65 -C bringup1.cfg -o A816.BIN freddie2.o && cp A816.BIN a816_sim.bin
KBTEST.BIN: kbtest.s bringup1.cfg
	ca65 -o kbtest.o kbtest.s && ld65 -C bringup1.cfg -o $@ kbtest.o
TIMING.BIN: timing.s bringup1.cfg
	ca65 -o timing.o timing.s && ld65 -C bringup1.cfg -o $@ timing.o
FSBENCH.BIN: fsbench.s bringup1.cfg
	ca65 -o fsbench.o fsbench.s && ld65 -C bringup1.cfg -o $@ fsbench.o
PCBENCH.BIN: pcbench.s bringup1.cfg
	ca65 -o pcbench.o pcbench.s && ld65 -C bringup1.cfg -o $@ pcbench.o
INTEST.BIN: intest.s bringup1.cfg
	ca65 -o intest.o intest.s && ld65 -C bringup1.cfg -o $@ intest.o
SYSTEST.BIN: systest.s bringup1.cfg
	ca65 -o systest.o systest.s && ld65 -C bringup1.cfg -o $@ systest.o
SYSTEST1.BIN: systest.s bringup1.cfg
	ca65 -D FULL -o systest1.o systest.s && ld65 -C bringup1.cfg -o $@ systest1.o
BRINGUP1.BIN: bringup1.s bringup1.cfg
	ca65 -o bringup1.o bringup1.s && ld65 -C bringup1.cfg -o $@ bringup1.o
NVTEST.BIN: nvtest.s bringup1.cfg
	ca65 -o nvtest.o nvtest.s && ld65 -C bringup1.cfg -o $@ nvtest.o
BLITLIST.BIN: blitlist.s bringup1.cfg
	ca65 -o blitlist.o blitlist.s && ld65 -C bringup1.cfg -o $@ blitlist.o
blitlist_sim.bin: blitlist.s bringup1.cfg
	ca65 -D SIM -o blitlist_sim.o blitlist.s && ld65 -C bringup1.cfg -o $@ blitlist_sim.o
SAMPLER.BIN: sampler.s bringup1.cfg
	ca65 -o sampler.o sampler.s && ld65 -C bringup1.cfg -o $@ sampler.o
sampler_sim.bin: sampler.s bringup1.cfg
	ca65 -D SIM -o sampler_sim.o sampler.s && ld65 -C bringup1.cfg -o $@ sampler_sim.o
PLAYDEMO.BIN: playdemo.s sine256.inc bringup1.cfg
	ca65 -o playdemo.o playdemo.s && ld65 -C bringup1.cfg -o $@ playdemo.o
SPRTEST.BIN: sprtest.s bringup1.cfg
	ca65 -o sprtest.o sprtest.s && ld65 -C bringup1.cfg -o $@ sprtest.o
scenes: $(SCENES)
sprscene%.bin: sprscene.s bringup1.cfg
	ca65 -D SEED=$* -o sprscene$*.o sprscene.s && ld65 -C bringup1.cfg -o $@ sprscene$*.o
sprtest_sim.bin: sprtest.s bringup1.cfg
	ca65 -D SIM -o sprtest_sim.o sprtest.s && ld65 -C bringup1.cfg -o $@ sprtest_sim.o
SPRDEMO.BIN: sprdemo.s sine256.inc bringup1.cfg
	ca65 -o sprdemo.o sprdemo.s && ld65 -C bringup1.cfg -o $@ sprdemo.o
SCROLLDEMO.BIN: scrolldemo.s sine256.inc bringup1.cfg
	ca65 -o scrolldemo.o scrolldemo.s && ld65 -C bringup1.cfg -o $@ scrolldemo.o
SPLIT.BIN: split.s bringup1.cfg
	ca65 -o split.o split.s && ld65 -C bringup1.cfg -o $@ split.o
BLITTEST.BIN: blittest.s bringup1.cfg
	ca65 -o blittest.o blittest.s && ld65 -C bringup1.cfg -o $@ blittest.o
nvtest_sim.bin: nvtest.s bringup1.cfg
	ca65 -D SIM -o nvtest_sim.o nvtest.s && ld65 -C bringup1.cfg -o $@ nvtest_sim.o
bringup1_sim.bin: bringup1.s bringup1.cfg
	ca65 -D SIM -o bringup1_sim.o bringup1.s && ld65 -C bringup1.cfg -o $@ bringup1_sim.o
# audio noise tests: listen while they run (see the header of each source)
SNDTEST%.BIN: sndtest%.s bringup1.cfg
	ca65 -o sndtest$*.o $< && ld65 -C bringup1.cfg -o $@ sndtest$*.o
SNDTEST.BIN: sndtest.s bringup1.cfg
	ca65 -o sndtest.o sndtest.s && ld65 -C bringup1.cfg -o $@ sndtest.o
clean:
	rm -f *.o *.BIN *.bin

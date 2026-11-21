---
name: atari-816-dev
description: Write, build, run and test programs for the Atari816 (a 65C816 computer on an FPGA) and its OS Horizon - console tools, desktop window apps, games and BASIC programs - in 65816 assembly (ca65/ld65) or Horizon BASIC, checked in the emu816 emulator with scripted input and screenshots. Use when asked to "write an Atari816 program", "make a Horizon app / window program / game", "write 65816 code for Horizon", "port X to the Atari816", "a .PRG for Horizon", "a Horizon BASIC game", or to fix, test or deploy such a program.
---

# Atari816 development

The Atari816: a 65C816 at 14.3 MHz, 8 MB RAM, a 640 x 360 x 8 bpp desktop shown 2 x 2 on
720p by Marga, the video chip, Ali, the blitter, POKEY sound and Lau, the sample player
(Horizon 0.17), an OPL2 FM synthesizer (REV $0C, Horizon 0.27), an Atari 8-bit inside. Horizon 0.18 adds full-screen mode with fine
scrolling, 16 hardware sprites, draw lists and frame sync. Horizon is its preemptive,
memory-protected OS with a window system. Programs are `.PRG` files: 65816 assembly
built with ca65/ld65 against Horizon's `horizon.inc`, run in user mode; **all hardware
access goes through syscalls** (`COP #n`).

## Find the SDK

The SDK is the folder with `tools/run816.py`, `templates/`, `docs/reference/` (in the
Atari816 repository: `sdk/`, next to `horizon/` and `emu/`). If unsure:
`find / -name run816.py -path '*sdk/tools*' 2>/dev/null | head -1`. Below, `SDK` is that
folder and `HORIZON` the Horizon tree (`SDK/../horizon`).

Prerequisites (check once): `ca65 --version`, `python3 -c 'import PIL'`, a built emulator
(`HORIZON/../emu/emu816`, else `make -C HORIZON/../emu`) and a built card
(`HORIZON/build/sd/SYSTEM/HORIZON.SYS`, else `make -C HORIZON`). If other people work in
the Horizon tree, copy `horizon/` and `emu/` somewhere private, build there, and pass
`HORIZON=<copy>` to every make.

## Workflow

1. **Choose a template** and copy it to the program's own folder:
   - `SDK/templates/console` - text in / text out (shell or Terminal).
   - `SDK/templates/window-app` - a desktop app: window, menus, controls (ui.lib), file
     dialog, alert.
   - `SDK/templates/game` - action game in a window: timer loop, tile map, keyed-blit
     sprites, dirty rectangles, keys + mouse, POKEY sound effects, title / play / game over.
   - `SDK/examples/deepdive` - a full-screen scrolling game (Horizon 0.18): own framebuffer,
     fine scrolling with wrap and a split panel, one draw list a frame, hardware sprites,
     own palette and raster table, Lau samples. Copy it for anything full screen.
   - `SDK/templates/basic-game` - a Horizon BASIC program (no assembler).
   - `SDK/examples/fetch`, `SDK/examples/echo` - (Horizon 0.22) the internet through the PC
     link: a URL read as a file, a TCP connection polled with sleep. Rules in the
     cheat sheet's "The internet" and `SDK/docs/reference/internet.md`.
   Set `NAME` in the Makefile. If the folder is not two levels below SDK, pass both
   paths on every make command: `make HORIZON=/abs/horizon SDK=/abs/sdk` (run816 is
   found through `SDK`). Replace the template's `test` target with checks for your
   program (the window-app one checks the template's own NAME.TXT). No template fits
   "a window with an animation" exactly: take `game` for anything that moves (its loop
   and timer), `window-app` for controls.
2. **Read before writing**: `references/abi-cheatsheet.md` (syscalls, blocks, events),
   `references/pitfalls.md` (the mistakes that kill tasks or garble code). For a window
   app also `references/look-and-feel.md`; for a game `references/games.md` and
   `references/pixel-art.md`. Full reference: `SDK/docs/reference/` (one page per topic,
   an example for every call).
3. **Write** `main.s` starting from the template's code. Keep its skeleton (WSSTART /
   ui_init / event loop / clean exit). Art for games: text art in `art/*.txt`, converted
   by `SDK/tools/img2inc.py` at build time.
4. **Build**: `make` (or `make HORIZON=... SDK=...`). Fix every ca65 error and warning:
   "Range error" on a branch = use `jmp`/`jne`/`jeq`/`jcc`/`jcs`; "Didn't use zeropage
   addressing" = a symbol defined after its use (move constants up) or a missing `z:`.
5. **Run and look**: `make run` (one screenshot after 1 s), or
   `python3 SDK/tools/run816.py NAME.PRG --horizon HORIZON --script my.script --out build/try`
   then **open every `build/try/shotN.png` and look at it** (or make one sheet:
   `python3 SDK/tools/contact.py build/try/sheet.png build/try/shot*.png`; on the sheet,
   one pixel = one screen pixel, so you can read coordinates for mouse moves).
   Check: is it drawn where you meant, nothing left over, text not clipped, colours right?
   Also read `build/try/console.txt` (crashes show as `[kill] task N NAME cause CC ...`;
   run816 then exits 1). Under the Desktop, Files is open at the top left and the menu
   bar shows Horizon and Programs before your menus.
6. **Fix and repeat** until the pictures are right. A crash: see "Faults" in
   `references/pitfalls.md`.
7. **Test script**: write `test.script` (input + `shot` lines) that drives the program
   through its main features, and a `test` target (`make test`) that runs it with
   `--expect TEXT` checks or file checks on `build/test/card/`. The simplest check for a
   window program: `print` a line on each event worth testing ("bounce 3", "solved in 2
   moves"): under the Desktop it goes only to the log, which is `console.txt`. A program
   that takes an argument (a test or demo mode) needs `--mode shell --args ...`.
   Games: `--log-sound` / `--log-lau` and check `emu.err` for `sound $DB..` / `lau $DB..` writes.
8. Report what you verified by running and what you did not (sound is never audible in
   the emulator; the emulator's joysticks read 0; emu816 runs at the board's speed since Horizon 0.19
   (`--ideal-timing`: the old, ~2x faster model); the
   emulator is REV $0C by default: `--rev 11/10/9/8/7` for older boards).

## Input scripts (run816.py --script)

One event per line, time in ms after the program started (`+N` = after the previous line):
```
800 hello\n          type text (\n Enter, \b Backspace, ^S ctrl+S, {esc} {up} {f10} {alt-f})
+500 key right 700   hold a key 700 ms (game controls)
+200 move 320 180    move the pointer to screen pixel (640 x 360 space)
+100 click           left click (click right / dclick / press / release / drag X Y / wheel N)
+500 shot            take a screenshot
```
Window content position = outer window x + 1, y + 16 (for a window opened at x, y).
Desktop mode (default) needs ~5 s to boot and launch; shell mode (`--mode shell`, needed
for `--args` and console programs) ~4 s; time 0 in the script is after that.

## Rules of thumb

- A16/I16 everywhere (`rep #$30`); 8-bit only locally, with `sep #$20` + `.a8` and back
  with `rep #$20` + `.a16`.
- Syscall results: **only carry and A (X, Y where documented) are meaningful.** N and Z
  are NOT set from A: test with `cmp #0`, `tax`, etc. after `sys`.
- Pointers: X = offset, Y = bank: `ptr label`. Blocks hold u24 = `.faraddr label`.
- Data and BSS are in the code bank (DBR); zero page is a private direct page in bank 0
  (`lda z:var`). Big buffers: `SYS_BALLOC` banks + long addressing (`[ptr],y`).
- Draw with few, large `win_draw` calls (~0.2 ms each, ~0.4 ms on the board); never
  redraw what did not change. Text with paper colour to overwrite without flicker. Many
  blits a frame: one `draw_list` (its sources stay in use until `list_wait` / `vsync`), or,
  from art registered once as a sheet (Horizon 0.19), one `sheet_draw`: four times cheaper.
- A multi-file program: `main.s` must be linked first (the templates' Makefiles do it):
  execution starts at the first byte of CODE.
- `SYS_UPTIME` is the same at every emulator run: a random seed from it repeats (good for
  tests).
- Exit through `exit n`; if `SYS_WSSTART` returned 1, `SYS_WSSTOP` first; silence sound
  (`SYS_BEEP` with X = 0) before exit.
- Under the Desktop, console output only reaches the log (`console.txt`), not the screen.

## References

- `references/abi-cheatsheet.md` - syscalls by topic, blocks, events, colours, keys.
- `references/pitfalls.md` - 65C816 / ca65 traps seen in this code base; faults.
- `references/look-and-feel.md` - grid, fonts, colours, standard menus, shortcuts, dialogs.
- `references/pixel-art.md` - art that reads at 2 x, the palette, img2inc text art.
- `references/games.md` - game loop, input, dirty rectangles with the blitter, sound.
- `references/testing.md` - run816, scripts, screenshots, test targets, the board.

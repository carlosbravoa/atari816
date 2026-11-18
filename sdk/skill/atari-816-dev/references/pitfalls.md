# 65C816 / ca65 pitfalls on Horizon

Each of these has bitten real code. Check new code against the list before running it.

## Register widths

- Programs run with A, X, Y 16-bit. horizon.inc sets `.smart -`: **ca65 does not follow
  REP/SEP**. After `sep #$20` write `.a8`, after `rep #$20` write `.a16` (same for X/Y with
  `.i8`/`.i16`). Otherwise `lda #5` is assembled with the wrong operand size and the CPU
  runs off into the data. Symptom: a crash or nonsense right after an 8-bit section.
- Keep 8-bit sections short and local; every routine starts and ends A16/I16.
- `.a8` / `.a16` are assembler state, in source order, not control flow: a label that is
  reached by a branch from an 8-bit section needs its own `.a8` (and the code after the
  section's `rep` its `.a16`).
- Filling a byte array with 16-bit stores writes one byte past each end (a `sta buf-1,x`
  loop writes before `buf`): give buffers a spare byte, or use 8-bit stores.
- A 16-bit `sta` writes two bytes: storing a byte into a table with A16 also overwrites
  the next byte. Use `sep #$20` / `.a8` ... `rep #$20` / `.a16` for single bytes, or plan
  the order (write the low field last). The same for `stz`.
- A 16-bit `lda` of a byte reads the next byte too: `and #$00FF` after it.
- `inc`/`dec` on memory are 16-bit with A16: a byte counter needs 8-bit mode.
- `xba` swaps the bytes of A (handy for `value * 256` and for `op | colour << 8`).

## Addressing

- **Direct page is not the data bank.** ZEROPAGE variables are in bank 0 (your window);
  DATA/BSS/RODATA are in the code bank (DBR). Write `lda z:var` for zero page. Without
  `z:`, ca65 chooses absolute addressing for a symbol it has not seen yet (defined later
  in the file) and reads the code bank instead. Warning to heed: "Didn't use zeropage
  addressing for 'X'". Put the ZEROPAGE segment at the end and always write `z:`
  (except inside brackets: `lda [ptr],y` / `lda (ptr),y` are always direct page, and
  `[z:ptr]` is a syntax error).
- Names of instructions cannot be labels or constants either (`sty:`, `STY = 8`): the
  error ("Expected an expression") does not say why.
- **Long pointers** live in zero page as 3 bytes (+1 spare): `ptr: .res 4`. Fill offset
  and bank (`sta z:ptr` / `lda #bank` / `sta z:ptr+2`), then `lda [ptr],y`. Forgetting
  the bank byte = reading bank 0 or garbage = a kill (cause $06 / $04).
- `lda f:$xxxxxx` / `lda f:label,x` for long absolute; `lda label` is DBR (code bank).
- Pointers to syscalls: `ptr label` (X = `.loword`, Y = `^label`). Do not pass Y = 0 for a
  label in the code bank. Bank 0 means "my window".
- Negative immediates are range errors in ca65 (`adc #-4`, `adc #BS / 2 - 8`): write
  `sbc #4`, or `#.loword(-4)` / `#$FFFC`.
- A constant may not have the name of a mnemonic (`STY = 8`, `BIT`, `INC`, `STA`): ca65
  says only "Expected an expression but found '='".
- Arithmetic on relocated addresses: write the whole expression inside:
  `lda #.loword(table + 3 * 16)`, not `lda #.loword(table) + 48` (ld65 "Expression too
  complex" for o65). `^label` gives the bank byte; `.faraddr label` the 3-byte pointer.
- `jmp (table,x)` reads the table in the program bank (fine: code bank); `jmp (addr)` reads
  bank 0 (your window), not the code bank.
- MVN/MVP take banks as operands: `mvn #^src, #^dst` with known labels; for a bank from
  SYS_BALLOC patch the operand at run time (the code bank is writable) or copy with
  `lda [src],y` / `sta [dst],y`. MVN changes DBR to the destination bank: restore it
  (`phb` before, `plb` after).
- Do not change DBR (PLB) without restoring it before touching your variables or calling
  ulib / ui.lib (they assume DBR = code bank).

## Syscalls

- Only carry and the documented registers are results. **N and Z keep the values from
  before the COP**: `sys SYS_READ` / `beq @eof` is wrong; write `tay` / `beq` or `cmp #0`.
- Call syscalls with A16/I16 (`rep #$30`): arguments are always taken as 16-bit.
- `print` puts its text inline in the code: branches across a few `print`s go out of
  range ("Range error"): use `jmp`, `jeq`, `jne`, `jcc`, `jcs`, `bra` only for short hops.
- `print` and every ulib / ui.lib routine clobber A, X, Y: save what you need first
  (`print` then `lda z:x` / `jsr put_dec`, not the other way round).
- ulib output is line-buffered: `jsr out_flush` before waiting for input after a prompt
  without a line end.
- Blocks with u24 fields: `.faraddr`; at run time the bank byte needs an 8-bit store or a
  16-bit store into a field whose next byte you rewrite afterwards. Keep blocks a byte
  longer than the last u24 (win_draw: 16 bytes for 15 used).
- `SYS_WEVENT` / `ui_getev` with A = 0 blocks; with A = 1 returns C set when empty.
  Programs using ui.lib must use `ui_getev`, never `SYS_WEVENT`.

## Program structure

- The entry point must be the first byte of CODE (the loader starts at $0100). Put
  RODATA / DATA in their segments, not in the middle of CODE before `start`. With
  several modules, `main.o` must come first on the ld65 line (a wildcard sorts
  `bigtext.s` before `main.s`: the program then starts in the wrong routine and seems to
  hang).
- win_draw blits (WD_BLIT / KBLIT / SBLIT / EXPAND / KSBLIT) return when the blitter has
  read your picture (Horizon 0.15): you may rewrite it right after. **`draw_list` does not**:
  it returns at once and Ali reads the sources and writes the target while you go on.
  Leave every source (and the target) alone until `list_wait` (A = 0), `vsync` or the next
  `draw_list`, which wait for it. Reading a full-screen framebuffer Ali drew into: `list_wait`
  first (it also flushes the CPU's cache).
- Sprites erased early and drawn late in a frame can be missing from a video frame
  (flicker; the emulator's screenshots show it too): erase and redraw each sprite in
  consecutive calls.
- End with `exit n`; never RTS from `start`.
- `win_close` of a window you do not own returns EINVAL (it does not close another
  program's window), so a `quit` path that closes `win` = 0 after a failed open is safe.
- `SYS_WSSTART` returns A = 1 when you started the window system (text shell): then
  `SYS_WSSTOP` before exit, or the screen stays a dead desktop. A = 0 under the Desktop:
  do not stop it.
- Controls (ui.lib) are in DATA and you must store the window number into each control's
  CT_WIN byte before drawing them.
- Sound kept playing after exit before Horizon 0.15; since 0.15 the kernel silences the
  program's channels when it ends.
- Focus (Horizon 0.15): WE_UNFOCUS comes when another window takes the keyboard; the keys
  the window held got their releases just before. A full-screen program gets it when the
  user leaves with Alt+Tab, Alt+Esc or F12.
- Zero page: ulib uses 38 bytes and ui.lib 38; about 180 are yours. ld65 fails with
  "Memory area ZP overflow" if you take more.
- Code + data + bss over 65,280 bytes: ld65 "MAIN overflow". Move tables / pictures to a
  file loaded into a SYS_BALLOC bank.

## The games round (Horizon 0.18)

- **EFAULT** from spr_set, fs_enter, draw_list, sample_play: the image / framebuffer /
  source / sample is not wholly in your memory (window bank 0 $0000-$7FFF, code bank, banks
  you allocated). Bank 0 above $7FFF is the kernel. A range may run across two of your banks
  only if they are consecutive: `bank_alloc` does not promise that, check (deepdive `getfb`).
- **Sprite images 16-byte aligned** (else EINVAL): ca65 cannot align inside the o65 segments;
  copy images to an aligned address in the window (`sta f:$001000,x`) or a bank. They must
  stay there, unchanged, while shown; freeing their bank hides the sprites.
- **Window sprites are hidden** while the window is not focused, anything covers its content
  (another window, an open menu), or a sprite is not wholly inside the content. That is not
  a bug in your positions. In full-screen mode positions are screen coordinates (320 x 180
  units in FS_320X8).
- **Palette entries show only while you have the focus** (and in full screen only while your
  screen is shown). A screenshot of the desktop with another window in front shows the system
  colours there. pal_set / ws_palette of an entry another program holds: EAGAIN.
- **Full screen is one program at a time** (EAGAIN, also while the other is in the
  background). The user can always leave (Alt+Tab, Alt+Esc, F12): handle WE_UNFOCUS (pause,
  stop samples) and WE_FOCUS (re-read `frame` so the pause is not counted as missed frames).
- fs_scroll / fs_enter EINVAL: Marga could read outside the framebuffer (check: x bytes + a
  line <= stride without HWRAP; x < stride with it; y + rows shown <= rows unless y < vheight),
  a split line odd in 320 x 180 or outside 1-359, stride not a multiple of 16, base not
  256-byte aligned.
- The split line counts 360 lines in every mode: in 320 x 180 a panel of 16 rows is split 32.
- fs_raster lines must be ascending and, with the split on, at or after the split line.
- Draw list records: A = window | count << 8 (count 1-128, not 0); LS_KEY's key is c2 (offset
  3), LS_FILL's colour c1 (offset 2); stride 0 = the width. LS_VBL goes on the first record
  of the frame's list (a later one makes Ali wait there).
- `vsync` also waits for your running list: a list started late in a frame delays the loop.

## Faults

`[kill] task N NAME cause CC addr AAAAAA pc PPPPPP` in console.txt:

| Cause | Usually |
| --- | --- |
| $02 / $03 (not the owner: read / write) | a long pointer with a wrong bank byte, an address in bank 0 at $8000 or above (the kernel), a stray store through a garbage pointer |
| $04 / $05 (bank not valid: read / write) | a pointer into a bank that was never allocated (bank byte not initialised) |
| $08 / $09 (the I/O page) | code touching $00:Dxxx: the hardware is syscall-only |
| $20 BRK | executing data: a wrong `.a8/.a16`, a bad `jmp`/`rts` (stack imbalance), falling off the end of a routine |
| $22 | XCE to emulation mode (copied 6502 code) |
| $23 | interrupts off (SEI) in a long loop |

`pc` = bank:offset; the offset is the address in the ld65 map (`ld65 -m build/x.map ...`,
CODE starts at $0100). EFAULT (A = 4, C set) from a syscall instead of a kill = a pointer
range you may not access or one crossing a bank.

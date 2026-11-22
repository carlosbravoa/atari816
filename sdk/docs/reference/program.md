# Programs: format, memory, start and exit

A Horizon program is a file `NAME.PRG` on the SD card: 65C816 code in native mode, built
with ca65 / ld65 (cc65 suite) into a relocatable o65 file. The kernel loads it into a 64 KB
bank of its own, gives it a private 32 KB "window" in bank 0 for its direct page and
stack, and runs it in user mode under memory protection.

Sources: `horizon/ABI.md` ("Program format", "Task start conditions", "Faults"),
`horizon/user/prog.cfg`, `horizon/kernel/loader.s`.

## Building

```
ca65 -I horizon/user -o build/main.o main.s
ld65 -C horizon/user/prog.cfg -o MAIN.PRG build/main.o horizon/build/ulib.o [horizon/build/ui.lib]
```

- `horizon/user/horizon.inc`: syscall numbers, constants, macros (`sys`, `print`, `ptr`,
  `exit`, `jeq`/`jne`/`jcc`/`jcs`). Include it first in every source file.
- `horizon/build/ulib.o`: the user library (output buffering, numbers, keyboard to ASCII,
  `getline`, argument parsing, `spawn`). Every program links it (the `print` and `exit`
  macros call it).
- `horizon/build/ui.lib`: the controls library (buttons, fields, lists, scroll bars,
  alerts, file dialogs). Window programs that want the standard look link it and
  include `ui.inc` (see [controls.md](controls.md)).
- `prog.cfg` links CODE, RODATA, DATA and BSS from $0100 (the loader moves them), and
  ZEROPAGE from $0000 (the task's direct page).
- `make -C horizon build/ulib.o build/ui.lib` builds the two libraries; the SDK templates'
  Makefiles do this for you.

Several source files: assemble each and list all objects on the ld65 line, **the one with
the entry point first** (the program starts at the first byte of CODE, and ld65 places
the objects' CODE in command-line order; put `.export`/`.import` on shared labels), or `.include` them into one main file (what
Horizon's own BASIC, Sheet and Write do). There are no shared libraries at run time:
everything is linked into the one file.

## Limits of the file

| | |
| --- | --- |
| File size | the o65 under 64 KB. (Horizon 0.28) The file may be larger and carry the program's own data after the o65: the loader reads only the o65 and never loads the rest. Before 0.28 the whole file had to be under 64 KB |
| CODE + RODATA + DATA + BSS | at most 65,280 bytes ($0100-$FFFF of the code bank) |
| ZEROPAGE | at most 256 bytes, shared with ulib (38 bytes) and ui.lib (38 bytes) |
| Imports | none: ld65 must resolve every symbol |
| Format | o65 "small" (16-bit sizes), byte-wise relocation; made by `prog.cfg` |

Bigger data (pictures, levels, documents) goes in banks from `SYS_BALLOC` (64 KB each),
filled from files with `SYS_READ`. To find data files next to the program, ask for its
own path with `SYS_TPATH` (Horizon 0.28; [system](system.md)) and cut it after its last
`/`.

## Memory model

| Where | What | How to address it |
| --- | --- | --- |
| Code bank, $0100.. | CODE, RODATA, DATA, BSS in that order; BSS cleared | DBR = PBR = the code bank at start: plain absolute addressing (`lda table,x`) |
| Code bank, past BSS | free, undefined contents | absolute |
| Bank 0 window $0000-$00FF | your ZEROPAGE segment (D = 0), cleared | `lda z:var` (the `z:` forces direct page) |
| Bank 0 window $0100-$7FFF | the stack (S starts just below the argument string at $7FFE) and anything you put there | `lda f:$001000` or a long pointer with bank 0 |
| Other banks | from `SYS_BALLOC`, owned by you, contents undefined | long addressing: `lda [ptr],y` with a 3-byte zero-page pointer, `lda f:addr,x`, or PHB/PLB |
| Bank 0 $8000-$FFFF | kernel | any access kills the task |
| $00:D000-$DFFF (I/O) | hardware registers | any access kills the task: use syscalls |

- **Pointers in syscalls** are X = offset, Y = bank. Bank 0 means your window. For a label
  in your program: `ptr label` (= `ldx #.loword(label)` / `ldy #^label`). A range passed to
  a syscall must not cross a bank boundary (EFAULT).
- **u24 in parameter blocks** is 3 bytes: offset low, offset high, bank. In a block in RODATA
  write `.faraddr label`. At run time: store the 16-bit offset with `sta blk+n` and the bank
  with an 8-bit store (`sep #$20` / `lda #^label` / `sta blk+n+2` / `rep #$20`), or a 16-bit
  store of the bank when the next byte may be overwritten.
- **The direct page is in bank 0, the data bank is your code bank.** `lda var` (absolute)
  reads the code bank; `lda z:var` reads the direct page. ca65 picks direct-page addressing
  automatically only for symbols it knows are zero page (declared in a ZEROPAGE segment
  earlier in the file); write `z:` to be sure.
- **Relocation** is done by the loader: `.loword(label)`, `^label` (bank byte),
  `.faraddr label`, `jsl`/`jml label`, `lda f:label` all work. Code may be anywhere in its
  bank; do not assume a bank number.
- **Self-modifying code** works (the code bank is writable), e.g. for MVN/MVP whose bank
  operands are only known at run time.
- **No heap.** Memory comes in 64 KB banks only. 92 banks on an 8 MB machine, about 88 free
  for programs; the window system takes 6 (screen) and each window a few (its bitmap).

## Register widths and the calling convention

- A program starts in native mode with **A, X, Y 16-bit** (P = $00). Assemble with `.a16`
  and `.i16` at the top. Keep them 16-bit around every syscall (`rep #$30`).
- Syscall: `sys NAME` (= `COP #n`). Arguments in A, X, Y (16-bit). Result in A (and X, Y
  where the call says). **Carry clear = OK; carry set = error, A = error code.** X, Y, D,
  DBR and the other flags come back unchanged unless the call returns something in them.
- ulib and ui.lib routines: `jsr`, A/X/Y 16-bit, and they clobber A, X, Y unless noted.
- Your own routines: whatever you like, but keep the width the assembler believes. When you
  switch, tell ca65: `sep #$20` + `.a8`, then `rep #$20` + `.a16`. ca65 does not track
  REP/SEP by itself (`.smart -` is set in horizon.inc), so a wrong `.a8`/`.a16` assembles an
  immediate operand with the wrong size and the CPU then executes garbage.

## Start conditions

| Register | Value |
| --- | --- |
| Mode | native, user mode, P = $00 (A/X/Y 16-bit, decimal off, interrupts enabled) |
| PC | code bank:$0100 (the first byte of CODE: put the entry point first) |
| PBR, DBR | the code bank |
| D | $0000 (your ZEROPAGE, cleared) |
| A | length of the argument string (0 = none) |
| X | window offset of the argument string ($7FFE - length, bank 0) |
| Y | 0 |
| S | X - 1 |

The argument string (at most 127 characters, zero-terminated) is what follows the program
name in the shell (`hello one two` gives "one two"), or what the parent passed to
`SYS_SPAWN`. ulib's `args_init` (X = its address) points `u_p` at it; `next_arg` splits it
into words ("quoted text" is one word); `parse_dec` reads a number.

```asm
start:  sta     z:alen          ; A = length of the arguments
        jsr     args_init       ; X = their address: u_p points at them
        lda     z:alen
        beq     @none
        ptr     word            ; buffer for the first word
        lda     #32             ; its size
        jsr     next_arg        ; -> A = length, C set if there was none
@none:  exit    0

        .segment "BSS"
word:   .res    32
        .segment "ZEROPAGE"
alen:   .res    2
        .segment "CODE"
```

The keyboard and the screen at start:
- **From the text shell** (or a Terminal window): the shell lends it the keyboard
  (`SYS_IREAD` reads keys), console output goes to the screen (or the Terminal).
  ctrl-C kills the program.
- **From the Desktop** (Programs menu, Files, an icon): no keyboard lent, console output
  goes only to the kernel log (DBG_OUT: the emulator's stdout, the board's PC link log). A
  program started this way opens windows and reads its keys as window events.
- A window program calls `SYS_WSSTART` first: under the Desktop it returns A = 0 (already
  running); from the text shell it starts the window system (A = 1) and the program must
  `SYS_WSSTOP` before it exits so the text console comes back.

## Exit

```asm
        exit    0               ; macro: flush ulib's output buffer, then SYS_EXIT with A = 0
```

- A program must end with `SYS_EXIT` (the `exit` macro or `jsr exit_a` with A = code).
  RTS/RTL from the entry point are not supported.
- At exit the kernel closes the program's windows, files, ports and frees its banks;
  the keyboard goes back to the lender; the pointer shape goes back to the arrow; an
  unfinished `ws_hold` is released. **Sound is not stopped**: silence POKEY yourself
  (see [sound.md](sound.md)).
- The exit code goes to the parent's `SYS_WAIT`; the shell prints it for background jobs.
  Codes $FF00 + cause mean the kernel killed the task (below), $FF80 a kill or ctrl-C.

## Faults

The kernel kills a task that touches memory it does not own, writes to its read-only
memory, touches the I/O page, executes BRK, switches to emulation mode, or keeps
interrupts off for 2 seconds (SEI and a loop). It prints on the console (and the log):

```
[kill] task 5 GEMRUN cause 06 addr 7C1234 pc 2B0345
```

| Cause | Meaning |
| --- | --- |
| $01-$1F | Protection: bit 0 a write, bit 1 not the owner, bit 2 bank not valid, bit 3 the I/O page, bit 4 the vectors. `addr` is the address, `pc` the instruction |
| $20 | BRK |
| $21 | The stack pointer was bad when the kernel was entered |
| $22 | Emulation mode (XCE) |
| $23 | Interrupts kept off for 2 s (watchdog) |

The exit code is $FF00 + cause. `pc` is the 24-bit address of the instruction: subtract
your code bank's base (the bank byte of pc, offset $0100 = the start of CODE) and look
the offset up in an ld65 map file (`ld65 -m build/main.map ...`; the map's addresses
start at $0100 too). `run816.py` prints any `[kill]` line and fails the run.

The typical causes in a new program:
- a pointer with the wrong bank (Y = 0 for a label in the code bank: use `ptr label`);
- `lda var` meant as direct page, but assembled as absolute in the code bank (or the other
  way round): use `z:` for direct page;
- a wrong `.a8`/`.a16` (an immediate operand one byte too short or too long);
- a long pointer whose bank byte was never set;
- a stack imbalance (an RTS returning to a pushed value).

## Single instance

`SYS_SINGLE` first thing in a program that should run once (an editor of the Desktop's
settings, a game that should not run twice): if it already runs, its windows come to the
front and the new copy should exit.

```asm
start:  sys     SYS_SINGLE      ; C set: already running (its windows were raised)
        bcc     :+
        exit    0
:       ; ... the program
```

## Where programs go on the card

| Folder | |
| --- | --- |
| `/BIN` | applications (the shell finds `NAME` there: type `name args`) |
| `/SYSTEM`, `/SYSTEM/TESTS` | Horizon's own programs and tests (Files refuses to start programs in /SYSTEM) |
| anywhere else | start it by its path in the shell (`/APPS/GAME.PRG`), from Files (double click), or from the Desktop's Programs menu |

To add a program to the Desktop's Programs menu, add a line `Title=/path/NAME.PRG` to
`/SYSTEM/PROGRAMS` (plain text, read when the Desktop starts; 16 entries at most).

# Roadmap notes: a C compiler for the Atari816

Research notes, no implementation. Horizon programs are written in 65816 assembly today.
This page says what a C target would need and how far the known compilers are from it.
**No compiler was tried for these notes.** What is said about the compilers comes from
the author's general knowledge as of 2026 and is marked "(unverified)" where it matters;
check the current state before choosing.

## What a Horizon C target needs

1. **Code generation for the 65816 in native mode**: 16-bit A/X/Y, 24-bit pointers for
   data outside the program's bank, the direct page as a register file.
2. **Horizon's memory model.** One code bank per program (CODE + RODATA + DATA + BSS
   at most 65,280 bytes), a 256-byte direct page shared with ulib / ui.lib (about 180
   bytes free), the stack in the task's 32 KB window in bank 0, more memory only as 64 KB
   banks from `SYS_BALLOC` (no heap: malloc would be a library on top of banks). So a
   "small" model (16-bit data pointers into the code bank, DBR = code bank) for code and
   static data, plus "far" pointers (24-bit) for big buffers.
3. **The program format**: o65 with relocations, as ld65 writes it (the loader relocates
   WORD, LOW, HIGH, SEG and SEGADR entries; no imports). Either the compiler emits ca65
   assembly (then ld65 does everything, and C links with ulib.o and ui.lib directly), or
   a converter from the compiler's relocatable objects to o65.
4. **A calling convention and syscall glue**: syscalls take A, X, Y and return carry +
   A (X, Y); C needs small assembly wrappers (`int sys_open(const char *path, int mode)`)
   or inline assembly. Callbacks from ui.lib (list rows) are JSR-called with A/X/Y 16-bit.
5. **A small C library**: string.h, a printf over ulib's output, stdio over the file
   syscalls (4 handles for the whole system), malloc over banks, no floating point
   needed at first.
6. **Headers** for horizon.inc and ui.inc (constants, structures: the win_draw block,
   events, control structures) - generated from the .inc files so they cannot drift
   (`tools/abicheck.py` already parses them).

## Candidates

| Compiler | 65816? | Output | Licence | Fit |
| --- | --- | --- | --- | --- |
| **cc65** | no: 6502 / 65C02 code only (ca65 assembles 65816, but the C compiler generates 6502 code with 8-bit registers) | ca65 assembly | zlib | see "cc65 in 8-bit native mode" below |
| **Calypsi** (Hans Hogbom) | yes: a modern C99 compiler for the 65816 with small / large memory models (unverified details) | its own ELF-style objects and linker; raw binary / hex / Foenix formats (unverified) | free to use, closed source (unverified) | good code quality reported by the Foenix community; needs an o65 converter or a Horizon output format from its author; its calling convention differs from ulib's |
| **WDC tools** (WDC816CC, from the 65816's maker) | yes | WDC object format, Windows programs | free download, closed (unverified) | old C89 compiler, runs under Wine; a converter to o65 needed; not attractive |
| **tcc-816 / 816-tcc** (the SNES homebrew fork of TinyCC, used by PVSnesLib) | yes | assembly for WLA-DX | LGPL | open source, emits assembly: a WLA-DX-to-ca65 translation (or retargeting its output stage to ca65 syntax) gives o65 through ld65; code quality is modest; old code base |
| **ORCA/C** (Byte Works, Apple IIgs) | yes | OMF objects (IIgs) | open-sourced (unverified: GitHub byteworksinc) | runs on a IIgs or an emulator of one (GoldenGate); OMF to o65 conversion; its libraries are IIgs toolbox-based |
| **vbcc** | a 6502 backend exists (65C02, by Volker Barthelmann); a 65816 backend: unverified, possibly experimental | vasm objects | free for non-commercial use | worth asking its author; vasm can emit relocatable objects that might be converted |
| **llvm-mos** | no: the 6502 family only (no W65816 target as far as known) | ELF | Apache 2 with LLVM exception | the best 6502 compiler, but adding a 65816 target is a large project |

### cc65 in 8-bit native mode (a quick path, untested)

cc65's code is 6502 code. On a 65816 in native mode with 8-bit registers (`sep #$30`),
almost all 6502 instructions behave as on a 6502, except: the stack is a 16-bit S (fine:
it lives in the task's window), page wrap-around in indexed zero page addressing differs
(cc65 code rarely relies on it), decimal-mode flag details, and BRK/COP/interrupts push
different frames (the kernel handles those). Horizon kills a task that enters emulation
mode, so the code must stay in native mode. A cc65 program would need:
- a startup in assembly: keep A/X/Y 8-bit for C, switch to 16-bit around every syscall
  (`rep #$30` / `cop` / `sep #$30`), with wrappers in a small runtime;
- cc65's zero-page use (its zp registers, `sp`) placed in Horizon's direct page;
- a linker config that puts everything in one o65 "small" program (cc65's runtime library
  linked with ld65, like ulib);
- 16-bit data only: no 24-bit pointers (big buffers through assembly helpers).
That gives C quickly, with the limits of a 6502 compiler (slow 16-bit arithmetic through
the runtime). Worth a weekend experiment before anything bigger.

## Recommendation

1. Short term: try the cc65 8-bit-native experiment above (cheapest; same toolchain, same
   object format, same linker, and C functions callable from assembly programs).
2. For a real 65816 C: ask the Calypsi author about an o65 (or a relocatable raw) output
   and a configurable calling convention; in parallel, evaluate tcc-816's output (its code
   size and speed on a few Horizon-style functions) translated to ca65 syntax.
3. Either way, generate the C headers from horizon.inc / ui.inc, and write the syscall
   wrappers once, in assembly, in a `libhorizon.lib` built like ui.lib.

## Other SDK items for later

- (Done: the joystick syscall, Horizon 0.15; full-screen mode, sprites, scrolling, draw
  lists and frame sync, Horizon 0.18: `docs/reference/games.md`, `examples/deepdive`.)
- C headers would also need the 0.18 blocks: the spr_set entry (SE_*), the fs_enter and
  fs_scroll blocks, the draw-list record (LR_* / LS_*), generated from horizon.inc like the rest.
- A shared-library mechanism (the architecture plans JSL jump tables) would let ulib /
  ui.lib / a C library be loaded once instead of linked into every program.
- An emulator option to play sound (POKEY 2 and the DACs) would let sound be heard
  while developing; today it is only logged (`--log-sound`); Lau's output can be written to
  a WAV file (`emu816 --wav`) and its writes logged (`run816.py --log-lau`).

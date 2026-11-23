# Roadmap notes

## C

**Status (November 2026): done.** The C SDK is built on cc816, the SDK's own compiler
(`sdk/c/cc816`: Python 3, writes ca65 assembly, links with ld65):
[sdk/c](../c), [docs/c/getting-started.md](c/getting-started.md).

Two compilers were tried before cc816 (cc65 and vbcc); the trials are in git history. On
the benchmark (`sdk/c/tests/bench`) cc816 is 1.0 to 3.0 times as fast as the faster trial.

## Other SDK items for later

- (Done: the joystick syscall, Horizon 0.15; full-screen mode, sprites, scrolling, draw
  lists and frame sync, Horizon 0.18: `docs/reference/games.md`, `examples/deepdive`; their
  blocks in C, `horizon.h`.)
- A shared-library mechanism (the architecture plans JSL jump tables) would let ulib /
  ui.lib / a C library be loaded once instead of linked into every program.
- An emulator option to play POKEY's sound would let it be heard while developing; today it
  is only logged (`--log-sound`). Lau and (Horizon 0.27) the OPL2 are heard: written to a
  WAV file (`emu816 --wav`) and played live by an SDL build of emu816.

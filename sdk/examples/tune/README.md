# Tune

Plays a ProTracker module with Horizon's replayer library (Horizon 0.26, Atari816):

```
> tune /Music/LAU.MOD
tune: the end
```

- `main.s` reads the file (up to 64 KB) into a bank it allocated: Lau, the sample player,
  reads the samples from there while they play.
- `mp_open` checks the module, `mp_play` starts it (its first tick runs at once).
- The **music timer** (`SYS_STIMER`) sends the program's port a message every `mp_tickus`
  microseconds; each message is one `mp_tick`. When a tick changes the tempo (`MPF_TEMPO`)
  the timer gets the new period; `MPF_END` is the end of the song.
- It runs at the shell's priority. For music that must stay steady whatever else runs, tick
  it from a task started at priority 0 — or let the engine `/SYSTEM/MUSICD.PRG` play it
  (`docs/reference/sound.md`, "Music").

## Build, run, test

```
make                     # TUNE.PRG (links horizon/build/modplay.o and ulib.o)
make run                 # plays /Music/LAU.MOD in the emulator; build/run/tune.wav is the sound
make test                # it must play to its end
```

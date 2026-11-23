# SkyRoads on the Atari816 (the road experiment, round 2)

SkyRoads (Bluemoon Interactive, 1993) from the C translation of
[SDL-skyroads](https://github.com/carlosbravoa/SDL-skyroads) (C++17, MIT). **Not a playable
port yet**: it plays the attract demo, every frame equal to the C++'s. Phase 1 measured the
road at 40 % of the original 36 frames a second; round 2 made the simulation 5 times faster,
the drawing 20 % faster and the load 8 times faster: the demo now holds 24 frames a second on
a steady beat through its busiest stretch, and loads in 4 s. `PORTING-NOTES.md` has the
numbers ("Speed, round 2"), the reasons and what 36 would need (Ali reading the runs itself).

What there is: the C translation of upstream's data loaders, simulation, app state machine
and renderer (`src/`), a PC back end with the check tools (`host/`), and a Horizon back
end that plays the attract demo full screen (`horizon/`).

## Build and run

```
make data            # the game's files: tools/getdata.sh downloads Bluemoon's freeware zip
                     # (or: make data GAME=/your/copy), decoded into data/card/ (not in git),
                     # and SKYPREP.DAT (srtool prepare: what the renderer would make at load)
make                 # SKYROADS.PRG (cc816, --code large)
make host            # build/host/srtool on the PC (demo-sim, demo-frames, demo-state, predecode,
                     # prepare, probecheck) and build/host/srsimcheck (the simulation against
                     # the one before round 2, on random ships)
make check           # the demo's 1,708 frames and its state after every tick, on the Atari816
                     # (emulator) against the PC's
make bench           # each tick's simulation and each frame's drawing timed
make sim             # the demo's ticks alone, timed (profile: RUNFLAGS="--prof FILE ...")
make beat RATE=24    # the demo shown on a steady beat (36, 24, 18; 0: adaptive): late frames
make paced           # the demo at 36 ticks a second, as many frames as it can draw
make probecheck      # the assembly probe against the C (Atari816)
make movecheck       # the assembly move_to and bounce scan against the C (Atari816)
```

On the Atari816 the program and `data/card/*` go in one folder (`/APPS/SKYROADS/`);
`SKYROADS.PRG /BEAT` plays the attract demo (after the 34 s intro's ticks, not drawn) at the
rate it holds; `/PACED`, `/BENCH`, `/SIM`, `/CHECK` are the measurements above. The game data is Bluemoon's freeware and
is not distributed here (its readme allows distribution only of the original, unmodified
archive): every user fetches it.

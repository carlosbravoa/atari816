# SkyRoads on the Atari816 (phase 1: the experiment)

SkyRoads (Bluemoon Interactive, 1993) from the C translation of
[SDL-skyroads](https://github.com/carlosbravoa/SDL-skyroads) (C++17, MIT). **Not a playable
port**: phase 1 measured whether the 65816 can draw the game's road at its speed; it
draws it exactly (every demo frame equals the C++'s) but at about 40 % of the original 36
frames a second. The port stopped there; `PORTING-NOTES.md` has the numbers, the reasons
and what would be needed (one request to Ali for many span fills).

What there is: the C translation of upstream's data loaders, simulation, app state machine
and renderer (`src/`), a PC back end with the check tools (`host/`), and a Horizon back
end that plays the attract demo full screen (`horizon/`).

## Build and run

```
make data            # the game's files: tools/getdata.sh downloads Bluemoon's freeware zip
                     # (or: make data GAME=/your/copy), decoded into data/card/ (not in git)
make                 # SKYROADS.PRG (cc816, --code large)
make host            # build/host/srtool on the PC (demo-sim, demo-frames, predecode, probecheck)
make check           # the demo's 1,708 frames on the Atari816 (emulator) against the PC's
make bench           # the experiment: each frame's simulation and drawing timed
make paced           # the demo at 36 ticks a second: frames drawn
```

On the Atari816 the program and `data/card/*` go in one folder (`/APPS/SKYROADS/`);
`SKYROADS.PRG /PACED` plays the attract demo (after the 34 s intro's ticks, not drawn),
`/BENCH` and `/CHECK` are the measurements above. The game data is Bluemoon's freeware and
is not distributed here (its readme allows distribution only of the original, unmodified
archive): every user fetches it.

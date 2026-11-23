# Porting notes: XCOM-XT on the Atari816

Stage 1 (assessment and foundation) to stage 5 (a playable app: section 4d), 23 November 2026;
the board (4e) and the alien turn (4f), 24 November 2026.

Upstream: <https://github.com/fmikowski/xcom-xt> at commit `a53918220c90` (18 November
2026, alpha 0.5.1), GPL-3. Fetched by `tools/getsrc.sh` into `upstream/` (not in git);
built from `build/src` = upstream's `src/` + `patches/src-*.patch`. The public repository
has no `docs/` and no `tests/` (BUILDING.md's links to `docs/design.md` and
`tests/README.md` lead nowhere): the design notes are the code's comments, which are
unusually thorough.

## 1. Assessment

### Sizes

C: 90 files, 49,352 lines with the headers (1.8 MB). By area (lines of `.c` + `.h`):

| Area | Lines | Files (main ones) |
| --- | --- | --- |
| Geoscape and campaign | 12,393 | geo.c 3,620, alien.c, craft.c, base.c, facil.c, airfight.c, report.c, graphs.c, items.c, rules.c, soldier.c |
| Base and UI screens | 11,984 | uik.c 1,362 (the DOS look: pictures, fonts, windows), invscr.c, labscr.c, trade.c, qlist.c, basescr.c, pedia.c, menu.c, batui.c, hud.c, panel.c |
| Battlescape logic | 12,350 | battle.c 1,677, ai.c 1,579, bplayer.c, bturn.c, effects.c, spawn.c, unit.c, path.c, los.c, vox.c, voxx.c, mapgen.c |
| Rendering and video | 3,948 | render.c, gfx.c, canvas.c (EMS/XMS canvas), cvinit.c, nlit.c (EGA night), vgainit.c, vgageo.c, hgcinit.c, cut.c (intro, slides), mouse.c |
| Data loading and memory | 4,396 | pak.c, floorld.c, picplan.c (which pictures fit), sprcache.c (disk-paged sprites), xmem.c (EMS/XMS read cache), startup.c, main.c |
| Sound | 2,149 | sound.c (PC speaker, Sound Blaster DMA, FM effects), music.c (AdLib driver), timer.c |
| Input, bench | 1,594 | input.c (keys, KEYS scripts, LOG), vbench.c (BENCH) |

Python tools: 10,544 lines (the converter XCOMCONV and its parts: convert.py, ui.py,
vgasprite.py, world.py, intro.py, sound.py, ...), plus PowerShell build and test scripts for
86Box.

### The assembly (NASM, 8086/286, 12,862 lines)

| File | Lines | What | C upstream? | Port |
| --- | --- | --- | --- | --- |
| vgaasm.asm | 2,966 | the VGA prototype: 8-bit back buffer, sprite blitters for vgasprite.py's span formats (masked, OR, clipped), clear/present/shift, the cursor box, the palette; the interface (pictures streamed from UIV.PAK to A000, glyphs, the clean screen, fills, copies, BIOS-font text, the pointer); the arrow; smoke/fire overlays and DOS's smoke pictures; night lights (OpenXcom's terrain lighting, shade tables) | no | interface: **C** (`plat/vga.c`); battle view entries 0-8, 22-26: **C** (`plat/vgabat.c`), except DOS's smoke/fire pictures and the per-cell night lights (one night shade for now) |
| vgxasm.asm | 866 | VGA outside the battle: DOS palettes per screen (PALV.PAK), VGA themes, the geoscape world view with zoom, markers | no | **done in C** (`plat/vga.c`) |
| xmemres.asm, xmemhma.asm | 1,571 | EMS/XMS read cache hooked into INT 21h, HMA variant | no | not needed (all data fits in memory) |
| rendasm.asm | 957 | the battlescape's floor pass (render.c draw_region): per level the tiles under the redraw rectangle, floors drawn, walls/objects/units collected | no | **C** (`plat/rend.c`) |
| pathasm.asm | 955 | path search (Dijkstra with cost buckets) | **yes**: `path_search_c` (vbench.c) | the C one now |
| blit.asm | 838 | EGA planar blitters | (EGA) | never used |
| voxasm.asm | 739 | the voxel line (OpenXcom calculateLine + voxelCheck) | no (OpenXcom's C++ is the reference) | **C** (`plat/voxrun.c`): 0 mismatches against OpenXcom's lines in 1,165 lines checked (below) |
| losasm.asm | 547 | fog of war: the fan of sight rays | no | **C** (`plat/losfan.c`; no independent reference yet) |
| blitc.asm | 441 | CGA blitters (the VGA path keeps their names and arguments) | (CGA) | the names are the VGA entry points |
| rdcount.asm | 404 | INT 21h read counter, the mode folder for opens | no | C (`plat/xdos.c`: the mode folder; counts 0) |
| hgcasm.asm | 379 | Hercules | | never |
| litasm.asm | 346 | EGA night light | | never |
| sndasm.asm | 294 | XMS driver calls, disk-paged sprite faults | | not needed |
| heldasm.asm | 282 | the inventory's held item at the pointer | no | to C (stage 2) |
| cvasm.asm | 232 | EMS/XMS canvas copies | | not needed |
| cutasm.asm | 228 | intro frame deltas (EGA/CGA runs, VGA FLI chunks) | no | FLI to C (stage 4) |
| fxasm.asm | 215 | dithered smoke/fire overlays EGA/CGA | (VGA's in vgaasm) | via vgaasm's entry 23 |
| arrow.asm | 211 | the selected unit's arrow | no | to C (stage 2) |
| uiasm.asm | 173 | EGA night colours of the panel | | never |
| video.asm | 106 | mode set, Hercules stubs | | C |
| wayasm.asm | 67 | blaster bomb waypoints' door walk | no | **C** (`plat/way.c`) |

Plus Watcom `#pragma aux` inline code in 7 files: `rl_imul`, `rl_mul14` (rules.h), `zoom_bytes`
(geo.c), `cpu_below_286` (3 files), the SB and timer interrupt stacks: all C now
(`plat/asm.c`, the patch). The VGA mode needs about 6,900 of the 12,900 lines rewritten
(vgaasm, vgxasm, rendasm, losasm, voxasm, wayasm, heldasm, arrow, cutasm's FLI); only
pathasm has a C twin. Done in stage 1: all but heldasm, cutasm's FLI, vgaasm's night
lights and smoke pictures (about 600 lines of asm left). Upstream's own test, `BENCH` (vbench.c), times the renderer, the
logic and the voxel lines: a ready harness for the later stages.

### Memory model

- Open Watcom `wcc -ml` (large: far code, far data), `-0/-1/-2` (8086/186/286 builds),
  speed (`-ox`) or size (`-os`) per file, `-zc` (an overlay's strings in its code segment:
  the 64 KB DGROUP was full).
- **Dynamic overlays** (WLINK `option dynamic`): about 45 sections (geoscape, battle core,
  AI, each base screen, ...) sharing one overlay area; build.ps1 computes the area from sets
  of sections that must fit together, and patches a bug of Watcom's overlay manager
  (ovlfix.ps1). Overlays are transparent to the C: `-NoOverlay` links everything resident.
  The port links everything resident.
- **The 640 KB**: DGROUP (64 KB: globals, constants of resident modules, the battle's lists
  from the near heap sized at start, `lim_init`), the far heap (malloc, `alloc_para`: blocks
  at offset 0 of their own segment so the assembly can index them), DOS blocks
  (`_dos_allocmem`: the map buffer 39 KB, path/sight tables 100 KB, sprite banks, the world
  map, the base block). The engine plans by DOS's free memory (`picplan.c`: which unit
  pictures fit, shared pictures, disk-paged sprites in tight battles); UMBs hold the map
  buffer and overlay areas; EMS/XMS hold a 2 MB read cache, a picture store and (EGA) a
  canvas. VGA needs 256 KB of XMS (its battle pictures).
- Pointers: every plain pointer is far (seg:off); segment arithmetic is common
  (`MK_FP(FP_SEG(p) + ((FP_OFF(p) + 15) >> 4), 0)`, tables before a block at negative
  segment offsets, segments passed to the assembly as `unsigned`). 229 MK_FP/FP_SEG/FP_OFF
  in 41 files; 61 explicit `__near` (hot data in DGROUP).

**How it maps here (`compat/xdos.h`, `plat/xdos.c`).** The port models the DOS machine
instead of rewriting the engine's memory code: real mode's first megabyte is an arena
(host: one allocation; Atari816: 17 banks, `xd_banks[]`), `MK_FP(s, o)` is byte `s * 16 + o`
of it, and the engine's heap (malloc and `_dos_allocmem` alike) is a DOS memory chain with
MCBs in its first 640 KB, so every segment trick works as on DOS. `FP_SEG`/`FP_OFF` give a
heap pointer its block's segment (the engine makes pointers as `MK_FP(seg, 0) + offset`
and takes the segment back: `geo.c`'s zoom table). A block never crosses a 64 KB line (a
bank: so a far pointer's 16-bit arithmetic stays right), as a DOS block never passes 64 KB.
A000 is the VGA picture, B800 the CGA page, 0040:006C the BIOS clock, F000:FA6E the 8 x 8
font (`plat/font8x8.h`), the PSP and the program's MCB where `main.c` reads them. INT 10h,
21h (memory, version, list of lists), 33h (mouse), 16h, 2Fh (no XMS), 67h (no EMS) and the
ports (VGA DAC, OPL2 388h/389h, retrace) are answered by C. Files: DOS names (`\`, case),
the mode folder (`VGA/` first for read-only opens, as rdcount.asm's INT 21h hook does).

On the Atari816 this model needs **far data pointers by default**: a plain `T *` in the
engine is a DOS far pointer, but a cc816 plain pointer is a 16-bit offset in the main bank.
See section 4; since stage 3 the SDK has it (`hcc --data far`, section 4b).

### Video: the 286 VGA path

- Mode 13h, 320 x 200 x 256, one page, no page flipping, no Mode X. Not a separate
  renderer: **the game runs as on CGA** (`g_video = VIDEO_CGA`) and `vga_init` patches the
  first bytes of the resident CGA routines (blitters, clear, present, shift, cursor box, UI
  pictures, glyphs, fills, HUD text, the pointer) into far jumps to vgaasm.asm's code copied
  to the heap. CGA buffer offsets are a quarter of the VGA ones (sprite x a multiple of 16).
- Battle view: an 8-bit back buffer of 320 x 144 (the view above the 56-row panel),
  sprites in tools/vgasprite.py's span formats (masked: transparent spans; OR: ground floors
  on a cleared area), drawn by the floor pass (rendasm.asm) then walls/objects/units by
  render.c, presented by rectangles of 8 x 8 cells (`gfx_present_cells`); scrolling moves the
  buffer (`buf_shift`) and redraws the strip. Dirty rectangles everywhere: a cursor move
  redraws its box (`rcursor.c`), a walk the tiles around it.
- Screens outside the battle: pictures (full-screen backgrounds, windows, buttons, item
  pictures) streamed from UIV.PAK (4.8 MB, a byte a pixel, masked ones with 0 clear) straight
  into A000; the "clean screen" for restoring under windows is not a copy but the list of
  pictures drawn (read again from the pack). Each picture's tag selects one of DOS's 5
  palettes (PALV.PAK: geoscape, basescape, graphs, UFOpaedia, battlescape) and a window
  ramp; themes (button colours) per palette. Fonts are the original BIGLETS/SMALLSET as 1-bit
  glyphs (`uk_glyph_cga`).
- Geoscape: a flat 320 x 160 world map (WORLDV.PAK, a byte a pixel), a 256 x 160 view with
  zoom 1, 2, 4, the 64-pixel button panel on the right, a message line below; markers are
  3 x 3 DOS pictures.
- Palette: the DAC (6-bit values), set at screen changes; fades are not used.
- Intro and end slides: FLI chunks (INTROV.PAK), slides with their own DAC.

How it maps (stage 1, `plat/vga.c`): the same entry points in C, called from the patched
upstream functions when `g_vga` is set (no self-modifying code). On the Atari816 A000 *is*
the full-screen framebuffer (320 x 200, stride 320, one bank: `horizon/hz_plat.c`), so the
engine's drawing is the screen's, nothing copied.

### The screen: 320 x 200 on 320 x 180

The VGA screenshots (upstream `release/screenshots`, lines at rows 20 and 180 drawn on
them) show:

| Screen | Rows 0-19 | Rows 180-199 | Proposal |
| --- | --- | --- | --- |
| Battlescape | map view | panel: soldier name, TU/health/energy/morale bars | **split**: the panel (rows 144-199, 56 rows) always shown at the bottom (Marga split at screen line 124); the view above shows 124 of the 144 rows, following the cursor / centring as the engine scrolls. Lose 20 rows of map only |
| Geoscape | map, INTERCEPT button | message line (row ~165) and the rotate/zoom buttons | **pan**: the 180 rows shown follow the pointer (`offset = pointer_y * 20 / 179`: every row reachable, the view moves 1 row per 9 of the pointer). Alternative: move the message line to rows 160-170 (it is drawn by hud.c) and show rows 0-179 (the zoom buttons' lower third cut): rejected, the buttons matter |
| Basescape, base screens | title, funds | GEOSCAPE button, last grid row | pan (as above) |
| Inventory | soldier name, OK and arrow buttons | ground grid | pan |
| UFOpaedia, briefings, reports, menus (windows centred in 200) | window frames | window frames | pan; windows centred: rarely needed |

Panning is one `hg_scroll` per change (free) and works for every screen without touching
the engine; it is in `horizon/hz_plat.c` now. The battlescape's split needs the engine to say
"battle" (the view's size is `VIEW_H`, a constant; the split is the platform's).

**640 x 360?** It would show the whole 320 x 200 at 1:1 in a 640 x 360 screen (a window
half the monitor's size, black around), or need 2 x 1.8 scaling (no hardware scaling). Text
is the original's 8-pixel fonts either way, so 640 x 360 gains nothing in legibility, costs
four times the framebuffer (230 KB) and the blitter's time, and looks small. Keep 320 x 180
with pan and split; a "whole screen" option at 640 x 360 (1:1, centred) could be added for
players who prefer no panning (cost: the same drawing, the framebuffer at an offset).

### Input

Mouse-driven UI with keyboard equivalents for everything (BUILDING.md's tables). The engine
reads the mouse through INT 33h (positions, buttons, press counts: `mouse.c`) and draws its
own pointer (OpenXcom's arrow, 9 x 13, in palette colours; an hourglass when busy); the
keyboard through BIOS INT 16h (scan << 8 | ASCII). On Horizon, a full-screen hgame program
gets `hg_mouse_x/y` in screen pixels (320 x 180) and buttons; the port adds the pan offset,
counts presses for INT 33h function 5, and turns `hg_key_next` (HID usage + character) into
BIOS codes (`horizon/hz_plat.c scan_of`). Upstream's KEYS scripts (keys, CLICK x y, HOLD,
MOVE, WAIT) work unchanged on both platforms: they are the tests' input.

### Sound

- Music: `music.c` is a complete AdLib driver in C (the original's tracks converted to its
  own format, MUSIC.PAK) that writes OPL2 registers through `outp(0x388/0x389)` from a
  72.8 Hz timer hook. The port keeps it: the model's port 389h calls `hg_opl_write`, the
  hook runs from `timer_read` and `xd_poll` when due (`plat/timer.c`). Stage 4: the hook
  from Horizon's music timer (`hz_sample_timer`, as `ports/digger/horizon/hz_timer.c`), so
  that it keeps time while the engine draws.
- Effects: OPL2 FM versions (the same driver), PC speaker (PIT channel 2: to POKEY's 16-bit
  voices), Sound Blaster 8-bit DMA of 4-bit samples (SOUNDS.PAK, 23 effects): to Lau
  (`hg_sound_from`, samples in far memory; the 4-bit decoding at load).

### Saves and files

Ten slots XCOMXT0-9.SAV, raw `fwrite` of the engine's structures (bases block, soldiers,
craft, the battle state). Files: stdio (`fopen`), POSIX `open/read/lseek` and DOS
`_dos_open/_dos_read`, `_dos_findfirst` for the pack lists. Horizon has 4 open files for
the whole system: the engine keeps UIV.PAK open while a screen is up (`uk_hold`), a
mission pack during the setup, the LOG: within 4, to watch in stage 2. **The DOS game's
own saves (GAME_1..GAME_10 in the user's folder) cannot be read**: the engine has its own
save format and no importer (checked: no reader of SAVEINFO.DAT, SOLDIER.DAT, ...).

### Timing

The PIT (1,193,182 counts a second) read directly (`timer_read`, `timer_pace`), INT 08h
hooked at 72.8 Hz for the music, the BIOS clock at 0040:006C for coarse waits. The geoscape
steps about 8 times a second by the clock (`geo.c`: 120 ms a loop unless a key comes);
battle animations are paced by `timer_pace` (the Game Options' speeds). The game logic does
not depend on the clock otherwise: a run with the same KEYS script is the same at any speed
if the clock is virtual. The port's clock (`plat.h`): real time in play, or a virtual clock
(each reading moves it 60 counts, a wait by its length) for tests: the host always, the
Atari816 with `/V`, so the two can be compared run for run.

### Watcom specifics and how each is handled

| Construct | Count (upstream) | Handling |
| --- | --- | --- |
| `far`, `__far` | 133 `__far`, `far` on about 290 lines | `#define far __far` (cc816) / nothing (host); see the data model |
| `__near` | 67 | nothing (near is cc816's default) |
| `__cdecl`, `__pascal`, `__interrupt`, `__loadds` | 86 + 4 | nothing |
| `#pragma aux` | 10 in 7 files | C functions (`plat/asm.c`; `geo.c`'s static `zoom_bytes` by the patch); cc816 ignores the pragma silently |
| `int86`, `int86x`, `intdos`, `intdosx`, `intr`, `segread`, `union REGS`, `union REGPACK` | 82 calls in 18 files | `compat/xdos.h` + `plat/xdos.c`: the services answered |
| `MK_FP`, `FP_SEG`, `FP_OFF` | 229 in 41 files | the arena (above) |
| `_dos_allocmem/freemem/setblock`, `_dos_open/read/close/findfirst/findnext`, `_dos_getvect/setvect` | 88 | the model |
| `inp`, `outp`, `outpw` | 193 in 13 files (EGA registers mostly, the DAC, OPL2, PIT, SB) | the model's port table |
| `_fmemcpy`, `_fmemset`, `_fmemcmp`, `_fmemmove` | 63 | the near ones (host); see the data model (816) |
| `_psp`, `__argc/__argv`, `_amblksiz`, `_nmalloc`, `_fheapshrink`, `_ovl_addarea` | a few | the model |
| `stricmp`, `strupr` | 63 | `strcasecmp`, a C `strupr` |
| `getenv` (BLASTER, XCV, XPIC, XWALK, XLIT) | 9 | none set |
| self-modifying hooks (`vgainit.c`, `vgageo.c`: code bytes of C functions overwritten) | 2 files | replaced by `plat/vga.c`; the hooked functions call it (the patch) |
| `T far *a, far *b;` (a qualifier before a later declarator's `*`) | 8 lines | one declarator a line (the patch): cc816 rejects it ("Invalid declarator") |
| far function pointers `void (__far *f)(void)` | 4 | not needed in the port (the patch, `xd_isr`) |
| 8.3 names, `\` | in strings | the model's file names |

Nothing else of C was missing in cc816: no VLAs, no `long long`, floating point in 19 lines
(statistics), 16-bit `int` assumed throughout (the engine *is* 16-bit code: cc816's 16-bit
int is an advantage; the host's 32-bit int is the exception, see "The host build").

## 2. What was built

| Path | What |
| --- | --- |
| `tools/getsrc.sh` | upstream at the pinned commit into `upstream/` |
| `tools/getdata.sh` | XCOMCONV (with `patches/tools-*.patch`) on your copy into `data/packs/` |
| `tools/mkpatch.sh` | the patch from a pristine and an edited copy of `src/` |
| `tools/mkfont8.py` | `plat/font8x8.h` (the BIOS font) from a Linux console font |
| `patches/src-0001-port.patch` | the changes to upstream (13 files, about 180 lines added, all `#if defined(XCOM_PORT)`): the VGA hooks (uk_*, hud_*, ms_*, gfx_night, gfx_dot, pics_next, vgageo.h's entries), `zoom_bytes` in C, one far declarator a line, no far function pointers, vbench's VGA block reads left out, `pak.c`'s unit_base read as u16 |
| `patches/tools-0001-he-type.patch` | the converter takes the GOG copy (below) |
| `compat/` | `xcompat.h` (given to every file: keywords, `long` 32 bits on the host), `xdos.h` (the DOS machine), `xport.h` (the hooks), Watcom's headers (`i86.h`, `dos.h`, `conio.h`, `bios.h`, `malloc.h`, `io.h`) |
| `plat/` | `xdos.c` (the DOS model), `timer.c` (upstream's timer.c's interface on the platform's clock), `vga.c` (vgainit + the VGA interface + vgxasm in C), `vgabat.c` (vgaasm's battle view), `rend.c` (rendasm), `losfan.c` (losasm), `voxrun.c` (voxasm), `way.c` (wayasm), `asm.c` (every other assembly routine: C or a stub that says so once), `plat.h` (the back ends' interface) |
| `host/host.c` | the Linux back end: headless, virtual clock, pictures (PPM) whenever the screen changed at a wait, the end after 30 s of no input |
| `horizon/hz_plat.c` | the Atari816 back end: arena in 17 banks, A000 = the framebuffer, pan, keys, mouse, OPL2, clock |
| `tests/geo.keys`, `tests/battle.keys`, `tests/runs`, `tests/host.sh`, `tests/host.md5` | the host's reference runs (`make check-host`): a new game to the geoscape, base, UFOpaedia, graphs; a quick battle (FA1, sectoids, seed 1); 14 pictures checked by MD5 (no picture of the game in git) |
| `tests/bench816/` | the Atari816 measurements (section 3) |
| `Makefile` | `src`, `data`, `host`, `host-run`, `check-host`, `refs-host`, `XCOM.PRG` |

### The converter

`python3 tools/xcomconv.py GAME -o OUT` runs on Linux with Python 3.12+ (3.14 here) and
PyYAML; 33 s for all three modes (EGA 15 MB, CGA 9 MB, VGA 18 MB, shared 0.3 MB). The
user's copy is the **GOG edition**, which is not DOS 1.4 byte for byte: BIGLETS.DAT (44,288
bytes against 32,768), SMALLSET.DAT and ENGLISH.DAT differ (the Collector's Edition fonts
and texts), and several terrain MCD records have HE_Type 1 (smoke, in OpenXcom's terms: the
UFOs' power-source parts, a URBAN record), which convert.py refuses. `--skip-check` passes
the first; `patches/tools-0001-he-type.patch` leaves those records out of the "explodes"
list (the engine knows only high explosive; they break without a blast). The fonts converted
fine (the menus' text looks right). To report upstream: GOG data.

Format decision: **the VGA packs as they are for stage 2**, read by the engine's own
loaders (the port must run upstream's code unchanged). In stage 3 a second build-time step
(`tools/mkatlas.py`, run on the PC after XCOMCONV) turns the battle sprites (VGA packs'
span-coded sprites) into blitter atlases in far memory, as `ports/prince` did, because the
CPU cannot draw them fast enough (section 3). UI pictures stay streamed from UIV.PAK (the
card reads straight into the framebuffer).

### The host build

`make host`: gcc, 64-bit Linux, all 87 upstream files that the port builds (timer.c,
vgainit.c, vgageo.c are replaced) plus `plat/` and `host/`. Run in the packs folder:

```
make host-run ARGS="VGA NOINTRO KEYS $PWD/tests/geo.keys LOG LOG.TXT"
```

It starts, finds the packs (`mode: VGA (forced ...)`, `packs format 4`), draws the start
menu, takes "N ENTER ..." to a new game, places the base and runs the geoscape, the
basescape, the UFOpaedia and the graphs: every picture identical in layout and colours to
upstream's VGA screenshots. Ten pictures, 6.4 s of virtual time, under a second of real
time. `VGA` is forced: without XMS the engine would pick EGA (to change in stage 2: report
XMS, or make the port's mode the default).

Semantics on the host (since stage 4a): **DOS's 16-bit `int`**. `tools/host16.py` rewrites
the host's copies of every source and header (upstream's, `plat/`, `compat/`, `host/`, in
`build/host/s16/`): `int`, `signed`, `short int` become `short`, `unsigned` and `unsigned
int` become `unsigned short`, `long int` becomes `long`, which `#define long int` keeps at
32 bits; strings, comments and `#include` lines are left alone, `main` and the type in
`va_arg` stay native, and a line marked `host16: native` too. `#pragma pack(1)` from the end
of `xcompat.h` on (cc816 packs every structure; upstream's own `pack()` lines become
`pack(1)`, the system headers are wrapped in `pack(push)`/`pack(pop)`), so the host's
structures and files have the Atari816's layout: **a geoscape save is byte for byte the
same on both** (12,100 bytes, `make test`'s save run). The printf wrapper prints plain
`%d %u %x` as 16-bit values. What still differs: C promotes a `short` to the host's 32-bit
`int` in expressions, so an unsigned 16-bit difference that goes negative, or a product
that overflows 16 bits before it is narrowed, can differ from DOS (none found in the
runs); and pointers are 8 bytes on the host (the sprite pointer tables of `pak.c`, about
250 entries: the host's "KB in all" is 433 against 434, the one allowed LOG difference).
No saved structure holds a pointer (checked: `geo_body`, `base_save_body`, `alien_save`,
`menu_save`; battle saves not yet tested). The 32-bit fault the old host had in "KB in all"
(`main.c dos_total_kb` read a segment through an `unsigned far *`) is gone with it.

Battles run on the host too (a helper agent wrote the battle side in parallel): quick
battles to "Mission successful", walking, reaction fire, alien turns. Checked with upstream's
own tests: BENCH's self-checks ("VGA sprite check: 470 draws, 0 differ", "check covered
sprites left out: 12 views, 0 differ", cursor, arrow, scrolls: "0 screen bytes differ, full
redraw same", path search C = asm entry), and upstream's `voxcheck.py` (OpenXcom's voxel
lines replayed in Python): BENCH's 720 lines and 445 shots of SHOTLOG battles on six
terrains, 0 mismatches. `sightcheck.py`: never more sight than DOS's voxel sight. Not yet:
DOS's smoke and fire pictures (the dithered shapes instead), the per-cell night lights, the
inventory's held item (heldasm), the intro (FLI), sound output (the OPL writes can be
logged: `-opl FILE`). BENCH on the host gives the counts but no times (virtual clock): a
full redraw of one level at the map's middle draws 51 masked + 37 OR sprites; all four
levels about 2-3 times that.

`upstream/tools/voxcheck.py` reads `vcol` at the wrong offset for pack format 4 (a fixed copy
in the agent's scratch): to report upstream.

### The Atari816 build

`make`: every upstream file compiles with cc816 (`hcc --code large`), after the 8 lines of
"one far declarator a line" and the far function pointers in the patch. Warnings with
`-Wall`: 80 `-Wfar-pointer` and 22 `-Wfar-cast` (a far address put in a plain pointer: the
data model, below), 3 implicit declarations (fixed: `unistd.h` in xcompat.h), 2 overflow
constants (harmless), 14 others.

The link fails:

```
hcc: XCOM.PRG does not fit in its code bank (the main bank), by 18,428 bytes
```

| Part of the main bank | Bytes |
| --- | --- |
| constants (RODATA: strings, const tables) | 51,058 |
| bss | 24,705 (+1,600 with the battle view's buffers: over by 18,428 now) |
| data | 268 |
| code that must stay (startup, libraries' assembly) | 5,430 |
| heap + software stack (8 KB + 8 KB as linked) | 16,384 |
| movable code (in other banks) | 578,218 in 1,823 functions (9 banks) |

Biggest contributors: items.c (4,966 of tables), unit.c (5,037 bss), geo.c (4,190), xdos.c
(3,695: the port's buffers, movable), vbench.c (2,957 strings), vga.c (2,614), main.c,
sound.c, pak.c; the rest are the screens' strings (DOS put them in code segments with `-zc`).

## 3. Measured (Atari816, emulator)

The engine cannot run on the 816 yet, so the VGA path's work was measured with the real
packs on the card by `tests/bench816/bench.c` (emu816, Horizon 0.30, REV $0C; the emulator
models the board's memory timing within about 5 %, but not the card's speed):

| Work | Time |
| --- | --- |
| a full-screen picture from UIV.PAK into the framebuffer, `read()` in 512-byte pieces + far copies (what `_dos_read` does now) | 132.8 ms |
| the same, `hz_read` straight into the framebuffer | 1.4 ms in the emulator (the board's card: about 170 KB/s, so about 0.38 s, as an XT's disk) |
| geoscape world view 256 x 160, zoom 0 (row copies, MVN) | 46.5 ms |
| the same zoomed 2x / 4x (C byte loop through far pointers) | 351.6 / 277.4 ms |
| battle view present, 320 x 144 back buffer to the screen (MVN) | 40.4 ms |
| one 32 x 40 masked sprite, C byte loop through far pointers (as vgaasm.asm's spans would be in C) | 8.76 ms |
| the same as 40 MVN spans of 24 bytes | 2.36 ms |
| the same by the blitter (hgame image, keyed, 300 queued, one flush) | 0.29 ms |

What it says:
- **The battle view cannot be drawn by the CPU.** A full redraw draws hundreds of sprites
  (floors, walls, objects, units over 4 levels; upstream's BENCH reports the counts: to be
  measured on the host in stage 2): at 2-9 ms a sprite that is seconds per redraw, against
  0.2-0.3 s on an 8 MHz 286. At 0.3 ms a sprite the blitter makes a full redraw about 0.1 s
  (300 sprites): **the battle sprites go to blitter atlases** (stage 3), the floor pass emits
  sheet records instead of calling span blitters, and the back buffer is a framebuffer page
  (the present becomes a blitter copy, or a page flip).
- **Pictures**: read them straight into the framebuffer (`hz_read` into far memory), not
  through the POSIX read-ahead: 133 ms of CPU per screen otherwise. Then the card's speed is
  the cost, as on DOS (upstream's EMS/XMS cache trick has its equivalent: keep UIV.PAK's
  pictures in far memory once read, 4.8 MB, or the pictures of the current screen).
- **Geoscape**: zoom 1 and 2 need an assembly row-doubler or two passes (a doubled row, then
  MVN copies of it): about 30 ms. Zoom 0 at 46 ms is fine (it draws at scroll and zoom
  changes only).
- The C library's `read` into a near buffer and cc816's far byte loops (about 120-200
  cycles a byte with a test) are the costs to avoid in every hot path.

## 4. SDK needs and cc816 problems (not changed: notes for the SDK)

| # | What | Kind | Minimal case |
| --- | --- | --- | --- |
| 1 | **A far data model.** A DOS large-model program's plain pointers are far (seg:off); its heap is far. cc816's plain pointers are main-bank offsets, so the engine's 640 KB of data cannot be reached without changing every pointer declaration of 49,000 lines (80 `-Wfar-pointer` sites are only where a far value is visibly assigned; every malloc'd structure is the rest). Needed: an option (`--data far`) under which unqualified data pointers are 32-bit far pointers, `__near` gives a main-bank one, malloc/calloc/realloc/free allocate far (blocks within a bank, like DOS's), string literals and statics may live in far banks, and the C library takes far pointers (strlen, memcpy, sprintf, fread/fwrite, ...). This is Watcom's `-ml`; it would serve every large-model DOS port. Objects never cross a bank, so pointer arithmetic stays 16-bit on the offset, as Watcom's far pointers do. | cc816 + libc feature | `char *p = malloc(40000); p[39999] = 1;` (with `--data far`: works in any bank; today: the heap is the main bank's, 40,000 bytes never fit beside 76 KB of constants and bss) |
| 2 | **Constants and statics outside the main bank.** 51 KB of constants + 25 KB of bss do not fit 64 KB even with no heap or stack. With (1) they could go to far banks; without it, a per-file option (`--rodata far` for files whose strings are only passed to the engine's own functions) would do. Same wish as skyroads' #10 | hcc/cc816 | `static const char *const names[] = { "a", ... }` in 90 files: the main bank fills with strings |
| 3 | `T __far *a, __far *b;` and `int a = 1, __far *p;` are refused ("Invalid declarator"). Watcom and Microsoft C accept a far qualifier before a later declarator's `*`; it appears in 8 upstream lines. Known (pitfalls.md says "not C"); accepting it as `T __far *b` would make DOS code compile unchanged | cc816 extension | `unsigned char __far *p, __far *q;` |
| 4 | Far function pointers: `void (__far *f)(void);` refused. cc816 has no far code pointers (the large model's function pointers are main-bank thunks), so the right answer may be to accept `__far` there and ignore it, with a warning | cc816 | `void (__far *fp)(void);` |
| 5 | `#pragma aux name = "..."` is ignored silently: a function defined only by its pragma becomes an undefined symbol at the link (or a static one never defined). A warning ("Watcom inline code ignored: name needs a C body") would point at all 10 at once | cc816 diagnostic | `#pragma aux f = "nop"` then `int f(void); int main(void){ return f(); }` |
| 6 | Far byte loops are slow: `if (*s) d[k] = *s;` over far pointers runs about 120-200 cycles a byte (8.8 ms for a 32 x 40 sprite) | cc816 speed | the sprite loop in `tests/bench816/bench.c` |
| 7 | `read()` into a near buffer + `hz_far_copy` is the only portable way to read into far memory, 100 times slower than `hz_read` into it: a `read_far(fd, void __far *, n)` in the library (honouring the read-ahead) would be the right tool | libc wish | `tests/bench816/bench.c` pictures |
| 8 | `od65` (cc65's object dumper) is not installed on the build machine, and hcc has no per-module size report: the main bank's parts per file came from `--keep`'s trial map. `hcc --sizes` (per object: constants, data, bss) would help every port | hcc wish | |
| 9 | **hgame's full screen gets no pointer motion without a button**: `hg_screen_fb` opens its window without `WF_HOVER`, so `hg_mouse_x/y` move only while a button is held; a mouse-driven game's pointer does not follow the mouse. The port reads `ws_mouse` itself. Wanted: `WF_HOVER` for full-screen windows (or an `HG_MOUSE` flag) | hgame | `hg_screen(HG_320X180, "t"); while (hg_frame()) printf("%d\n", hg_mouse_x);` with the mouse moved, no button: the value never changes |
| 10 | **No way to send a scroll/split without a frame**: a program that keeps its own time (a DOS port: `hg_poll`, never `hg_frame`) cannot make `hg_scroll`/`hg_split` take effect; the port calls `hz_fs_scroll(&hg__scr)` on hgame's internal block. Wanted: `hg_view_send()` (or `hg_poll` sending a changed scroll) | hgame | `hg_screen_fb(HG_320X180, "t", 320, 200); hg_scroll(0, 20); for (;;) hg_poll();`: the view never moves |
| 11 | `read()` returns `int`: with 16-bit int a read of 32,768 bytes or more looks negative (`k < 0` taken for an error). The port tests `k == -1`. Wanted: a line in c-library.md (or `ssize_t` as `long`) | libc doc | `int k = read(fd, p, 40000u); if (k < 0) ...` |
| 12 | **A far pointer plus an int that overflowed.** `cost + 4 * TILES` (an enum, 4 x 10,000 = 40,000: -25,536 in 16-bit int) wrapped back to offset 40,000 on DOS (Watcom adds to the offset alone); cc816's 24-bit far pointer goes 25 KB back into another block (here: the path search's bucket array over the walk tables, every alien path different from the host's). Documented as unsupported (reference.md, "Arithmetic"); `-Woverflow` finds it (2 sites in 49,000 lines), but the port builds with `-w`. Wanted: `-Woverflow` on even under `-w` (it is never harmless next to a far pointer), or an int addend added to the offset alone, as an element access already is | cc816 | `unsigned char __far *p = ...; enum { T = 10000 }; unsigned short __far *b = (unsigned short __far *)(p + 4 * T);` |
| 13 | **Argument evaluation order.** cc816 evaluates a call's arguments left to right, gcc and Watcom right to left; `hurt(u, roll_damage(), rl_side())` (both call `rnd`) drew the random numbers in the other order: different damage than DOS. Unspecified in C, but every DOS port depends on it somewhere. Wanted: a warning when two arguments of one call both call functions (or an option for right-to-left) | cc816 | `int a(void), b(void); void f(int, int); f(a(), b());` |
| 14 | Horizon: no bank can be shared by two tasks (a helper task reading the game's memory is killed, cause 02): the music task loads MUSIC.PAK itself (2 banks) | Horizon note | |
| 15 | run816.py: the emulator always runs to `--seconds`, also after the program has ended: a test suite pays for the longest run's budget in every run (tests/check.sh gives each run its own `s=N`). Wanted: `--stop-on TEXT` (end the run when the console shows TEXT), or end at the program's exit in shell mode | tool wish | |
| 16 | console.txt and `--log-lau` have no emulated-time stamps: a test cannot line up the program's phases (an alien turn) with `--log-opl-us` | tool wish | |
| 17 | The Desktop leaves 3,136 KB free of 8 MB at a program's start (emu816, Files open): an app's `mem=` must fit that | note | `--needs mem=4096K` refused: "XCOM needs 4096 KB of free memory (3136 KB free)" |
| 18 | **ca65 takes a small constant as a direct-page address**: `lda V_N,x` with `V_N = 62` (a field's offset in a block whose address is in X, DBR the main bank) is assembled as `lda dp,x` (B5 3E): it reads the direct page in bank 0, not the block; a store there trashes the direct page or kills the task (cause 02, an address in bank 0). The SDK's own assembly addresses blocks by symbol (`_hz_ph+44`: absolute), so this only bites a routine that takes the block's address at run time. `a:V_N,x` forces absolute. Wanted: a line in reference.md ("In the large code model" / "Movable assembly"), or a `-W` in hcc's ca65 call for `dp,x` with a constant below 256 in a FUNC segment | doc | `.p816` `.a16` `.i16` `V_N = 62` then `lda V_N,x` assembles to `B5 3E`; `lda a:V_N,x` to `BD 3E 00` |
| 19 | prof816: `--prof-from/--prof-to` count from the program's start, `--console-times` from the machine's (in shell mode the program starts about 4.75 s later): a window taken from the console lands seconds late. And only exported names (or `_name` labels) become rows: an assembly function's own loops are all charged to its exported entry | tool wish | a console line at 23.07 s marks a phase; `--prof-from 23.07` profiles from 27.8 s of the machine |
| 20 | The blitter waits and the vertical-blank sleeps show only as "idle (WAI)" and "syscall $0F": which of the program's calls slept is not in the profile (each syscall row could name its callers' functions) | tool wish | |

**Where items 9-17 stand (24 November 2026).**

- 9-11 are in the SDK and the port uses them: `horizon/hz_plat.c` sends the view with
  `hg_view_send()` (no `hg__scr`, no `hz_fs_scroll` of its own) and reads the pointer from
  `hg_mouse_x/y/b` (hgame's 320 x 180 coordinates, halved from the kernel's 640 x 360 as the
  port's own `ws_mouse` reading was: the pan's maths and the clicks are unchanged; the
  presses are still counted by the port at each poll, not by `hg_mouse_clicked()`). The
  reads loop as before (`read_all`/`write_all`).
- 12: `-Woverflow` is no longer silenced by `-w` (the build now prints `geo.c:180`'s
  `WMAP_W * WMAP_H`, 51,200 into an `unsigned`: harmless); cc816 has `-ffar-wrap` (far
  pointer arithmetic on the offset alone, DOS's), not used by the port, whose upstream fix
  (`4u * TILES`, src-0005) stays (reference.md, "The far data model", "Pointers").
- 13: cc816 has `-fargs-right-to-left` (DOS's order) and `-Wsequence-args`, which names 44
  calls in the port's sources (most of them `log_printf`/`sprintf` of getters; battle.c's
  `hurt` is the one known to matter, fixed by src-0003's `HURT`). The port keeps
  left-to-right: its tests compare with the host build, whose order is gcc's.
- 14: no change (Horizon: a bank shared by two tasks; noted for a later revision).
- 15: run816 `--stop-on TEXT` (with `--stop-on-delay MS`, `--must-stop`): every emulator
  run of `tests/check.sh`, `tests/sound.sh` and `tests/speed.sh` ends 1 s after the
  program's last line ("xcom: files: at most ...", printed at its exit after the LOG and
  the saves are closed) instead of at its `--seconds`.
- 16: run816 `--console-times` (each console line with the emulated time, the same base as
  `--log-opl-us`) and `--log-lau-us`.
- 17: measured: the Desktop with Files open leaves 62 banks (3,968 KB) to a program at its
  start; the "3,136 KB free" of the needs check is after XCOM.PRG's own 13 banks (832 KB)
  were taken by its loader (the check runs as a constructor, after `__hz_xload`). So
  `mem=` counts free memory beside the program's own image.
- The speed's assembly (`horizon/hz_*.s`) is movable now (`FUNC`, sdk/c/rt/model.inc):
  hcc places it in a code bank like C (reference.md, "Movable assembly"): 3,824 bytes out
  of the main bank's fixed part ("Sizes", below).

## 4b. Stage 3's gate: the far data model (done, 23 November 2026)

The SDK now has items 1-5 and 7-8 of the table above: `hcc --code large --data far`
(sdk/docs/c/reference.md, "The far data model"): plain data pointers are 32-bit far
pointers, string literals and `const` tables live in banks of far data, `malloc` takes
banks from Horizon, the C library and hgame take far pointers, `read` goes straight into
far memory, `T far *a, far *b;` and `void (far *f)(void)` compile, `#pragma aux` is
warned about, and `hcc --sizes` lists every object. The port changed only `Makefile`
(`--data far`, `--game`), `compat/xcompat.h` (`__near` empty: one pointer kind;
`XD_FAR_DATA`, so the engine's malloc is the DOS chain in the arena), `plat/xdos.c`
(`_dos_read`/`_dos_write` straight into the arena) and `horizon/hz_plat.c` (`@FILE`: the
options of a test from a file, `tests/*.args`). Upstream is untouched.

| | |
| --- | --- |
| XCOM.PRG | 833,994 bytes: an o65 of 21 KB, 12 code banks (732,183 bytes of code; 578,218 with near data: far pointers make it 27 % bigger), 1 bank of far data (51,168 bytes: the strings and constant tables) |
| The main bank | 46,577 bytes besides movable code: code that must stay 8,005, constants 3,517, data 319, bss 34,736 (the biggest, `hcc --sizes`: hgame's record queues 4.6 KB, `arena` 2 KB, `g_units` 2 KB, `save_box` 1.3 KB); + `--heap 2048` + `--stack 8192` = 56,817 of 65,264; 8 KB of it then filled with movable code |
| Banks at run time | 13 for the program, 17 for the DOS arena, the framebuffer's |
| Boot | `X.PRG @GEO.ARG` (`/V VGA NOINTRO LOG GEO.TXT KEYS GEO.KEY`): the start menu, a new game, the base placed, the geoscape within 20 s of emulated time; the whole of tests/geo.keys (the base, the UFOpaedia, the graphs) by about 80 s |
| Against the host | GEO.TXT and BATTLE.TXT (tests/battle.keys: a quick battle on FA1V, sectoids, seed 1, to "script finished") are the host's line for line, except the VGA buffer's segment (the structures' sizes differ: 16-bit `int`, 4-byte pointers) and BATTLE.TXT's "KB in all" (the host prints 0: a 32-bit `int` fault of the host build; the Atari816's 434 is the DOS model's own figure); every screenshot is one of the host's pictures but for 55 pixels (the mouse arrow: the emulator's pointer at 0,0) |

The profile of the first 60 s (`run816.py --prof`, `sdk/tools/prof816.py`): the platform
layer's polling dominates, not the engine: `uptime_us` (`hg_us`) 82,206 calls, 13 % of the
cycles; `__udiv32` 9 % (the clock's conversions); `memcmp` 8 % (`plat_poll` compares the
768-byte DAC each poll); the INT 33h model 7.5 %; `scan` (the floor pass) 5 %; `xd_mkfp`
4.8 %; `mouse_poll`, `plat_poll`, `bios_clock`, `plat_mouse` 2-4 % each.

**The next blockers** were (1) the polling and (2) the battle view's drawing: both done in
stage 4a (section 4c); (3) remains: the far data model's code in the engine's hot loops
(the render logic, the voxel lines, the path search: assembly where the profile says so).

## 4c. Stage 4a: tests, polling, the battle view by the blitter (23 November 2026)

### make test

`make test` (`tests/check.sh`, about 50 s on the fast machine; 1 min 53 s with a clean
build of both) runs each line of `tests/runs` (upstream's KEYS scripts) on the host build
and on the Atari816 in the emulator, both with the virtual clock (`/V`), and compares
(`tests/compare.py`):

| Run | Script | What |
| --- | --- | --- |
| geo | `tests/geo.keys` | a new game, the base placed, geoscape time, base screen, UFOpaedia, graphs |
| battle | `tests/battle.keys` | a quick battle (FA1V, sectoids, seed 1): the view, the Options window |
| save | `tests/save.keys` | a new game, an hour of game time, Save Game in slot 1, Load Game |
| bench | (none) | upstream's BENCH: its renderer checks ("check scroll: 0 screen bytes differ, full redraw same", "VGA sprite check", path search C = asm) |

Checked for each: the engine's LOG line for line (one allowed difference: "KB in all",
pointer size, above); the **test pictures**: the model (`plat/xdos.c xd_shot_point`)
takes them at the same points of both builds, where the engine polls or waits for a key
and the screen changed (a Fletcher sum of A000 and the DAC, looked at every 500 / 200 ms of
virtual time): the same list of (number, virtual time, checksum) on both; what the
emulator **showed** at each (the program prints the line and holds the screen four frames,
`--shot-on`) equal pixel for pixel to the host's PPM at the pan printed (or the split
battle view: its 124 rows and the panel); the run's end at the same virtual time (a run
ends 5 virtual seconds after the script); `*.SAV` files byte for byte; BENCH.TXT line
for line (with the virtual clock its times are readings of it: equal); no kill, no
blitter rule broken (emu816's check of CPU reads of what Ali wrote). The host's pictures'
MD5s are in `tests/host.md5` (27; no picture of the game in git). Plus a run with the
**real keyboard and mouse** (no KEYS, the real clock, `tests/input.script`): the start
menu clicked, New Game, the difficulty, a base placed by a click on the globe and Enter,
the base screen by its button, GEOSCAPE at the bottom (the pan brings it in), G for the
graphs: the LOG must say each. The test could fail and did: the first blitter version
left the view black (37 % of the pixels differed).

The arrow: in `/V` runs the pointer moves only by the script (as on the host), so the
arrow is where the host draws it and pictures compare whole (no masking).

Rebuilds follow content (`build/sum/`, as Prince's Makefile): rsync -a or an unpacked tree
rebuilds what changed. `tests/xrun.sh OUT SECONDS "OPTIONS"` runs XCOM.PRG once with the
packs (trying things out); `tests/prof.sh` profiles the four screens.

### Polling

The engine polls keyboard, mouse and clock constantly (free on an 8088). Before, in the
first 60 s: `uptime_us` 13 %, `__udiv32` 9 %, `memcmp` of the DAC 8 %, INT 33h 7.5 %, the
CPU never idle. Now (`horizon/hz_plat.c`, `plat/xdos.c`, `plat/timer.c`):

- one clock reading per `xd_poll` serves the BIOS clock and the timer hook (it was three),
  converted with 16-bit shifts and adds (`d + d/8 + d/16 + d/256 + d/512`: 0.015 % fast),
  no `__mul32`, no `__udiv32`;
- `plat_poll` does its work (events, the pointer, pan, palette) at most every 8 ms, from
  the reading already made; the DAC is sent only when a port write changed it
  (`xd_dac_dirty`), no compare;
- INT 33h polls only at function 3 (once per `mouse_poll`; 5 and 6 answer from it);
- where the engine spins for input (two empty keyboard polls within 2 ms), the next waits
  for the vertical blank (`hz_vsync`: the CPU sleeps); `timer_pace` and `delay` sleep
  through whole frames (`plat_sleep_counts`);
- `xd_mkfp` in 16-bit arithmetic;
- the pointer's position from `ws_mouse` (hgame's full screen gets motion events only
  while a button is held: the pointer did not follow the mouse; SDK need below).

The profile (10 s of each screen, real clock, `tests/prof.sh`; % of all cycles):

| Screen | Before | After |
| --- | --- | --- |
| start menu, idle | idle 2 %; uptime_us 32 %, memcmp 10 %, int33 7 %, plat_counts 6 %, __mul32 6 % | **idle 77 %**; vsync 3.9 %, uptime_us 2.2 %, int33 1.9 %, ws_mouse 1.7 % |
| geoscape, time running (1 min) | idle 2 %; uptime_us 21 %, vga_uk_glyph 8.6 %, memcmp 6.6 %, __mul32 5.3 % | **idle 50 %**; vga_uk_glyph 7.8 % (the clock's text), vformat 2.7 %, __udiv32 2.0 % (the engine's), fly_craft 1.8 % |
| base screen, idle | idle 2 %; as the menu | **idle 76 %** |
| battle view, idle | idle 2 %; uptime_us 31 %, memcmp 9.7 %, __mul32 7.2 % | **idle 77 %** |

### The battle view by the blitter

Measured first (BENCH, real clock, the C renderers through far pointers): a full redraw of
level 0 at the map's middle (51 masked + 37 OR sprites) **1,256 ms**, all four levels
**1,862 ms**, the present 325 ms, a clear 189 ms, a scroll by one tile 944 ms, a cursor step
81 ms; a real-time quick battle still showed a black view after 50 s. The profile: the C
pixel loops (present, clear, the span blitters, clipspan, the shift), not the engine.

Now (`horizon/hz_bb.c`, `plat/vgabat.c` asks the platform first; the host keeps the C,
which stays the reference):

- **Where.** The framebuffer is 320 x 400 in two banks: rows 0-199 are A000 (the screen),
  rows 205-348 the back buffer, 349-388 the cursor box's copy. The back buffer's segment is
  D004 (`plat.h XD_BB_SEG`; the arena's bank 13, outside the DOS memory; `plat/vga.c`
  still takes the DOS memory upstream's prototype took, so the engine's memory plan is
  unchanged), and on the Atari816 bank 13 *is* the framebuffer's second bank: Ali and the
  CPU see the same bytes, so whatever the engine reads through `MK_FP(g_bufseg)` is right
  (`MK_FP` into bank D first waits for the blitter).
- **Sprites.** Each span-coded picture is unpacked the first time it is drawn (no PC tool:
  the packs' pictures are already in memory, unpacking is a few `memset`/`memcpy` a row)
  into an atlas (sheets of 1024 x 256, 256 KB, as needed, at most 6) as a rectangle whose
  uncovered pixels are its key, a colour none of its spans uses; a draw is one keyed sheet
  record, clipped as the C writes (rows and columns of the clipped entries, the buffer's
  rows, a part past column 320 on the next row: the C's offsets are linear). A file read
  into, or a free of, memory holding a kept picture forgets the atlas
  (`plat_mem_changed`, from `fread`, `read`, `_dos_read` and the DOS chain's frees).
  BENCH's map: 204 pictures, one sheet. A picture with all 256 colours would be drawn by
  the C (none seen).
- **The rest.** Clear: a fill record. Present: a copy from a sheet over the back buffer to
  the screen, waited for (the CPU draws the pointer and the interface next). Scroll: one
  `draw_list` move. Cursor box: copies to and from rows 349-388. The unit's arrow: an atlas
  picture. Smoke and fire overlays (`fxtile_cga`), the night shade at the present, a
  picture without a key: the C, after waiting for the blitter.

BENCH now (real clock; first value with the pictures unpacked on the way):

| | Before | Now |
| --- | --- | --- |
| full redraw, level 0, view 20,20 | 1,256 ms | 376 ms first, **206 ms** after |
| full redraw, levels 0-3 | 1,862 ms | 909 ms first, **419 ms** after |
| average full redraw (12 views) | 1,353 ms | 307 ms |
| present / clear | 325 / 189 ms | 7 / 0 ms |
| scroll by one tile / 3 tiles / edge across | 944 / 993 / 825 ms | **113 / 86 / 52 ms** |
| cursor step / unit step | 81 / 146 ms | **21 / 47 ms** |
| 100 OR floors / masked floors / objects | 252 / 271 / 626 ms | 37 / 57 / 51 ms |
| level 0 with 32 smoke + 16 fire tiles | | 629 ms (245 without the overlays: the C overlay) |
| a quick battle on the screen (real time) | black at 50 s | drawn by 8 s |

What limits it now: "same without blits" is 164 ms, the engine's own render code in C
(the floor pass, `render.c`'s columns, `__mul16`, `__umul1632`, `__udiv32` calls, far
pointer arithmetic) plus the records' CPU side (`plat_bb_sprite`, `find`, `put`: about
50 us a sprite). So **0.15 s is not reached** (0.21 s for level 0, 0.42 s for four levels);
cursor moves (21 ms) and scrolling (52-113 ms) feel immediate. Next: profile the redraw
alone (BENCH's checksums out of the window), the floor pass and `hz_bb.c`'s record path in
assembly, the pictures unpacked at the battle's start instead of during the first redraw,
the smoke/fire overlay by Ali's EXPAND (a 1-bit mask, `LS_EXPANDK`).

**What Ali cannot do here:** a per-pixel colour remap. The night shade (and upstream's
per-cell night lights, not ported yet) maps every pixel through a 256-byte table at the
present; Ali copies, keys, fills and expands, with no lookup table, and the raster table
changes 16 palette entries a frame, not 256. Needed for it in hardware: a copy through a
256-entry remap table (a "translate" mode in Ali), or a palette bank per screen region
(Marga). Meanwhile the C does the night present (a 46,080-byte remap; assembly next), or
pre-shaded copies of the pictures in the atlas (one per shade level) when the lights come.

### The screen

(Stage 4a's way, `/PANPTR` since section 4e: the picture now stands still, the wheel
moves it.) Implemented in `horizon/hz_plat.c`: every screen pans (the 180 lines show rows from
`s * 20 / 179`, s the pointer's line; the pointer's row is `s + s * 20 / 179`); the
battle view is split: the panel (rows 144-199) whole at lines 124-179, 124 of the view's
144 rows above it, following the pointer while it is over them (the engine says so:
`plat_view(1)` at a present, `plat_view(0)` when a picture crosses row 144: the Options
window, the inventory, the geoscape). Seen in the emulator's pictures: start menu,
difficulty, geoscape (rows 10-189 with the pointer at 100: the INTERCEPT button's top
cut, reached by moving up), base screen (GEOSCAPE at the bottom reached with the pointer
low: `tests/input.script`'s shot 7), UFOpaedia, graphs, battle view with the panel whole,
the battle's Options window (panning, not split), Select Save Position / Load. The engine's
mouse coordinates under the pan: the input run clicks New Game, Beginner, a point on the
globe (the base went to North Africa, where the click was), BASES, GEOSCAPE: all right.

### Sizes now

XCOM.PRG 845,938 bytes (12 code banks, 744,821 bytes of code; 1 bank of far data, 51,710
bytes); the main bank 48,354 bytes without movable code (bss 36,330), + heap 2 KB + stack
8 KB = 58.6 KB of 65,264; at run time 13 banks of program, 17 of the DOS arena, 2 of
framebuffer, 1 for the pictures' table, 4 per atlas sheet (BENCH: 1 sheet). Atlas: 256 KB
a sheet, made from the packs in memory (no file, no load time of its own: about 2 ms of
CPU a picture the first time it is drawn).

## 4d. Stage 5: the playable app (23 November 2026)

Done by the lead and three helper agents in parallel (sound, speed, screens), each in its
own tree, merged three-way; the whole `make test` from a clean build at the end.

### Faults found (port, upstream, compiler)

| # | What | Where | Fix |
| --- | --- | --- | --- |
| 1 | Every path search on the 816 differed from the host's: `vbench.c path_search_c` takes `cost + 4 * TILES` (an enum: 40,000 overflows 16-bit int to -25,536); DOS's far pointer wrapped the offset back, cc816's 24-bit one went 25 KB back and `memset(bucket, 0xFF, 512)` trashed the walk tables (wc, wd): aliens that did not move, battles that went their own way after the first alien turn | upstream (int overflow) + cc816's far pointers (SDK 12) | `patches/src-0005-fixes.patch`: `4u * TILES` |
| 2 | Damage drawn in another order: `hurt(u, roll_damage(), ..., rl_side())`, both call `rnd`; cc816 evaluates arguments left to right, Watcom/gcc right to left | upstream (unspecified order) + cc816 (SDK 13) | `src-0003`: a `HURT` macro, the side first (4 sites) |
| 3 | A comrade's death cost no morale on DOS/816 (`rank_mod*200*(...)` overflows 16 bits), 10 on the host | upstream | `src-0003`: the product in `long` (DOS, OpenXcom, host and 816 agree) |
| 4 | Plain `char` was signed in the port's build (Watcom: unsigned): the battle's Game Options screen indexed `"\x94..."` strings to y = -115 (host crash, 816 writes off screen) | port Makefile | `-funsigned-char` (host), `-fsigned-char` dropped (cc816's default is unsigned) |
| 5 | The base screen black under windows: the VGA "clean screen" was the last picture only | port (`plat/vga.c`, upstream's VGA prototype) | a real 64,000-byte copy at E000 (`XD_CLEAN_SEG`, bank 14, outside DOS memory) |
| 6 | The UFOpaedia list drawn over the article | upstream | `src-0003`: `uk_restore` after an article |
| 7 | The end slides never shown: INT 21h seek (42h) missing; `read()` of 64,000 bytes | port | modelled; reads in pieces (below) |
| 8 | The AdLib driver reads past a track's end (GMTACTIC's instrument 10): on the 816 a tempo of 1 from the memory after it, the music crawling after 75 s | upstream | `src-0002`: an instrument ends at the track's end, both builds |
| 9 | Test runs on the 816 took 20 emulated s a virtual second: a KEYS `WAIT` polls 20,000 times a virtual second at 60 counts a clock reading, each poll about 1 ms | port (test clock) | `XD_TICK_STEP` 600 (plat.h): geo 230 → 45 s |
| 10 | `plat_counts`: `d * 611` overflowed for a gap above 7 s (the first reading, a long load) | port | `plat_us_to_counts` in two parts |
| 11 | The BIOS clock (0040:006C) fell back to 0 when the 32-bit PIT count wrapped (1 hour of play): every WAIT ending at once, `now > end` tests stuck | port | its high word counts the wraps |
| 12 | The app started from the Desktop (no options) ran in EGA mode (no XMS in the model) | port | VGA unless the options name a mode |

To report upstream: 1, 2, 3, 5, 6, 8 (and the converter's GOG HE types, voxcheck.py's offset).

### Sound

**Music: a task of its own, MUSD.PRG** (`mus/musd.c` + upstream's `music.c`, small model,
21.7 KB). XCOM.PRG spawns it at priority 0 from its folder before the engine opens a
file; it reads MUSIC.PAK whole (83 KB, 2 banks: a task cannot read another's memory, kill
cause 02), owns the music timer (13,731 us = PIT 16,384, the driver's 72.8 Hz) and the
OPL2, and runs the driver's ticks; late wake-ups catch up (8 ticks at most). Commands by
port messages (play track/loop, stop, FM effect, sound on/off, quit); it quits when its
parent is gone. The game's own `music.c` keeps running on the game's clock as on the host
(its state and LOG unchanged); its OPL writes go nowhere while the task runs (without
Lau or MUSD.PRG they go to the OPL2 as before). So the music keeps its tempo through
battle loads, redraws and alien turns with no hook in the engine's loops.

**Effects: a Sound Blaster model** (`plat/sb.c`): `BLASTER=A220 I7 D1 T3`, DSP 2.01 (reset,
version, speaker, time constant, PCM 14h, 4-bit ADPCM 75h/74h, halt), the 8237's registers
and pages; at a block's end, on the model's clock, the handler the engine set with
`_dos_setvect` is called. The effects live in a 64 KB "UMB" of the sound's own at C000
(the arena's bank 12, outside the DOS memory: the memory plan unchanged; the LOG says "all
23 effects in the UMB"). SOUNDS.PAK's 23 effects are Creative 4-bit ADPCM at 6,000 or
8,000 Hz; on the 816 each block is decoded once into signed 8-bit samples (cached by
address and checksum in up to 3 far banks, about 82 KB for all) and played on Lau at
volume 160, one at a time as on the card. The host logs each block (`-sb FILE`); with `/V`
the 816 prints the same line. The LOG's "sound:" line is now "Sound Blaster at 220 IRQ 7
DMA 1, DSP 2.01" on both. The PC speaker's effects stay silent (not needed).

**Tested** (`tests/sound.sh`, part of `make test`, about 25 s): the geoscape music's OPL2
writes (2,701, 1,456 ticks) and the battle's (load, redraws: 1,500) equal the host's
(its `-opl` log: tick, ms, register, value), the ticks on the 13.731 ms beat (median
lateness 0.1-0.2 ms, at most 8-17 ms once, while a screen loads); the aliens' turn run
(sndai): 5,875 writes equal, beat 13.7310 ms, at most 0.92 ms late; the battle's Sound
Blaster blocks equal the host's, each a Lau start of its samples at its rate; the
recordings (`--wav`): geoscape RMS 312, battle 636, peaks about -19 dBFS, nothing
clipped; effects 10-14 dB above the music (the driver's OPL levels are low and cannot
change without leaving the host's stream). Broken on purpose: a period of 13,800 us and
effect rates +500 failed all three.

### Saves and files

- Saves live in the program's folder (`hz_prog_dir`, then `hz_chdir`: the engine's
  relative names): `/APPS/XCOM/XCOMXT0-9.SAV`, `XCOMXT.CFG`; never in the archive, kept
  by updates.
- **Geoscape save** (`save`) and **battle save/load** (`bsave`: a quick battle saved at
  its start, two turns with an alien turn each, loaded, the same keys again) byte for byte
  against the host (XCOMXT1.SAV 12,100 / 52,265 bytes); the loaded battle's state (the
  engine's checksums of units, map, floor, fog, AI, random number) is the saved one's, and
  the 19 LOG lines after the load are the ones after the save. `bsavebig` (test-long): the
  abductor battle (11 sectoids), 78 KB. A campaign battle (CAMPAIGN.TMP + XCOMXT.TMP and a
  rename) is in the soak.
- Upstream's own: after a load the view level and the AI's choices of a *continued*
  battle can differ from the uninterrupted one (seen with TAB and an abductor's aliens);
  the same on host and 816: the engine's, not the port's.
- **Open files** (Horizon: 4 for the whole system): the model counts them on both
  builds, refuses a fifth as Horizon would (so both behave alike) and prints "xcom: files:
  at most N open (...)"; compare.py fails on any refusal and on a different peak. Peaks
  seen: 4 in tests (the KEYS file is one: UFOPAED.PAK + UIV.PAK + PALV.PAK in the
  UFOpaedia; XCOMXT1.SAV + the mission pack + the LOG in a battle save), so 3 in play;
  the music task opens nothing during play.
- `read()`/`write()` in pieces of 32,767 bytes until n, the end or an error
  (`read_all`/`write_all`): the SDK's read moves at most that much a call.
- **A full card** (`check.sh`, emu816 `--card-free 8000`): the save is written short, the
  engine says "Could not save the game!", the model removes the cut save (`xd_fclose`: a
  cut slot would load as garbage), the game goes on to its end (no kill). emu816 counts
  the bytes written in the run, so its card stays full after the removal: the LOG's later
  lines are lost there (on a real card the removal gives the room back).
- **No data** (an app installed without the packs): a screen "X-COM: the game's data is
  missing ... /APPS/XCOM/ ... See README.TXT", a key ends it. **The engine stopping with
  an error** (exit(n) with n != 0: "out of memory", "Packs are from another version", ...):
  its last lines on the screen until a key (`xd_exit`), as DOS left them on the text
  screen. A missing card while playing: not tested (the emulator cannot pull it).

### Speed (BENCH and the profile, real clock, emu816)

| What | Before (stage 4a) | Now |
| --- | --- | --- |
| full redraw, level 0 (view 20,20) | 233 ms | **137 ms** |
| full redraw, levels 0-3 | 461 ms | 260 ms |
| average full redraw (12 views) | 328 ms | 150 ms |
| the first redraw of a battle | 396 ms | 153 ms (the atlas filled before it) |
| the same without blits (the engine's own code) | 179 ms | 99 ms |
| scroll by one tile / 3 tiles / edge across | 120 / 94 / 56 ms | 88 / 63 / 42 ms |
| cursor step / unit step | 23 / 32 ms | 17 / 21 ms |
| 100 masked / 100 OR sprites | 66 / 46 ms | 36 / 23 ms |
| a view with 32 smoke + 16 fire tiles | 635 ms (dithered shapes, C) | 309 ms (DOS's pictures, blitter) |
| night: level 0 / present / scroll | 580 / 366 / 474 ms | 241 / 115 / 193 ms |
| path search, unit 0, 60 TU | 606 ms | 231 ms |
| alien turn, abductor (FA5V, 11 sectoids, SEED 2) | 48.3 s (with fault 1 fixed) | **19.8 s** |
| a soldier walking 3 tiles | 3.54 s | 3.29 s (paced by the animation) |
| geoscape world view, zoom 0 / 1 / 2 | byte loop / 349 / 276 ms | 50 / 99 / 58 ms |
| geoscape, CPU idle at 5 Sec / 1 Day | 50.2 / 76.8 % | 54.2 / 77.5 % (8 steps a second: never CPU-bound) |
| text (glyphs), share of the geoscape's time | 7.8 % | 3.8 % |
| 360 voxel lines / 8 aims | 3.3 / 1.68 s | unchanged (C) |

How (`horizon/*.s`, ca65, built by hcc as ports/skyroads' are):
- `hz_bbs.s`: a picture already in the atlas goes from its lookup straight to its blitter
  record (the C, `hzb_sprite_c`, does the rest); the unpacking's colour scan.
- the atlas is filled at the battle's start (`plat_bb_prepare`, called through
  `src-0004` before the battle view and before BENCH; loaded saves too): a bar for 1.5 s
  (285 pictures) with the hourglass, then no hitch while scrolling over new tiles.
- `hz_rend.s`: the floor pass's column loop (`rd_level`; the host keeps `plat/rend.c`'s C,
  the reference; the structure's offsets checked by `_Static_assert`).
- DOS's smoke and fire pictures (`plat/vgabat.c` fxpic, pics_next: SMOKEV.PAK, as upstream
  loads it), drawn through the atlas on the 816; BENCH's pictures check and a checksum of
  the buffer added through `src-0004`, host = 816.
- **Night: the single night shade kept** (decided: per-cell lights are about 900 lines of
  OpenXcom's lighting for the picture only; sight at night is the engine's and unchanged;
  on the 816 they would cost the same per-pixel remap with one table per light level, so
  they can come later without a speed cost). Its present in assembly (366 → 115 ms).
  Flares and fires do not light their area visibly. A `night` run in `make test`.
- `hz_path.s`: the profile of a real alien turn put about 85 % in the path search (not the
  voxel lines or the sight fan); an exact assembly twin of `path_search_c` with path.c's
  step rules (`plat/way.c` sets it up; `src-0004` calls it from path.c). The LOG's alien
  positions are the same with and without it; BENCH says "match".
- `hz_vga.s`: each zoomed world row built once and copied for the rows that repeat it; the
  glyphs.

What the player feels: entering a battle is about 1 s longer than before (the bar), then
smooth (scrolling and the cursor immediate); a soldier's step is paced by the animation
(about 1.1 s a tile, as on DOS's default speed); the first alien turn of a small battle
a few seconds, of an abductor about 20 s (upstream: about 20 s on an 8 MHz 286 for the
first jungle turn in exact mode); the geoscape keeps its 8 steps a second at every speed.
`make speed` (tests/speed.sh, 20 s): BENCH by day and at night and an alien turn, on the
real clock (reports, fails only when a run does not finish or BENCH's checks fail).

Not done: the A* goal search (DOS's pathasm.asm stops at the goal; the port searches all
tiles within the TU, as the C reference does: the next big win for alien turns, with new
references), the unpacking's second pass in assembly (the bar 1.5 → 0.8 s), the voxel line
and sight fan in assembly, per-cell night lights.

### The screens walked through (host vs Atari816)

Every row passes `make test` (same LOG, the same pictures pixel for pixel, the same end
time; 4 PASS lines a run):

| Screens, features | Run |
| --- | --- |
| the intro (FLI), 10 s then skipped | `intro` |
| the victory slides / the defeat slides | `endwin` / `endlose` (test-long) |
| new game, geoscape time, base screen, UFOpaedia, graphs | `geo` |
| base info, stores, monthly costs, transfers list, soldier list and info, rename, Select Armour, Equip Craft (craft, crew, equipment, armour list) | `base1` |
| Build Facilities (a refused place and its notice, then built), research (new project, staff, start), manufacture, purchase (a soldier, scientists), sell/sack, transfer (destinations), a new base | `base2` |
| the Intercept window, graphs, UFOpaedia (section, article, back), options, funding, soldiers, time buttons, pause, zoom, scroll, right-click centre | `geobtn` |
| a UFO detected, an interceptor launched, stances, weapons toggled, the UFO shot down | `dogfight` |
| a terror site, its window, the Skyranger sent, "Begin Mission?", briefing, pre-battle inventory, battle, abort, debriefing | `mission` |
| battle: Options and Game Options windows, walk, inventory with the held item (mouse), a grenade primed and thrown, kneel, turn, end turn, alien turn, abort, debriefing | `bturn` |
| battle: walk, an alien spotted, snap / auto / aimed shots, hits and misses, reaction fire, a soldier killed, end turn, abort | `bfire` |
| a night battle | `night` |
| Save Game / Load Game (geoscape), battle save and load | `save`, `bsave`, `bsavebig` (test-long) |
| BENCH (upstream's renderer checks) | `bench` |

Not covered: a transfer between two bases, fitting armour (none in stores at the start).
The held item: heldasm.asm is EGA/CGA only; invscr.c's VGA path draws the item in C (the
rifle, a clip, a grenade follow the pointer, placed in hand, leg, ground: the same on
both). The FLI intro (`plat/fli.c`: COLOR, LC, BLACK, BRUN, COPY): 889 of 890 frames
shown, 26 ms a frame on average (one due every 83 ms), 75 frames over 80 ms (the
explosion, 249 ms at worst; 1.1 s behind at worst, caught up after): played, as upstream
does; any key skips it, `NOINTRO` stays.

### The app

- `make app`: **XCOM.HZA** (about 900 KB): XCOM.PRG, MUSD.PRG, APP.INF (`name=X-COM UFO
  Defense`, category Games; `needs=` copied from XCOM.PRG: `horizon=0.30,sprites,blitter,
  mem=2304K`), XCOM.ICN (`app/XCOM-ICON.txt`: a saucer with a green beam over a night sky,
  drawn for the port, not game art), README.TXT (`app/README.TXT`: the player's guide: the
  data, the keys, what differs). **No game data**: it is the archive one may give away.
- **The data**: the packs XCOMCONV made from the player's own copy go into `/APPS/XCOM/`
  (PACKS.VER, the 5 `.PAK` files of 290 KB, the `VGA/` folder, 82 files, 18 MB; the EGA and
  CGA folders are not needed). Copied by hand (README.TXT), or `make card` builds
  `build/card/APPS/XCOM/` (the app with the packs) to copy onto one's card, or `make app
  DATA=1` also builds `build/XCOM-DATA.HZA` (the same app with the packs: for one's own
  card only). As ports/prince's data is made by `make data` from the user's own files and
  packed by `make app`, only here the release package leaves it out (it is not free data).
  An update with XCOM.HZA keeps the packs and the saves (the Installer keeps the files
  the archive does not have; tested).
- `mem=`: the needs check runs with the program loaded; the Desktop leaves about 3.1 MB
  free (4096K was refused there); the game then takes the DOS arena (17 banks), the
  framebuffer (2), the pictures' table, the atlas sheets (4 banks each, at most 6; fewer
  when memory is short: the C draws the rest), the effects' cache (up to 3) and MUSD.PRG's
  3. Measured: 44 banks held at most in the tests' battles, 32 at the start, 13 of them the
  program's: 31 more + MUSD.PRG's 3 = 2,176 KB; `mem=2304K` (and the start fits beside
  the Desktop).
- `make test-app` (tests/app.sh, about 1 min): XCOM.HZA opened in Files, installed,
  started from Programs > Games without the data (its message on the screen), then with
  the packs and an old save already in /APPS/XCOM: the install keeps them, the game
  starts (the loading screen, the intro skipped by a key, the start menu), a new game, a
  base, Save in slot 2: `/APPS/XCOM/XCOMXT2.SAV`. Passes.
- **Loading**: a first screen at once ("X-COM: UFO DEFENSE ... Loading..." with a bar,
  in rows 205-384 of the framebuffer, shown until the engine first waits for input, so its
  own black screen while it loads is not seen). Measured in the emulator (fast card):
  the program's start to the start menu 3.1 s (NOINTRO; 70 KB read: the engine's
  start-up is mostly CPU: the palette and picture loaders read byte by byte through
  stdio, `__umul1632`), to the intro 1.9 s (46 KB). Before `main`, Horizon loads XCOM.PRG
  (875 KB) and MUSD.PRG (22 KB): with emu816's slow card (`--card-kbps 170:100`) the
  machine reached the menu 6.4 s later than with the fast one. On the board's card: about
  2 s for the program at 450 KB/s, 5 s at 170 KB/s (the notes' 0.38 s a picture), so the
  start menu 5-9 s after the double click; the loading screen shows after the program's
  load. Read later, when needed: the mission and race packs at a battle's start (0.3-1 MB,
  1-6 s on a slow card), UIV.PAK's pictures with each screen (64 KB a full screen: 0.15-0.38
  s), the music task's MUSIC.PAK (83 KB) at its start, SOUNDS.PAK at the first geoscape.

### Robustness

- Allocation: the engine's own malloc is the DOS chain (its NULL answers are DOS's, which
  the engine handles: "out of memory" ends it with its message on the screen, xd_exit);
  the platform's banks (the arena: a message and the end; the pictures' table, atlas
  sheets, the effects' cache: the C draws, the effect is silent) all fail cleanly.
- Random memory and bankwrap: `EMU816_ARGS="--ram-random 1 --log-bankwrap" sh
  tests/check.sh`: all 85 PASS lines as with cleared memory (every run's LOG, pictures and
  saves the host's), and no bankwrap report at all. (emu816's report covers the indexed
  modes on the data bank, `abs,X`, `(dp),Y`, `(sr,S),Y`; the far data model's `[dp],Y`
  carries into the next bank by design and is not reported: fault 1 above was of that
  kind and was found by the host comparison, not by this.)
- The clock: the microsecond clock (`hg_us`, 32 bits) wraps every 71.6 minutes; the port
  uses only differences of readings and converts them in two parts (no 32-bit overflow);
  the PIT count's wrap (an hour of play) keeps the BIOS clock going. `/U n` adds n us to
  the clock: `make test` runs the real-input session three times: as after the machine's
  start, with the clock as after 5 minutes (`/U 300000000`), and with it wrapping about
  25 s into the game (`/U 4264967296`: "xcom: the microsecond clock wrapped" checked): the
  same LOG lines each time. Upstream's `sound.c` compares `now > sb_end` (not wrap-safe):
  at the PIT count's wrap one effect may be cut; harmless.
- **The soak** (`soak`, make test-long; `tests/soak.keys`, TERROR, OLDCLOCK): 1 January,
  a terror site at London: the Skyranger sent, briefing, inventory, the terror battle
  (UR0V): a walk under reaction fire, an alien turn (psi panic, a civilian killed, a
  Cyberdisc hit), a **campaign battle save** in turn 2 (slot 2, the CAMPAIGN.TMP path),
  abort, debriefing; a Small Scout intercepted and shot down; 1-25 January at 1 Hour (UFOs
  3-8); a Large Scout landed: the second battle (FA3V, at night): walk, kneel, an alien
  turn, abort, debriefing; to 26 January at 1 Day, a geoscape save (slot 1). On host and
  816: 305 LOG lines the same, 62 pictures pixel for pixel, the same end time, both saves
  byte for byte (11,928 and 90,811 bytes), at most 3 files open. 805 emulated seconds on
  the 816 (2 min 45 s of wall time).

### Sizes (stage 5)

XCOM.PRG 875,182 bytes (12 code banks, 770,269 bytes of movable code; far data); the
main bank 54,447 bytes without movable code (code that must stay 13,151: the speed's
assembly is in it, constants 3,881, data 374, bss 37,041) + heap 2 KB + stack 8 KB =
64,687 of 65,264: **about 600 bytes left** (four port arrays moved to `__far` statics to
fit; the next changes need the SDK's far code segment for `.s` files, or hgame's queues
out of the main bank). MUSD.PRG 21,699 bytes. XCOM.HZA about 910 KB. At run time 32 banks
at the start (13 the program's, 17 the DOS arena, 2 the framebuffer), at most 44 in the
tests' battles, + MUSD.PRG's 3. The port's own code: about 10,300 lines of C and assembly (plat/, horizon/
with 4 assembly files, host/, mus/, compat/) besides the tests, 5 upstream patches of 369 added
lines.

**Since the SDK's movable assembly (24 November 2026):** the four `horizon/hz_*.s` files
open each exported function with `FUNC` (sdk/c/rt/model.inc), so hcc places them in a code
bank like C. XCOM.PRG 875,022 bytes; the main bank without movable code 50,597 bytes (code
that must stay 9,299, constants 3,881, data 374, bss 37,043) + heap 2 KB + stack 8 KB =
60,837 of 65,264: **4,427 bytes left** (3,850 more than before; hcc fills the room with
4,387 bytes of movable C until a change needs it). `make test`: 91 PASS lines.

## 4e. On the board (24 November 2026)

The first tries on the board: "it works! music on ... the scrolling thing is a bit annoying
... the game stutters a lot ... the battle is laggy". The emulator had promised a calm game.

### The measuring kit (`make kit`)

Programs started from the Desktop get no options, so the port reads **XCOM.ARG** in its
folder when it gets none (README.TXT section 4; `#` comments). The port's own options for
measuring:

| Option | What |
| --- | --- |
| `/M`, `/MN NAME` | self-timing (`horizon/hz_perf.c`): counters of time per kind of work (the engine's file calls, the card's own calls, the blitter waits, the vertical-blank sleeps = the idle time, view and palette sends, the pointer, effects started and decoded), histograms of the gaps a player feels (between the engine's looks at the keyboard and at events, pointer move → pointer drawn, between pointer draws, between battle view presents), the music task's own lateness (`mus/musd.c` 'M'/'R'), the memory; a line every 5 s, a block every 30 s, the totals at the exit, appended to NAME.TXT in the program's folder and to `/PC:/NAME.TXT` (the PC link's folder; silently nothing without it) |
| `/W` | the pointer circles by itself (a step every 20 ms): a KEYS script's run with the pointer moving |
| `/Q n`, `/E` | end after n s; end at the first wait for input (after BENCH) |
| `/C FILE` | copy FILE to `/PC:/` at the exit (BENCH.TXT) |
| `/IOB` | the card's costs: each kind of Horizon file request timed alone (stat, open, close, seek, reads of 16 B to 32 KB, a LOG line's create/append), IOBENCH.TXT and `/PC:/`, then the end |

A KEYS script's `WAIT` now sleeps to the next frame between its looks at the mouse on the
real clock (`patches/src-0006-perf.patch`; the virtual clock: unchanged), as a player's
input wait does, and ends the loading screen (it stayed up for a whole scripted run). A
script's CLICK/MOVE keeps the pointer where it put it until the mouse (or `/W`) moves.
`tests/perf.sh OUT S "XCOM.ARG text"` runs a kit run in the emulator as on the board (the
app's folder, no options, the PC folder at OUT/pc); `tests/perfcmp.py BOARD EMU` puts two
reports' totals side by side. The kit's runs: `tests/perf/*.arg` (0 IOB, 1 BENCH, 2
menus and geoscape scripted, 3 a battle scripted, 4 and 5 by hand).

### What the board showed (kit runs 1-3), against the emulator of then

| Per call | Board | Emulator (instant card) | Emulator optimistic by |
| --- | --- | --- | --- |
| the engine's open (stat + open, 2-3 requests) | 54-66 ms | 4.3-4.7 ms | 13-14 x |
| close of a file read / of a LOG line | 7 / 16 ms (with its write) | 1.3 / 1.6 ms | 5-10 x |
| seek | 1.34 ms | 0.52 ms | 2.6 x |
| read (the engine's, through stdio's buffer) | 1.7-3.1 ms | 0.55-0.76 ms | 3-4 x |
| PALV.PAK (an open, seek, read and close at each palette) / NAMES.PAK / UIV.PAK / FA1V.PAK | 1,557 / 2,082 / 5,136 / 2,075 ms | 115 / 207 / 1,175 / 550 ms | 13 / 10 / 4.4 / 3.8 x |
| plat_poll's work (events) | 1.06 ms | 0.85 ms | 1.2 x |
| the pointer drawn, a view send, a palette, a blitter wait, a present, an effect started | 2.08 / 0.45 / 14.6 / 2.04 / 5.0 / 73 ms | 2.07 / 0.46 / 16.5 / 2.16 / 5.4 / 73 ms | none (within 10 %) |
| BENCH (redraw 159 ms, scroll 93, cursor 21, present 11) | | the same | none |

So the CPU, the blitter and the memory are modelled honestly; **the card was not**: the
emulator answered every file request at once. On the board a request costs what the I/O
processor's FatFs needs, whatever its size: an OPEN or a STAT about 25 ms. That was the
stutter at every screen change (seconds of opens and small reads), and the music task's
timing was fine all along (at most 26 ms between its wake-ups, no tick lost).

### The fixes

- **The emulator's card** (emu/README.md "The card's speed"): `--card-board`, each request
  costs the board's time (OPEN, STAT 24 ms, CLOSE 0 / 16 ms after writing, SEEK 1.1 ms, READ
  4.5 ms + 220 KB/s, WRITE 3 ms + 100 KB/s), fitted to the three board runs (within 10-30 %
  per kind); run816 uses it from the program's start (`--card-board-at`; `--fast-card` for
  the old instant card); `emu/tests/asm/cardtest`. Other ports: digger's and prince's
  app tests needed longer waits after the install and around the Programs menu (it stats
  each program as it opens); prince's and xargon's scripted games press keys at fixed
  times, so their check.sh runs with `--fast-card` for now (a note there: wait lines to do).
- **The packs in memory** (`plat/xdos.c`, "the packs in memory"): read-only opens of the
  packs go through a cache: a name table (each path looked up once: there or not, its
  size) and their contents in 16 KB blocks in far banks taken while at least 12 banks stay
  free (at most 24; given back to the battle's atlas when it needs them), least recently
  used reused. An open, a seek, a read of what is in memory make no card call; the engine
  sees the same bytes, files and errors (`make test`: the host's LOGs, pictures and saves).
  Measured (emulator, the board's card): no card call at all in steady play on the
  geoscape or in a battle after its start; a screen's first visit 1-6 card calls (0.2 s),
  later visits none; the start: machine on to the start menu 19.6 s (21.3 before), to a
  quick battle 21.5 s (28.0). Memory: 7-8 banks of cache in the tests' runs.
- **The pointer is a hardware sprite** (`horizon/hz_plat.c`, "the pointer"): vga_ms_draw /
  vga_ms_erase (2 ms of CPU each, about 100 a second while the mouse moved) now give the
  arrow's or the hourglass's picture to one of Marga's sprites, moved at each poll where
  the mouse is (no lag behind the engine's own redraw), hidden when the engine has had no
  pointer for 300 ms while it still polls. `/V` runs draw it as before (the test pictures
  are the host's); `/CPUPTR` too.
- **The screen stands still** (the user's decision): each kind of screen starts at its own
  rows (by the DOS palette the engine sets: geoscape and its windows centred, rows 10-189;
  base screens bottom-aligned, their buttons in rows 188-199; graphs and UFOpaedia articles
  top-aligned, their buttons in rows 0-17; the battle's inventory rows 4-183, its OK in rows
  1-10); the mouse wheel (5 rows a step: hgame's new `hg_mouse_wheel()`, sdk test gt_poll)
  or F5 / F6 move it, 4 rows a poll at most; the battle view's 124 of 144 rows the same
  (centred first). What the centred geoscape hides: the INTERCEPT button (rows 0-9: a wheel
  step, or I) and the lower part of the globe buttons (rows 190-199: + / -, the arrows).
  `/PANPTR` keeps the old way. View sends: none unless the wheel turns (17 a second before).
  Squeezing 200 rows into 180 instead (every 10th row dropped; tried on the host's
  pictures of the base information and the soldier list): the whole screen shows and
  stays usable, but every second or third line of small text loses one of its rows ("SKY-
  RANGER-1" in the soldier list, a few names, the bars' scales look broken), and it would
  need a copy of the picture at every change (Marga cannot skip rows): not taken. A
  640 x 360 mode with the picture doubled only across would stretch it to 2:1 against
  the 1.2:1 it was drawn for (distorted): not taken either.
- **Effects** (`horizon/hz_snd.c`, `horizon/hz_adpcm.s`, `patches/src-0007-sfx.patch`):
  each start used to checksum the whole block in C and decode it the first time: 72-206 ms
  a shot. Now every effect is decoded when the engine has loaded them all (23 effects, 0.96
  s, in assembly: 3.7 s in C), and a start checksums 1 byte in 61 (`sb_sum`, both builds):
  0.9 ms. Lau's volume 255 (Prince's and Xargon's; was 160). The Lau setup is theirs
  (`hg_sound_from` of signed 8-bit samples in far banks, `hg_play`), nothing the hardware
  would refuse. What a player hears: no effect in the menus or on buttons; a chime when a
  UFO is detected; an interception's shots and hits; in a battle every step, shot, hit,
  death, door, explosion.
- **The alien turn**: 44 s without a poll in the scripted battle (FA1V, seed 6), the board
  the same. The voxel line (`plat/voxrun.c`, 60 % of it) now copies its block in and out
  instead of reaching it through a far pointer at every field, and makes its table
  pointers once a call (a few per cent: the turn is still 44 s). It now calls
  `plat_busy_poll` once a line: every 32nd call the platform reads its events and moves
  the pointer (real clock only), so the pointer moves and keys queue during the turn (the
  music has its task). NOEXACTAI (the engine's option, XCOM.ARG) makes the same turn 8 s.
  Next: the voxel line in assembly (and the A* goal search). (Since done: section 4f,
  the same turn 8.4 s with the exact sight.)
- **"xdos: FP_OFF of a pointer outside the DOS memory"** (8 lines in a battle): panel.c's
  `FP_OFF(u)` of a unit in `g_units` (a global, in the main bank), only to test it for NULL:
  the expected case the model already answers (non-zero); no longer reported for the main
  bank's globals.
- **BENCH's "CPU read of blitter-written memory"** (emu816's rule check): BENCH's own
  screen checks read the screen (bank 4B in that run) right after a present whose list the
  port did not wait for; on the board the reads could be stale (its CPU has a 4 KB cache;
  hz_list_wait flushes it), the board's BENCH said "0 differ" all the same. BENCH only:
  the game itself reads what Ali wrote after `plat_bb_sync` (the old CPU pointer read the
  screen under the arrow: the sprite does not).

### Expected on the board now (the emulator with the board's card; `/M` on)

| Kit run | Figure | Before (board) | Now (emulator) |
| --- | --- | --- | --- |
| 0 IOB | stat / open / C open+close / seek / read 512 B / 4 KB / 32 KB / LOG line | (new) | 25 / 25 / 51 / 1.5-1.8 / 7.4 / 23 / 151 / 46 ms |
| 1 BENCH | average full redraw / scroll / cursor step | 159 / 93 / 21 ms | 156 / 93 / 21 ms |
| 2 GEO | to the start menu (ready for input after the start) | 10.4 s (+ card) | 13.0 s |
| 2 GEO | idle on the geoscape at 5 Sec, the pointer circling | 44-47 % | 62-66 % |
| 2 GEO | pointer move → drawn, at most / view sends a second | 40-52 ms / 17 | 30-40 ms / 0 |
| 2 GEO | card calls in steady play / at a screen change | 0 / 220-1,400 calls, 0.6-1.6 s | 0 / 0-6 calls, 0-0.2 s |
| 3 BAT | ready in a quick battle | 17.2 s (emu, board card) | 14.9 s |
| 3 BAT | idle in the battle view, the pointer circling | 18-25 % | 40 % |
| 3 BAT | an effect's start | 73 ms (206 at most) | 0.9 ms |
| 3 BAT | the alien turn | 45 s, pointer frozen | 44 s, the pointer moves |

## 4f. The alien turn (24 November 2026)

"The battle is laggy": the aliens' turn took 41 s in the kit's scripted battle (FA1V,
seed 6), 24 s with an abductor's 11 sectoids, 28 s for the first turn of a small scout
(FA1V, seed 1), with the exact sight and aim (upstream's default from a 286 on; NOEXACTAI
is not an option: it changes what the aliens see). Upstream's own figure for an 8 MHz
286: about 20 s for the first jungle turn in exact mode. Now: 6.5-8.5 s, the game's
state the same as before (the host's: `make test`, `make test-long`).

### The profile

emu816's counts over the turn alone (`run816 --prof`, `--prof-from/--prof-to` are
program times: the console's `--console-times` are the machine's, about 4.75 s later in
shell mode; prof816 names only exported labels, so the assembly's own labels were
exported as `_hzv_*` / `_hzp_*` for the label-level rows), and the host build's call
counts (gprof, and a copy of vox.c printing each line's caller, steps and result):

| Turn | What took the time (before) | The work |
| --- | --- | --- |
| FA1V seed 6 (the kit's battle: 41 s) | the voxel line's C 82 % (enter_tile 12 %, `__udiv16` 11 %, rows 9 %, run 8 %, skip 7 %, `__mul16` 6 %, room_of 5 %, shift 4 %, check 4 %: the divisions and multiplies of the empty-layer skip, a far pointer at every voxel), the path search 4 %, the rest the music task, interrupts, polling | 2,171 lines, 2,163 of them sight checks (62 `vox_sees`: los_unit_sees for each step of the walking alien, by it and by each soldier who might see it; 37 lines each, almost all blocked: the unit is not seen); a line 199 main steps, 16.6 tiles, 27 voxels checked, about 230,000 cycles (16 ms) |
| abductor, 11 sectoids (FA5V seed 2: 24 s) | the path search (`hz_path_run`) 70 %, the voxel line 18 % | 33 searches, 27 of them `path_search_to` toward a patrol node, each a whole flood of the map within 254 TU (1,400-1,575 tiles) for goals 8-18 TU away; 848 lines |
| FA1V seed 1, the first turn (sndai: 28 s) | the voxel line | one alien patrolling: 1,406 lines, every one a sight check that fails (38 checks of 37 lines) |

So both of the hot spots of the notes' "what is next" were right, and they are the whole
turn: the lines of sight (not aims: 59 lines of fire in the kit's battle) and the path
search toward a goal.

### What changed, and why each is exact

**1. A search toward a goal ends when its outcome is known** (`horizon/hz_path.s`,
`plat/way.c hz_path_search`; the host keeps the whole search, the reference). The C
reference (`vbench.c path_search_c`) floods every tile within max_tu; its bucket lists
keep a tile whose cost fell in its later bucket, so a cost can still fall after the
tile's own bucket has passed: the order matters, and an A* order (upstream's DOS
pathasm) would change ties and paths. Instead the same flood, stopped early:
- *reached*: at the start of a bucket, when no waiting tile (any bucket from here on)
  costs less than the goal, no cost on the goal's path can fall any more (a step costs 0
  or more, from[] changes only with a lower cost): path_build follows the same path as
  after the whole flood;
- *cannot be reached*: path.c's own A* estimate ((2 x the longer + the shorter axis
  distance) x 2, used while no tile costs less than 4 to enter: a straight step then
  costs 4 or more, a diagonal 6 or more) is a lower bound of any rest of a path and
  changes by at most a step's cost from a tile to its neighbour; the search counts the
  waiting tiles whose cost + estimate is within max_tu; at 0 (and the goal not reached)
  nothing reached later can reach the goal within max_tu.
- Who reads a search toward a goal: whether it got there (best) and path_build's path
  (execute's walk, bplayer's long walk: refresh_paths searches again after it); the
  tables of a failed search only `ai_way` (the blaster bomb's missile search: excluded,
  it runs whole). Every other search (path_search over the TU) runs whole as before.

Measured (host counts): the abductor's goal searches went from 27,000 expanded tiles to
about 4,600 (successes stop after 8-485 tiles, failures after 79-1,272). Its turn
22.2 s → 10.2 s with the C voxel line, the LOG's positions the same.

**2. The voxel line in assembly** (`horizon/hz_vox.s`, called by `plat/voxrun.c` on the
Atari816; the C stays the host's and the reference). The same walk as the C (and as
upstream's voxasm.asm): the line in OpenXcom's frame, every voxel it enters checked
against the tile's four parts' LOFT rows and the unit there, R_CALL for vox.c's
tile_info, the same block fields at every return (the block is vox.c's static, in the
main bank: X holds its offset, `a:V_FIELD,x`; long pointers `[dp],y` for the blob, the
map, the MCD records and the unit table). Two differences in how, none in what (a
multiply or a divide costs hundreds of cycles here; the C's skip does two of each per
axis, about 4 a tile):
- a minor axis's drift r (r -= d each main step; below 0: a move and r += d0) is kept
  as t, the main steps to its next move (r / d + 1), and b = r mod d: a step is t - 1;
  a move reloads t from the line's q = d0 / d and rem = d0 mod d (b += rem; at d or more:
  b -= d and t = q + 1, else t = q). The same moves at the same steps; the start (r =
  d0 / 2) from one division per minor axis per line (q even: t = q / 2 + 1, b = rem / 2;
  odd: t = (q - 1) / 2 + 1, b = (d + rem) / 2); r = (t - 1) d + b back in the block at
  each return.
- the C's skip (a tile's empty layers passed at once: the main steps that keep the major
  axis and each minor one in its room) is taken from move to move of the minor axes:
  the steps between two moves at once, stopping before the first move past a minor
  axis's room (that axis's room looked at only when one of its moves falls in reach).
  The same position, drifts and counts after it, no voxel of it checked (as the C).
Checked: a test program (`build/me/vt`, not kept: synthetic blobs, maps and units with
lifts, excluded units, units below floors, lines on past their target) ran the assembly
and the C on 18,000 random lines with every field of the block compared after each
return: 0 differ (it found the two faults below); BENCH's 720 lines in `make test`
(BENCH.TXT line for line with the host); every shot and sight line of `make test` and
`make test-long` (LOGs, pictures, saves); upstream's `voxcheck.py` against OpenXcom on
the host twin (its C was only rearranged: the line's extension is `extend()`, shared).
Faults it found while written: a skip with no room took one step (`sta` sets no flags:
the `bne` after it tested the room's compare), and the line's sign was lost to an `ldy`
between `sbc` and `bpl`; and before that every `lda V_X,x` with V_X < 256 had been
assembled as direct page, X (`a:` forces absolute: SDK note 18).

BENCH (real clock): 360 voxel lines 3,457 → 747 ms, the same past the tile 4,110 →
922 ms, 8 aims (canTargetUnit) 1,963 → 558 ms. A line of the kit's battle: about 40,000
cycles (2.8 ms) instead of 230,000.

**3. The screen during the turn.** The engine computes for seconds without looking at
the clock or the input. `plat_busy_poll` (called by each voxel line and every 8th tile
of a path search) now does, every 8th call (20-40 ms), what DOS's timer interrupt kept
going: the clock read, the BIOS clock moved on, the timer hook and the Sound Blaster
model run (`xd_clock`); every 40 ms plat_poll (the events, the pointer's sprite where
the mouse is, keys queued: its events cost about 1 ms, at 8 ms they took 7 % of a
turn). With the BIOS clock moving, upstream's busy pointer (mouse.c busy_tick, from the
AI's thinking) turns its hourglass over every 0.27 s, as on DOS: the sprite shows it
over the HIDDEN MOVEMENT window (upstream's own screen for the turn; nothing else on
DOS). Before, the clock stood still: the pointer stayed the arrow (the kit's "ptr 0,
lag 43190 ms"). The virtual clock (tests): nothing, as before. The music never waited
for the turn: it is MUSD.PRG's task (4d); over the kit's battle with `/M` its longest
gap between wake-ups stayed 15-22 ms (no gap above 30 ms, at most one tick late) in
every period, the alien turn's included.

**4. The loading screen** shows upstream's hourglass (its shape, in the loading screen's
colours, turned over every 0.27 s) below the bar until the first wait for input; the
engine's own busy pointer meanwhile (its busy_show while it loads, in colours not set
yet: half an hourglass at the top) is not shown. Battle setups (the atlas bar), saves
and loads show the engine's hourglass as before (busy_show).

### Before and after

The app as the board runs it (`tests/perf.sh`: the app's folder, MUSD.PRG, XCOM.ARG, the
board's card model), the turn as the LOG gives it ("alien turn N ms"):

| Turn (the script) | Before | After |
| --- | --- | --- |
| FA1V seed 6, the kit's battle (tests/perf/bat.keys: a walk, shots, a soldier killed, the turn ended) | 41.4 s | **8.5 s** |
| FA5V seed 2, an abductor's 11 sectoids (tests/prof/alien.keys) | 24.0 s | **7.8 s** |
| FA3V seed 3 (bturn: a walk, a grenade, kneel, the turn ended) | 14.2 s | **6.8 s** |
| FA1V seed 1, the first turn (sndai: the turn ended at once) | 28.4 s | **6.5 s** |
| FA1V seed 1, four turns (bsave: saved, loaded, two more) | 2.3 / 1.2 / 2.7 / 1.4 s | **1.9 / 0.5 / 2.0 / 0.5 s** |

The same in the emulator's shell (`tests/xrun.sh`, no music task), and BENCH (real clock):

| | Before | After |
| --- | --- | --- |
| FA1V seed 6 / the abductor / bturn / sndai | 38.1 / 22.2 / 13.1 / 26.1 s | 7.9 / 7.3 / 6.3 / 6.1 s |
| bsave's four turns | 2.2 / 1.2 / 2.5 / 1.3 s | 1.7 / 0.5 / 1.9 / 0.5 s |
| (the abductor with only the searches' early ends, the voxel line still C) | 22.2 s | 10.2 s |
| BENCH: 360 voxel lines / the same on past the tile | 3,457 / 4,110 ms | 751 / 932 ms |
| BENCH: 8 aims (canTargetUnit) | 1,963 ms | 569 ms |
| BENCH: path search, unit 0, 60 TU (a whole search: unchanged) | 249 ms | 249 ms |
| BENCH: average full redraw | 147 ms | 147 ms |

The game's state: every turn's LOG the same as before (positions, shots, hits, the
same lines; only the "N ms" figures differ), `make test` and `make test-long` pass.

### What limits it now

- The voxel line: about 40,000 cycles a line of 16 tiles; per tile crossing about 1,300
  (the tile's parts, the skip's rooms and moves, the step across), per minor-axis move
  about 60, per checked voxel 250-400 (the parts' rows of its layer and y). The sight
  checks that fail (most of them) run all 37 lines to the obstacle, usually most of the
  way (two thirds on average). A cache of the tiles' columns by their four records
  (exact) gained 2 % and was dropped.
- The path search: about 8,000 cycles a tile expanded (10 directions with path.c's
  step rules). Searches repeated with the same unit, start, TU and world (an abductor's
  turn: about 15 % of its tiles) could be skipped with a world version (path.c's
  tile_update, way.c's door flips, the units' positions): not done.
- The rest of an alien turn: the AI's own C (patrol_ok, unit_fits_at: 5 % of an
  abductor's turn), interrupts and the music task (about 10 % of the CPU).
- So a first turn of a small battle is 5-7 s, not 1-3 s: the lines it must trace for
  sight are the turn. NOEXACTAI (the engine's option) remains the way to 1-3 s, with
  the tile-based sight it brings.

### Sizes

The main bank without movable code: 51,687 bytes (code that must stay 9,440, constants
3,993, data 416, bss 37,838; before 51,462) + heap 2 KB + stack 8 KB = 61,927 of 65,264:
**3,337 bytes left** (225 taken: hz_vox.s's tables and variables, hz_path.s's few).
hz_vox.s (about 2 KB) and the rest of the new code are movable (code banks). XCOM.PRG
about 950 KB.

## 5. The plan

Principle: **upstream's code runs unchanged** on a model of the machine it was written for;
the port is `compat/` + `plat/` + back ends + one small patch of `#if defined(XCOM_PORT)`
hooks. Every assembly routine becomes C with upstream's name and arguments (the asm's
comments are the specification; OpenXcom's C++ for the voxel line). To follow upstream (an
alpha that changes weekly): change `COMMIT` in `tools/getsrc.sh`, `make src`, fix the hunks
that do not apply (12 files, small hunks at function heads), re-check the assembly files
that changed (`git diff OLD NEW -- src/*.asm`: each has its C twin in `plat/`, named alike).
A fork would be faster today and unmergeable in a month.

| Stage | Delivers | Tested by | Size (new lines) |
| --- | --- | --- | --- |
| 1 (done) | assessment; converter on Linux; DOS model; the VGA interface, geoscape and battle view in C; the game's assembly in C (floor pass, LOS fan, voxel line, waypoints); the host runs menus, geoscape, base screens and battles; 816 compiles; measurements | `make check-host` (14 pictures); BENCH's self-checks; voxcheck.py against OpenXcom; `tests/bench816` | 5,200 (`plat/`, `compat/`, `host/`, `horizon/`, tests) |
| 2 | **the host complete**: heldasm, cutasm's FLI, DOS's smoke/fire pictures, the night lights in C; a check of the LOS fan (a C reference from the asm's comments, compared on random fans); the 32-bit `int` audit; reference runs: KEYS scripts for a campaign month, base screens, a terror site, a night battle, saves, with `SEED`, LOG and pictures as checksums | `make check-host`: LOG and pictures equal run to run | 1,500-2,000 |
| 3 | **SDK far data model** (cc816 + libc, by the SDK's owner) **or** the fallback: a build-time source pass (`tools/farify.py`: `__far` on every data pointer declarator of upstream's files, using a typedef table; the library calls through far wrappers) — decided at the start of the stage. Then the engine boots on the 816 to the start menu and the geoscape with the virtual clock (`/V`): pictures and LOG compared with the host's for the same KEYS script | 816 vs host: LOG lines equal, pictures equal (checksums), at the same script steps (`--shot-on` on the engine's own lines) | far model: SDK work (estimate 1,500-2,500 lines in cc816 and the library); fallback: 600 lines of tool + a few dozen hand fixes |
| 4a (done) | `make test` (host vs Atari816: LOG, pictures, saves, BENCH, real input); the 16-bit host; polling; the battle view by Ali (atlases unpacked on the machine); the screen split | section 4c | |
| 4 | **speed**: battle sprites to blitter atlases (`tools/mkatlas.py` after XCOMCONV; the floor pass and render.c's sprite calls make sheet records; the back buffer a framebuffer page), pictures by `hz_read` into the framebuffer, the geoscape zoom in assembly, the voxel line / path search / LOS fan profiled (`prof816.py`) and moved to assembly where they dominate (the alien turn: upstream says 20 s on a 286 for the first jungle turn in exact mode); the 2.0 MB of UI pictures cached in far memory; the battlescape split | `BENCH` on the 816 against the 286 figures (full redraw 0.2-0.3 s, alien turn); the same LOG as the host (logic unchanged) | 2,000-3,000 (half assembly) |
| 5 | **the game**: sound (music.c on the music timer, effects on Lau and POKEY), saves next to the program, 4-file limit checked, the intro, the end slides, the APP package (`make app`), README for players | campaign scripts on the 816 against the host's LOG; saves written and loaded; `--wav` checks; `make test`, `make test-app` | 800-1,200 |

Honest size: about 9,000-11,000 new lines in the port (5,200 of them exist now) (plus the SDK's far data model, or the
farify tool), most of them the C and assembly twins of upstream's 6,900 lines of VGA-mode
assembly; the upstream patch should stay under 500 lines. Time: stage 2 two to three
working days of an agent, stage 3 one to two (with the SDK feature ready), stage 4 three to
four (the atlas and speed work, as Prince's and SkyRoads'), stage 5 one to two.

Risks:
- **The data model** (stage 3) is the gate: without far data the engine does not run at all.
- **Speed of the battle**: the 8088 engine is light in logic but its renderer is CPU work
  that only an XT's 64 KB-at-a-time memory made cheap; here sprites must be the blitter's.
  The alien turn in exact mode (voxel lines) is the other heavy part: 20 s on a 286; on the
  816 in C it may be minutes; NOEXACTAI (upstream's XT mode) is the fallback.
- **4 files**: the engine opens packs, the UI pack, the LOG, saves; counted in stage 3.
- **Memory decisions**: the engine sizes its battle lists and picture plans by DOS's free
  memory; the model reports 638 KB free and no UMB/XMS: with EMS/XMS modelled in far banks
  (stage 3) the engine takes its "plenty of memory" paths (every picture, no disk paging).
- **Upstream moves fast**: 0.5.1 is the first public alpha; pin, and merge by stages.
- **The GOG data** is not exactly DOS 1.4 (fonts, texts, HE types): behaviour around the
  patched HE records differs from DOS (those parts do not explode).

## What is next (after stage 5)

| What | Why | Estimate (agent time) |
| --- | --- | --- |
| ~~the A* goal search~~, ~~the voxel line in assembly~~ | done, exact (section 4f): the alien turns 4-5 times faster | |
| the voxel line's tile crossing (about 1,300 cycles) and checked voxels (250-400); a search skipped when the same one was just done (a world version) | a first turn of a small battle 5-7 s (section 4f, "What limits it now"); 1-3 s needs about twice that | 1-2 days |
| the sight fan (`plat/losfan.c`) in assembly | not seen in the turns' profiles (X-COM's fog of war, the player's turn) | 0.5 day |
| the start-up's CPU part (3 s: the palette and picture loaders read through stdio byte by byte) | the start menu sooner | 0.5 day |
| the main bank: `hgame`'s queues (the `.s` code moved: done, section 4) | room for the next changes | with the SDK |
| per-cell night lights (OpenXcom's lighting, a table per level at the present) | flares and fires lighting their area | 1 day |
| the FLI's runs in assembly | the intro's explosion scene (1.1 s behind at worst) | 0.5 day |
| report upstream: faults 1, 2, 3, 5, 6, 8 above, the GOG data, voxcheck.py | | |

## What the user needs to provide or decide

- To play on the board: the packs on the card (`make card`, or copy data/packs as
  app/README.TXT says) and XCOM.HZA installed. Nothing of this round was tried on the
  board (the emulator only): the card's speed, the OPL2's and Lau's sound are its own.
- Whether to release XCOM.HZA (GPL-3, no data) beside the other ports.
- Whether the GOG edition is the one to support (the converter patch), or a DOS 1.4 copy.

## Time (stage 1)

About 4 h 30 of the agent's time: reading upstream and the SDK 1 h, the DOS model and the
host build 1 h 15, the converter 20 min, the VGA interface and the geoscape in C 1 h, the
816 compile, the bench and these notes 55 min. A helper agent wrote the battle side's C
(`vgabat.c`, `rend.c`, `losfan.c`, `voxrun.c`, `way.c`: about 2,000 lines) in parallel in
12 minutes of wall time and checked it with upstream's tests.

# Porting notes: XCOM-XT on the Atari816

Stage 1 (assessment and foundation), 23 November 2026.

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

Implemented in `horizon/hz_plat.c`: every screen pans (the 180 lines show rows from
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

## What is next (after stage 4a)

| Stage | What | Estimate (agent time) |
| --- | --- | --- |
| 4b speed | the redraw to 0.15 s: profile the redraw alone, the floor pass (`plat/rend.c`) and `hz_bb.c`'s record path in assembly, the atlas filled at the battle's start; the smoke/fire overlay by Ali's EXPAND; the night present in assembly; the alien turn and voxel lines (BENCH: 360 voxel lines 3.3 s, path search 0.6 s, 8 aims 1.7 s) profiled and the hot ones in assembly; the geoscape's zoom 1-2 (assembly row doubler); UI text (`vga_uk_glyph`, 8 % of the geoscape) | 2-3 days |
| 5 sound | music: `music.c` already writes the OPL2 (`hg_opl_write`) from the timer hook run at polls: move the hook to Horizon's music timer so it keeps time while the engine draws (as `ports/digger`), check with `--log-opl-us`; effects: SOUNDS.PAK's 4-bit samples to Lau (`hg_sound_from`, decoded at load), the PC speaker's tones to POKEY; `--wav` checks in `make test` | 1 day |
| 5 files | saves next to the program (they are: the program's folder), battle saves (`bsave.c`) in a test; the 4-open-files limit counted (UIV.PAK held while a screen is up, a mission pack, the LOG reopened per line, a save) | 0.5 day |
| 5 intro | the FLI intro and end slides (`cutasm.asm`'s VGA chunks in C), `NOINTRO` no longer needed | 0.5-1 day |
| 5 app | `make app`/`make test-app` (APP.INF, `--needs horizon=0.30,blitter,mem=4096K`, icon, the packs: 18 MB of VGA packs in the app folder, or the user's own converted copy) | 0.5 day |
| 2 rest | heldasm (the inventory's held item), DOS's smoke/fire pictures, the night lights | 1 day |

Honest remaining work: about 6-8 agent days to a complete, playable app; the battle's speed
(4b) is the one with risk (the engine's render and AI code in C through far pointers).

## What the user needs to provide or decide

- Nothing to run stage 2 (the data is here).
- A decision on the far data model (SDK need 1) before stage 3: build it into cc816, or
  accept the farify fallback.
- Whether the GOG edition is the one to support (the converter patch), or a DOS 1.4 copy.

## Time (stage 1)

About 4 h 30 of the agent's time: reading upstream and the SDK 1 h, the DOS model and the
host build 1 h 15, the converter 20 min, the VGA interface and the geoscape in C 1 h, the
816 compile, the bench and these notes 55 min. A helper agent wrote the battle side's C
(`vgabat.c`, `rend.c`, `losfan.c`, `voxrun.c`, `way.c`: about 2,000 lines) in parallel in
12 minutes of wall time and checked it with upstream's tests.

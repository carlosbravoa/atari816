# This fork of XCOM-XT

This folder is **our fork of XCOM-XT** (<https://github.com/fmikowski/xcom-xt>, GPL-3,
by Filip Mikowski and others), taken at upstream's commit `a53918220c90` (18 November
2026, alpha 0.5.1; the full hash is in `COMMIT`). Upstream's tree came in unchanged in
commit `cca0456` of this repository (without `release/screenshots/`); every change since
is ours and is made here directly.

The fork serves two targets:

- **the Atari816** (`ports/xcom/` around this folder: its own platform layer in `plat/`,
  `horizon/`, `compat/`, `mus/`, built by `ports/xcom/Makefile` with the SDK's `hcc`), and
- **a 286 PC in real-mode DOS** (another project): upstream's own DOS build (`build.ps1`,
  Open Watcom 2.0 and NASM, 16-bit, the overlay manager).

So the engine stays portable: what only the Atari816 needs lives outside this folder or
behind `#if defined(XCOM_PORT)` (the port's builds define it; the DOS build does not), and
what makes the game better for everyone (a fix, a sound) is written in the engine itself,
on the paths the DOS build uses (`src/sound.c`'s Sound Blaster, FM and speaker paths,
`tools/sound.py`). No file of upstream's DOS build was removed or renamed; the files
`ports/xcom/plat/` replaces on the Atari816 (`src/timer.c`, `src/vgainit.c`,
`src/vgageo.c`) are left out by the port's Makefile and stay as they are for DOS.

## Which builds are tested

| Build | How | Tested here |
| --- | --- | --- |
| Atari816 (`XCOM.PRG`, `MUSD.PRG`) | `make` in `ports/xcom` | `make test`, `make test-long`, `make test-app`, `make kit` (emulator; the board by hand) |
| The host (Linux, headless, DOS's 16-bit `int`) | `make host` in `ports/xcom` | compiles every engine file the port uses, with `XCOM_PORT`; the reference of `make test` |
| DOS (`XCOMXT.EXE`, `XCOM286.EXE`) | `build.ps1` (Windows, Open Watcom, NASM) | **not built here**: Open Watcom is not installed on the machines this repository is worked on |

Since the DOS build is not compiled here, every change to `src/` is checked by hand for it:
plain C that Watcom takes (no C99), nothing new in the overlay list, no DOS-only file
changed except where said below. Build it with `build.ps1` before a release for the 286.

## Our changes, by topic

`git diff cca0456 -- ports/xcom/engine` shows them all (about 50 files, 1,500 lines added, at the time of writing).

**The Atari816's hooks** (all `#if defined(XCOM_PORT)`; the DOS build compiles upstream's
code there):

- The VGA prototype's entry points called as C functions (`ports/xcom/plat/vga.c`) instead
  of upstream's self-modifying code: `uik.c` (`uk_theme`, `uk_cga_palette`, `uk_pic_cga`,
  `uk_pic_clean`, `uk_cga_c`, `uk_fill`, `uk_glyph_cga`, `uk_copy`, `uk_save`,
  `uk_restore`), `hud.c` (text, clear), `mouse.c` (pointer draw and erase), `gfx.c`
  (`gfx_dot`, `gfx_night`), `invscr.c` (the VGA colour map), `bplayer.c` (smoke and fire
  pictures' step), `vgageo.h` (the world, XOR, battle and slide entries).
- `geo.c`'s `zoom_bytes` in C (Watcom's `#pragma aux` is assembly).
- The battle pictures prepared for the blitter (`main.c`, `battle.c`: `plat_bb_prepare`);
  `path.c` calls the port's path search in assembly (`hz_path_search`, cc816 only).
- Sound: `music.c` tells the port's music task what it plays (`plat_mus_*`; `mus_play_mem`
  for the task, `XCOM_MUSD`); `sound.c` takes an upper memory block of its own
  (`xd_sound_umb`) and lets the platform decode each effect once (`plat_sfx_preload`); no
  far function pointer for the old IRQ vector (`xd_isr`).
- `pak.c` reads the unit sets' table as 16-bit values (`unsigned` is 32 bits on the host).
- Test hooks: `cut.c` a test picture of each end slide, `input.c` a KEYS script's `WAIT`
  sleeps on the platform, `vbench.c` BENCH's VGA block checks left out and a check of the
  port's smoke and fire pictures instead; at night its screen checks read the port's levels
  shown (`plat/vgabat.c` `vga_lit_shown`) and it prints the night lights' counts.
- The VGA night lights' levels in portable C: `src/vlit.c`, `src/vlit.h` (new files, all of
  `vlit.c` inside `#if defined(XCOM_PORT)`: the DOS VGA build keeps `vgaasm.asm`'s
  `lit_present`, the same model, and gets an empty object). The light map, the sources, the
  20 x 18 cells' levels for the platform (`ports/xcom/plat/vgabat.c` shows them;
  `ports/xcom/PORTING-NOTES.md` section 4k).
- `mouse.c` `busy_tick`: the platform's clock and pointer (`plat_busy_poll`) in the
  engine's busy loops (the turn's end, the AI).
- `pedia.c`: after an article, the screen under the list again (VGA; the port keeps a
  real copy of the clean screen).

**cc816's C** (every build, valid Watcom C): one far declarator a line (`cvpriv.h`,
`xmemlend.h`, `invscr.c`: cc816 rejects `T far *a, far *b;`).

**Fixes of upstream's bugs** (every build; the six we found are to be reported upstream,
`ports/xcom/PORTING-NOTES.md` section 4d, faults 1, 2, 3, 5, 6, 8):

- `vbench.c` `path_search_c`: `cost + 4u * TILES` (`4 * TILES` is 40,000: a 16-bit `int`
  overflow that only DOS's far pointers wrapped back).
- `battle.c` `HURT`: the hit side before the damage roll (both call `rnd`; C leaves the
  order of arguments open: Watcom's right-to-left order made explicit).
- `battle.c` `kill_unit`: a comrade's death's morale loss in `long` (the 16-bit product
  wrapped: no loss, or a gain; OpenXcom loses it as now).
- `music.c` `decode`: an instrument ends at its track's end (GMTACTIC's instrument 10 read
  past it).
- (`pedia.c`'s list over the article, fault 6, is fixed for the port's VGA only, above.)

**Smoothness** (every build; PORTING-NOTES.md section 4h):

- `path.c`, `path.h`: `path_search_begin` / `path_search_more` / `path_search_busy` /
  `path_search_finish`: a whole search in slices where the platform can stop and resume
  it (the Atari816's hz_path.s, XCOM_PORT); elsewhere `begin` is the whole search at once.
  Every other path call (path_cost, path_build, a search, a tile's change, step_cost, the
  checksum) finishes it first. `search` split into `prep` and the search.
- `bplayer.c`: `refresh_paths` with `g_path_slice` (ms; 0, the default: as before) begins
  the search and leaves its rest to the turn's wait (`map_key`'s idle loop, a KEYS
  script's WAIT through `input.c`'s new `g_wait_hook`); the next key finishes it before
  the action; `hud_cursor` shows the TU when it is done. The DOS build and the tests (the
  port's virtual clock) keep 0.
- `panel.c` `number`: the digits without sprintf, one fill a run of a row's set pixels (the
  same pixels).

**Night sight in the LOG** (every build; `battle.c` `update_vision`): at night (the 9-tile
dark range on) each alien that comes into or goes out of X-COM's sight is a LOG line
(`T1: night: alien 14 at 48,38,0 seen by Novak, 81 tiles squared, near` / `... out of
sight`; "on a lit tile" past 9 tiles): what the darkness rule decided, for the tests. No
rule changed: the engine already had OpenXcom's (`los.c` `los_unit_sees`, `effects.c`
`fx_lit`).

**The converter** (`tools/convert.py`): the GOG edition's MCD records with HE_Type 1 (smoke)
are left out of the explosives list instead of stopping the conversion.

**The interface's sounds** (every build; pack format 5):

- `tools/sound.py`: three more effects at the end of SOUNDS.PAK, from SOUND2.CAT (the DOS
  geoscape set, OpenXcom's GEO.CAT): `button` (entry 0, OpenXcom's `Mod::BUTTON_PRESS`),
  `window 1` and `window 2` (entries 1 and 2, `Mod::WINDOW_POPUP[0..1]`; `WINDOW_POPUP[2]`
  is entry 3, upstream's `geo popup`), 8,000 Hz as all DOS samples, with a gain each (0.5,
  0.47, 0.6) to stay under the shots: the Sound Blaster has no volume per effect.
- `src/sound.h`, `src/sound.c`: `SFX_BUTTON`, `SFX_WINDOW1`, `SFX_WINDOW2`;
  `snd_button()` (TextButton::mousePress) and `snd_window()` (Window::popup: one of the
  three at random, on numbers of its own: the game's `rnd()` is untouched); digital
  samples only (no FM or speaker stand-in), not in a battle, at a priority under an alert
  and a battle's effects (the third pop-up is the alert's sample: it plays at the
  interface's priority there). In the geoscape's per-screen list for machines that load
  effects per screen.
- The hooks, one at the place that takes each click (so a button drawn twice clicks once):
  `uik.c` (`uk_buttons_key`: every row of bottom buttons; a column of `UKS_BUTTONS` rows;
  OK of `uk_notice` and `uk_page_wait`; the pop-up of `uk_menu`'s `UKS_POPUP` /
  `UKS_CLEAR` windows and of the message boxes), `geowin.c` (`win_open`, `wait_btn`, the
  interception list's buttons, Select Destination's), `gpop.c` (its windows and buttons,
  the debriefing's OK), `geo.c` (the side buttons and the time buttons; the globe's
  rotate and zoom buttons are not TextButtons in OpenXcom: silent), `basescr.c`,
  `baseinfo.c`, `soldier.c`, `facilscr.c`, `labscr.c` (the arrow buttons: silent, as
  OpenXcom's ArrowButton), `hangar.c`, `graphs.c` (the toggles), `pedia.c` (an
  article's buttons), `saves.c` (the list's window and Cancel), `mreport.c`, `brief.c`.
- `src/packver.h`: format 5, so that packs from an older converter are refused (the DOS
  build: "Packs are from another version"; the Atari816 says so on its screen).

**Closer to the original** (every build; pack format 6). What the DOS game does is taken
from OpenXcom's source (which reproduces it and names each sound, timing and window:
`src/Interface/Window.cpp`, `TextButton.cpp`, `Geoscape/BaseNameState.cpp`,
`BuildNewBaseState.cpp`, `Battlescape/UnitWalkBState.cpp`, `ExplosionBState.cpp`,
`Inventory.cpp`, `ProjectileFlyBState.cpp`, `BriefingState.cpp`, `DebriefingState.cpp`,
`Mod/Mod.cpp`; the rules `bin/standard/xcom1/*.rul`) and from ufopaedia.org's list of the
sound files (SOUND page: what each SOUND1.CAT entry is).

- Windows pop up (`uik.c` `uk_popup`, `uk_popup_bg`): Window::popup's animation, the frame
  growing from the window's centre (both ways, across or down: each window as its
  OpenXcom state's `WindowPopup`) in 20 steps of 14 ms (0.28 s: a step a frame at the
  VGA's 70 Hz; OpenXcom's 0.05 a frame), the inside (the clean copy, a picture or black)
  in it, the window's contents drawn when it has opened; the pop-up sound as it starts.
  The pointer stays alive (`input_ready` each step: a click waits for `input_key`); on
  EGA and CGA the frame's left edge stays on whole bytes. Windows that do not pop up in
  DOS open at once and silently (`UK_POP_NONE`: ConfirmDestination, ConfirmCydonia,
  AlienBase, NewPossibleResearch / Manufacture, ResearchInfo, ManufactureStart,
  DismantleFacility, SackSoldier, UfopaediaSelect, TransferBase; these had the pop-up
  sound before). `uk_menu`'s styles `UKS_POPH`, `UKS_POPV`, `UKS_POPNONE` (the field is
  16 bits now); `geowin.c` `win_open`, `gpop.c` `win`, `labscr.c` `popup` take the kind;
  `saves.c` (ListGamesState) pops up over the screen instead of replacing it.
- A menu drawn again under a window that has closed does not pop up again (the start
  menu after Load Saved Game's list or the difficulty's Cancel, the UFOpaedia's start
  after an article): `uk_menu` keeps the pop-up menus open now, the first under the
  others (OpenXcom's state stack); a menu drawn again that is among them closes the ones
  over it; `uk_popup_reset` (`uk_screen`, the geoscape's `draw_map`) forgets them all.
- Buttons press (`uk_press`, `uk_held`): TextButton drawn pressed with the click when the
  left button goes down, kept so while it is held, drawn again as it was before the
  action (OpenXcom acts on the release); a KEYS script's `HOLD x y n` holds it n x 20 ms.
  Every row of bottom buttons (`uk_buttons_key`), the columns of `UKS_BUTTONS` menus, the
  geoscape's pop-ups (`geowin.c`, `gpop.c`: the label kept in `Hit`, the label was blank
  before), the six function buttons of the geoscape (`geo.c` `side_press`), the base
  screen's buttons, Base Information's, Dismantle's and Sack's OK / CANCEL, the craft
  screen's OK, research and production (`labscr.c`), the UFOpaedia article's, Load /
  Save's CANCEL, the monthly report's and the briefing's OK, Monthly Costs' OK.
- The first base is named (`uik.c` `uk_name_box`, `geo.c` `place_base`): BaseNameState,
  192 x 80 at 32, 60 on BACK01, popping up, "Base Name?" in the big font, the name typed
  in the big font after a blinking caret (TextEdit: every 0.1 s), OK only while there is
  a name, Enter / Esc / OK end it, nothing cancels it. Build New Base's name is the same
  window (was a text box with the region's name filled in). Placing a base shows
  BuildNewBaseState's window over the map's top (256 x 28 on BACK01, "SELECT SITE FOR NEW
  BASE", CANCEL but for the first base; `geo.c` `base_site_window`).
- A UFO's detection plays no alert of its own (`geo.c`): DOS has none; UfoDetectedState's
  window pops up with one of the three pop-up sounds (upstream's "alert" is the third
  pop-up sound, GEO.CAT 3: it held the window's own sound off).
- The battle's samples (`tools/sound.py`, `src/sound.c`): SOUND1.CAT's entry 0 is the
  snakeman's slither (ufopaedia.org; OpenXcom's snakeman moveSound 0), not an explosion:
  explosions are entry 2 (SMALL_EXPLOSION, power up to 80) and 5 (LARGE_EXPLOSION) by
  their power (`snd_blast`, `bview.c` `bv_blast` takes it). Footsteps by terrain
  (`snd_footstep`, `battle.c` `step_sound`): Tile::getFootstepSound (the floor's, an
  object's that is no big wall, a stair top's below), the MCD's Footstep byte in a new
  mission pack section "XFS1" (`tools/convert.py` `footsteps`, `src/pak.c`, `MCD_STEP`;
  `g_pak.he` grew by a byte a record), WALK_OFFSET 22 + 2 f at the walk's phase 3 of 8
  (the tile left) and + 1 at phase 7 (the tile reached): 1 metal (the craft, the X-COM and
  alien bases), 2 ground, 3 furniture and rock, 5 sand, 6 the UFOs and Mars. Flying units (`walk_flies`): the flying
  warble (FLYING_SOUND 15) once a step instead (floaters always, as their moveSound; a
  flying suit or hovertank in the air or going up or down). The UFO's sliding doors
  (SLIDING_DOOR_OPEN 20, `bdoor.c`), the inventory's drop (ITEM_DROP 38) and reload
  (ITEM_RELOAD 17, also the battle's reload, `bact.c`), a throw's swish (ITEM_THROW 39:
  upstream had the sample but never played it) and its landing (ITEM_DROP, 0.3 s later:
  the flight is not drawn), machines' deaths (23: tanks, cyberdiscs, sectopods,
  `battle.c` `unit_mech`), the autocannon's shot (12, was the rifle's), the rocket
  launcher's (52) and the blaster and small launchers' (53). Where a new sample is not
  loaded (FM or speaker machines, effects per screen) an older effect stands in.
- Music as DOS's (`src/sound.c`, `tools/sound.py`, `src/music.h`): the start menu plays
  GMSTORY once (MainMenuState's interface; was GMGEO1), a briefing its deployment's
  (GMDEFEND, terror sites and base defence GMENBASE, Cydonia GMNEWMAR; was silent), the
  battle GMTACTIC (Cydonia too; was GMMARS), the debriefing GMMARS
  (`DEBRIEF_MUSIC_GOOD` / `_BAD`; was GMWIN / GMLOSE at the battle's end, which DOS plays
  at the game's end only), the geoscape GMGEO1 in the first month, then GMGEO1 or GMGEO2
  at random (GeoscapeState::init; GMGEO2 was converted but never played). MUSIC.PAK has
  four more tracks (2-2.3 KB each).
- `src/packver.h`: format 6 (older packs are refused: make them again). The Atari816's
  sample cache (`ports/xcom/horizon/hz_snd.c` NCACHE) 48 entries.
- Memory (every build with a 64 KB UMB for the sound): the 42 effects take 59,448 bytes of
  it (46,154 before), the battle's track 4,797 after them (1,275 left); the geoscape's
  tracks (GMGEO1 14 KB, GMGEO2 23 KB) no longer fit beside the effects and go to
  conventional memory in the geoscape (kept only while 15 KB stay free: `RESERVE`; the
  battle is where memory counts, and its track stays in the UMB). (A UMB too small for all
  the effects: in XMS, or per screen, as before.) `g_pak.he` grew by a byte a MCD record (the footsteps,
  up to 338). `ports/xcom/PORTING-NOTES.md` section 4i.

## How to see our diff

```sh
git diff cca0456 -- ports/xcom/engine            # everything since upstream's tree
git diff cca0456 --stat -- ports/xcom/engine
git log --oneline cca0456.. -- ports/xcom/engine  # change by change
```

## Taking a newer upstream

Upstream's tree at `cca0456` is the merge base. For a newer upstream commit NEW:

```sh
git switch -c xcom-upstream cca0456          # a branch at the old upstream tree
git clone https://github.com/fmikowski/xcom-xt /tmp/xt && git -C /tmp/xt checkout NEW
rsync -a --delete --exclude .git --exclude release/screenshots /tmp/xt/ ports/xcom/engine/
git -C /tmp/xt rev-parse HEAD > ports/xcom/engine/COMMIT
git add -A ports/xcom/engine && git commit -m "ports/xcom/engine: upstream at NEW"
git switch dev && git merge xcom-upstream     # our changes carried onto upstream's
```

In words: on a branch from `cca0456` (where `engine/` is upstream's tree and FORK.md does
not exist yet), replace `ports/xcom/engine/` by upstream's new tree as cca0456 did (no
`release/screenshots/`, `COMMIT` the new hash), commit, and merge that branch into ours:
git carries our changes over and stops only where upstream changed the same lines. The
next update branches from that upstream commit instead of `cca0456`.
Then: the assembly files upstream changed (`git diff cca0456 xcom-upstream --
ports/xcom/engine/src/'*.asm'`) each have a C twin in `ports/xcom/plat/` that must follow;
`PACK_FORMAT_VERSION` (ours is 6): take the higher of the two plus one if both changed the
packs; `make test` (its pictures' references move if upstream changed what is drawn).

## Differences from the original game

What was noticed while working on the fork, compared with the DOS game (OpenXcom's source
and rules for its behaviour, ufopaedia.org for its files; upstream's own list:
`release/MANUAL.TXT` section 12). Fixed so far: the button and pop-up sounds (pack format
5); the windows' pop-up animation, the menus that popped up again, the pressed buttons,
the base's name, the detection's alert, the battle's samples, the music per screen
(pack format 6, "Closer to the original" above).

### How complete the game is

Checked in the engine's code (not only upstream's claims). Implemented: as DOS. Partial:
what is missing is said.

| Part | State | What is missing (where; estimate) |
| --- | --- | --- |
| Geoscape: time, the 6 speeds, alien missions of every DOS type (research, harvest, abduction, infiltration, base, terror, retaliation, supply), UFO flight paths, detection, hyper-wave decoder | implemented | the 5-second speed moves craft and UFOs once a game minute (`geo.c` `time_step`: `second` piles up), not every 5 s (1-2 days); the clock steps every 120 ms (OpenXcom geoClockSpeed 80) |
| The world | partial | a flat map with 3 zooms, no rotating globe (weeks; maybe not practical on an XT), no day / night shading (`geo.c` `draw_world`; 2-3 days VGA, 2 more EGA / CGA), no radar circles (1 day) |
| Interception and the dogfight (5 stances, disengage, minimise, up to 4, damage, the UFO's picture) | implemented | the globe's zoom before a fight (follows the flat map) |
| Crash and landing sites, terror sites, alien bases (found by patrols and agents, assaulted), retaliation and base defence (the defences' shots, then the battle in the base), monthly report, funding, pacts, game over | implemented | base defence's shots are a list on one page (`facilscr.c` `facil_defend`; 0.5 day) |
| Graphs, statistics | implemented | |
| UFOpaedia (texts, pictures, stats) | partial | a weapon's page shows its power, not DOS's table per ammunition (`pedia.c` `show_stats`; 0.5-1 day) |
| Bases: building, placing, dismantling, up to 8 bases, base information, stores, costs, transfers, purchase and sale (corpses, artefacts, craft), hiring and sacking, research, manufacture, psi labs and training, alien containment and interrogation, defences, grav shield, mind shield | implemented | soldiers have no gender (`base.h`): the death screams alternate male and female |
| Soldiers: stats, ranks, promotions, experience, rename, armour; craft: weapons, crew, items, HWPs, refuelling, rearming, repairs | implemented | |
| Battlescape: the 6 terrains and cities, the 8 UFOs, terror sites with civilians, alien bases, both stages of Cydonia; fog of war, night and flares, reaction fire, morale, panic, berserk, psionics (panic, mind control, psi amp), mind probe, medikit, motion scanner, stun rod, melee (chryssalids turning victims into zombies, reapers), proximity and primed grenades, high explosive, blaster bomb waypoints, smoke, fire, destructible terrain, doors, kneeling, reserved TU, inventory, flying, grav lifts, levels, abort, hidden movement, captures, debriefing, score | implemented | |
| Terror units | partial | the cyberdisc's explosion when it dies and the silacoid's burning (specab 1 and 2: no flag in `pak.h`; 1 day) |
| The battle's unit stats (UnitInfoState, the click on the rank) | missing | `panel.c` `panel_click` (1 day) |
| Limits | partial | 60 units on a map, 26 soldiers, 8 tanks a battle; 100 soldiers a base, 250 in all; bodies cannot be thrown (`MANUAL.TXT` 12) |

### Presentation differences

| What | Where | Estimate |
| --- | --- | --- |
| Soldiers jump from tile to tile with 2 leg pictures (4 with extra memory) instead of DOS's walk of 8 frames a tile; a turn jumps to the last direction | `render.c`, `sprcache.c`, `battle.c` `walk` | 3-5 days, memory-bound |
| Shots are a dotted line, a thrown grenade is not drawn in flight (its landing sounds 0.3 s after the throw) | `battle.c` | 2 days |
| An explosion is one picture for 0.4 s, not DOS's animated fireballs (ExplosionBState: power / 5 explosions spreading) | `bview.c` `bv_blast` | 1-2 days |
| UFO doors open at once (DOS animates them; SLIDING_DOOR_CLOSE, SOUND1.CAT 21, at the turn's end, is not in the packs) | `bdoor.c` | 1 day, 1.2 KB of samples |
| Night: on EGA two light levels instead of DOS's 16 (VGA: the 16, per cell of 16 x 8 pixels, upstream's `vgaasm.asm` `lit_present` and the port's `vlit.c`; DOS shades each tile's pictures by the tile's level, so a cell is up to 1.5 tiles off at a light's edge) | `nlit.c` | (memory) |
| The selected soldier's arrow and the cursor do not bob or blink | `rcursor.c` | 0.5 day |
| The pointer's colour is the same everywhere (OpenXcom: 252 on the geoscape, bases, UFOpaedia and graphs, 144 in a battle) | `mouse.c`, `ports/xcom/plat/vga.c` | 0.5 day |
| Units' own move sounds are not in the packs: tanks (SOUND1.CAT 14), hovertanks and cyberdiscs (40), snakemen (0), silacoids (47), celatids (16); the walkers play footsteps, the fliers the flying warble | `sound.c`, `battle.c` `walk_flies` | 2 h, about 8 KB of samples (the sound's 64 KB UMB has 1.3 KB left in a battle) |
| Missing battle samples: AP rounds' hit (13), melee attacks (48-50, 54), the celatid's death (7), the second and third male and female screams (42, 43, 45, 46), psi (36), mind probe (37) | `sound.c` | the same: the UMB is full (on the Atari816 the packs' 3 far banks have room) |
| Effects are one at a time (a click cuts a pop-up's tail); DOS mixes none either, OpenXcom does | `sound.c` `play` | (as DOS) |
| No interface sounds in a battle (its options, abort, save windows): DOS's tactical part loads SOUND1.CAT only, we believe it is silent there too (OpenXcom plays them) | `sound.c` `ui_sound` | 1 h if DOS has them |
| Windows pop up 0.28 s, at the VGA's frame rate; OpenXcom takes 20 of its frames (0.33 s at 60 per second) | `uik.c` `POP_STEP_MS` | (a number) |
| Placing a base needs Enter or a second click on the marker (DOS: one click), and the base's cost is asked in a message box (ConfirmNewBaseState: 224 x 72 at 16, 64 with the area and cost) | `geo.c` `pick_point`, `new_base` | 2 h |
| Soldiers, craft and bases are renamed in a message box (OpenXcom: the name's field edits in place) | `uik.c` `uk_edit` | 0.5 day |
| The intro has no digitised effects (`MANUAL.TXT` 2) | `cut.c` | 1 day |

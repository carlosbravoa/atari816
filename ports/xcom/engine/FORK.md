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

`git diff cca0456 -- ports/xcom/engine` shows them all (about 40 files, 690 lines added, at the time of writing).

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
  port's smoke and fire pictures instead.
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
`PACK_FORMAT_VERSION` (ours is 5): take the higher of the two plus one if both changed the
packs; `make test` (its pictures' references move if upstream changed what is drawn).

## Differences from the original game

What was noticed while working on the fork (upstream's own list: `release/MANUAL.TXT`
section 12). Fixed in this round: the button and pop-up sounds (above).

| What | Where | Estimate |
| --- | --- | --- |
| Windows open at once; DOS (and OpenXcom) grow them for a moment (the pop-up animation) | `geowin.c` `win_open`, `gpop.c` `win`, `uik.c` `uk_menu`, `box` | 0.5-1 day (a few frames of a growing frame, VGA and EGA) |
| A menu window drawn again after the menu it opened (e.g. the start menu after Load) pops and sounds again; OpenXcom's stays | `uik.c` `uk_menu` (`shown`) | 1-2 h |
| Most buttons do not show the pressed state (TextButton inverts while the mouse is down); only the geoscape's pop-ups flash | `uik.c` `uk_buttons_key`, `uk_menu`; the screens' own hit tests | 0.5 day |
| The first base is named after its region; DOS asks for a name (BaseNameState) | `geo.c` `place_base` | 1 h, and every new-game test picture moves |
| A UFO's detection plays the alert sample, which then holds off its window's pop-up sound; to compare with DOS | `geo.c` (the alert, `geo_popup`) | 1 h |
| No interface sounds in a battle (its options, abort, save windows); DOS's battlescape loads SOUND1.CAT only, so we believe it is silent there too: to check on DOS | `bsave.c`, `batui.c`, `bact.c`; `sound.c` `ui_sound` | 1 h if it is not |
| Effects are one at a time (a click cuts a pop-up's tail); DOS mixes none either, OpenXcom does | `sound.c` `play` | (as DOS) |

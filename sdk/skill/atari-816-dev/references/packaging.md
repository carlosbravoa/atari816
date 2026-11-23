# Packaging a program as a Horizon app (.HZA)

Purpose: turn a program into an app (Horizon 0.29+): its folder in `/APPS`, `APP.INF`, an
icon, its needs, the `.HZA` archive, the Installer, where saves go, and how to test the
install in the emulator. Source: `sdk/docs/apps.md`, the Installer `horizon/user/install.s`,
the Desktop's reader `horizon/user/uiapp.s`, `ports/digger` (the first app). Every
command below was run.

## The app folder

An app is one folder, `/APPS/NAME/`, holding everything it needs:

```
/APPS/DIGGER/
    APP.INF          what the app is
    DIGGER.PRG       the program
    DIGGER.DAT       its data
    DIGGER.ICN       its icon (32 x 32, 1024 bytes)
    DIGGER.SCO       written by the program later: never in the archive
```

The folder's name is the app's name on the card (at most 32 characters, not starting with
`.`). No shared libraries, no dependencies between apps. The Desktop lists the apps in its
Programs menu after Horizon's own programs (sorted by name; a `category` groups them under
"Games >"; 24 lines, then "More apps >"; at most 64 apps). A program right in `/APPS`
(where run816.py puts programs) or a folder with a program and no APP.INF is listed too.
On Horizon 0.28 and older there is no Installer and the Desktop does not read `/APPS`.

## APP.INF

`key=value` lines; keys ignore case; spaces around key and value dropped; `#` lines,
empty lines and unknown keys ignored; CR LF or LF; Horizon reads the first 1023 bytes;
every key optional; longer values are cut.

| Key | Max | What |
| --- | --- | --- |
| `name` | 24 | name in the Programs menu and the Installer. Default: the folder's name |
| `program` | 63 | the program file. Default: `FOLDER.PRG`, else the folder's only `.PRG`; needed when there are several and none is named like the folder |
| `category` | 15 | groups apps under one menu item ("Games >") |
| `version` | 15 | shown by the Installer |
| `description` | 63 | one line, shown by the Installer |
| `types` | 47 | extensions it opens, comma-separated: `types=DIG,LVL`. A double click on such a file starts the app with the full path in quotes as its argument: `"/GAMES/LEVEL1.DIG"`. Horizon's own types keep their programs |
| `icon` | 31 | a built-in icon name or an icon file in the folder |
| `needs` | 47 | the same list as `hcc --needs`, for the Installer to show (the program checks itself). Leave it out: `hzapp.py pack` copies the program's list into the archive's APP.INF |

Built-in icon names (`apinames` in `horizon/user/desk.s`): `folder sd atari doc text
writedoc sheetdoc picture basdoc disk xex cart program edit write sheet paint basic calc
solitaire terminal files settings about pc freecell music musicdoc`.

Digger's (`ports/digger/app/APP.INF`; its Makefile strips the `#` lines when copying):

```
name=Digger
version=1.0
description=Windmill Software's Digger (1983), from Digger Remastered
category=Games
program=DIGGER.PRG
icon=DIGGER.ICN
needs=horizon=0.28,sprites,mem=1280K
```

Digger has no `types=DRF`: it takes a recording as `/P:file`, not as a bare path, so a
double click could not play one. Only register a type the program opens from `argv[1]`.

## Icons

An icon file: 32 x 32 pixels, one palette index a byte, row by row, 255 = transparent:
exactly 1024 bytes. From a picture (a game's sprite as a PNG with alpha):

```
python3 SDK/tools/hzapp.py icon sprite.png build/HELLO/HELLO.ICN --preview build/icon.png
```

(Pillow needed.) Larger pictures are scaled down (pixel art by a whole-number step when its
size allows), smaller ones centred; nearest colours of the Desktop's palette; alpha below
128 transparent; the drop shadow added (`--no-shadow`: none). Look at the preview. Or make
one from a text drawing with Horizon's `tools/mkicons.py`
(format: the header of `horizon/sdfiles/icons.txt`): `color C N` lines map a character to
a palette index (`.` must be mapped too: `color . 255`), then `icon NAME` and exactly 32
rows of 32 characters. House style: 1-pixel black outline, light top/left inner edge, dark
bottom/right, a drop shadow in colour 15 one pixel right and down. Palette: 0-15 UI
colours, 16-231 the cube `16 + 36r + 6g + b`, 232-255 greys.

```
python3 HORIZON/tools/mkicons.py icon.txt HELLO.ICN /dev/null     # -> 1024 bytes
```

(The third argument is a ca65 include of the icon numbers; not needed for an app.)
Digger makes its icon from the game's sprite (`tools/mkdata.py --icon`, the same method as
`hzapp.py icon`). The pixel art rules: `references/pixel-art.md`.

## What a program needs: hcc --needs, HZ_NEEDS

The program checks its needs itself before `main`; a program copied to an old card says
what is missing and exits 1 instead of crashing. The message goes to the console and, when
the window system runs, into a small window.

```
hcc --needs horizon=0.29,mem=256K -o HELLO.PRG hello.c     # repeatable; comma-separated
```

| Need | Checked |
| --- | --- |
| `horizon=0.29` | Horizon version at least this |
| `rev=11` | hardware revision at least $0B |
| `lau` | Lau, the sample player (REV $0A+) |
| `opl2` | the OPL2 (REV $0C) |
| `sprites` | Marga's sprites and scrolling (REV $0B+) |
| `blitter` | the blitter (REV $08+) |
| `mem=1024K` / `mem=2M` | free memory at start (at most 65535K) |
| `joystick` | not checked (cannot be detected); the Installer shows it |

With `--code large` hcc raises `horizon` to at least 0.28. Without `--needs` nothing is
checked. Before 0.29 the check tells 0.28 and 0.27 apart, calls older "0.26 or older",
and cannot check a revision, sprites or the blitter (they pass).

Messages (run on the emulator):

```
NOPL needs the OPL2 sound chip (hardware revision $0C).          # --needs opl2, --rev 11
CNEEDV needs Horizon 0.99 or later (this is 0.29).               # sdk/c/tests/run.py
ASMAPP needs Lau, the sample player (hardware revision $0A or later).
MEM needs 60000 KB of free memory (5248 KB free).                # --needs mem=60000K
```

hcc refuses bad lists (exit 1):

```
hcc: --needs: horizon=1: a version such as 0.29
hcc: --needs: unknown need 'warp' (horizon=X.Y, rev=N, lau, opl2, sprites, blitter, joystick, mem=NK)
hcc: --needs: mem=99m: KB of free memory, such as 1024K or 2M (65535K at most)
```

**In assembly**: `.include "needs.inc"` and put `HZ_NEEDS` first at `start`:

```asm
        .include "horizon.inc"
        .include "needs.inc"
        .segment "CODE"
        .a16
        .i16
start:  HZ_NEEDS "GAME", 0, 29, 0, NEED_OPL2 | NEED_LAU, 1024
        ; the program: A and X are still the start conditions (the argument string)
```

Arguments: name (15 characters at most), Horizon major, minor (0, 0 = any), lowest
revision (0 = any), `NEED_LAU | NEED_OPL2 | NEED_SPRITES | NEED_BLITTER | NEED_JOY`, KB of
free memory (0 = any). 650-720 bytes of code, no zero page. `sdk/c/tests/apps/asmapp.s` is
a working example. Horizon 0.29's `sys_info` ($36; C: `hz_sys_info()`) returns the
version (major * 256 + minor) in A and the revision in X (`hz_x`).

## hzapp.py: check, pack, list

```
python3 SDK/tools/hzapp.py check FOLDER|FILE.HZA     # checks only; exit 1 on an error
python3 SDK/tools/hzapp.py pack FOLDER [-o FILE.HZA] [--mtime N] [--needs-from-program]
python3 SDK/tools/hzapp.py list FILE.HZA             # its files and APP.INF
python3 SDK/tools/hzapp.py icon IMAGE.png OUT.ICN    # an icon from a picture (above)
```

The needs are written once, in the program. `pack` with an APP.INF without `needs=` puts
the program's list into the archive's APP.INF (`hzapp: the archive's APP.INF:
needs=horizon=0.29,mem=256K added, from HELLO.PRG (the folder's APP.INF is not changed)`).
A `needs=` that differs from the program's is a warning; `--needs-from-program` replaces it
in the archive. `check` prints what the program checks: `HELLO.PRG checks:
horizon=0.29,mem=256K`.

A real run (`build/HELLO` = APP.INF, HELLO.PRG built with `--needs
horizon=0.29,mem=256K`, HELLO.ICN):

```
$ python3 SDK/tools/hzapp.py pack build/HELLO -o HELLO.HZA --mtime 0
Hello 1.0 - Counts its runs in its own folder
  category: Tests
  needs: horizon=0.29,mem=256K
  3 files, 18 KB, into /APPS/HELLO
hzapp: HELLO.HZA: 30,720 bytes
$ python3 SDK/tools/hzapp.py list HELLO.HZA
  APP.INF  127
  HELLO.ICN  1,024
  HELLO.PRG  16,342
Hello 1.0 - Counts its runs in its own folder
...
hzapp: OK
```

What it checks: APP.INF present, known keys, values within the sizes; `icon=` a built-in
name or a 1024-byte file in the folder (a warning); the program present
(`program=`, else `FOLDER.PRG`, else the only `.PRG`) and an o65 Horizon program; its
needs block against APP.INF's `needs=` (a warning); every name one FAT and the Installer
accept (printable ASCII without `\ : * ? " < > |`, no part ending in `.` or space or
starting with space; folder at most 32 characters; paths inside at most 112,
`/APPS/NAME/path` at most 127); dot-files left out (warning); links refused; files of
16 MB or more warned. Real messages:

```
hzapp: warning: APP.INF says needs=horizon=0.29, but HELLO.PRG checks horizon=0.29,mem=256K
hzapp: OK (1 warning(s))                                          # exit 0
hzapp: error: a?b.txt: the character '?' is not allowed (printable ASCII without \ : * ? " < > |)
hzapp: error: the folder has no APP.INF
hzapp: 2 error(s)                                                  # exit 1
```

`--mtime 0` gives every entry the same time: the same archive byte for byte on every
build. Plain tar works too, from the folder holding the app's folder:
`tar --format=ustar -cf DIGGER.HZA DIGGER` (`COPYFILE_DISABLE=1` on macOS). Without
`--format=ustar` GNU tar's long names (over 100 characters) are refused by the Installer.

A Makefile target (Digger's):

```make
app: DIGGER.HZA
DIGGER.HZA: $(PRG) DIGGER.DAT build/DIGGER.ICN app/APP.INF $(SDK)/tools/hzapp.py
	rm -rf build/app && mkdir -p build/app/DIGGER
	cp $(PRG) DIGGER.DAT build/DIGGER.ICN build/app/DIGGER/
	grep -v '^#' app/APP.INF > build/app/DIGGER/APP.INF
	$(PYTHON) $(SDK)/tools/hzapp.py pack build/app/DIGGER -o $@ --mtime 0
```

Never put a file the program writes (scores, settings, saves) into the archive: an
update would replace the user's file. Let the program create it when missing.

## The Installer (/BIN/INSTALL.PRG)

- Files: double click the `.HZA` (or select it, Enter): a window with name, version,
  description, size, target folder; **Install** (or **Replace** when the app is there).
- Shell: `install FILE.HZA` (asks y/n), `install -y FILE.HZA` (no question),
  `install -l FILE.HZA` (list only), `install -r NAME` (remove `/APPS/NAME` and everything
  in it, saves too; `-y` no question). Files' "Remove app..." does the same.
- It unpacks into `/APPS/.INSTALL`, then renames it to `/APPS/NAME`. On an update it first
  moves the user's files (those not in the archive) into the new folder. Any error deletes
  `/APPS/.INSTALL` and leaves the old app as it was. A full card: "The card is full.
  Nothing was installed". At the end it writes `/SYSTEM/APPS.NEW` so the Desktop rereads
  the apps.
- A need the machine lacks is a warning ("It may not run here: it needs Horizon ... or
  later."); it can still be installed.
- Refused: no APP.INF ("... has no APP.INF in its folder: it is not a Horizon app."), no
  program, links, unsafe names, anything outside the one top folder, GNU long names, a
  cut or damaged archive.
- Each outcome is one console line, in the shell and in windows (the log, `console.txt`):
  `install: installed /APPS/NAME`, `install: replaced /APPS/NAME`, `install: removed
  /APPS/NAME`, `install: cancelled`, `install: failed: REASON` (`... the card is full`, `a
  name that is not safe: GOOD/../EVIL.TXT`, ...). In windows the question too, just before
  it shows: `install: asks: Install /APPS/NAME` (`Replace`, `Remove`). Test scripts wait
  for these lines.

## Installing in the emulator

**From the shell** (as `sdk/c/tests/run.py`'s apps test does): run the Installer itself
with run816, then start the app by its path (the same steps as that test's, which waits for
the `install:` lines; HELLO was verified with fixed delays before those lines existed):

```
# install.script (run816 started "install -y /HELLO.HZA")
0 wait install: installed /APPS/HELLO
+500 /APPS/HELLO/HELLO.PRG\n
+0 wait hello: folder
+500 install -y /HELLO.HZA\n
+0 wait install: replaced /APPS/HELLO
+500 /APPS/HELLO/HELLO.PRG\n
```

```
python3 SDK/tools/run816.py HORIZON/build/sd/BIN/INSTALL.PRG --mode shell \
  --dest /BIN/INSTALL.PRG --args "-y /HELLO.HZA" --file HELLO.HZA:/HELLO.HZA \
  --script install.script --out build/run-install
```

The console then has `Hello is installed: it is in the Programs menu.` twice (install,
then update) and the program's lines; `build/run-install/card/APPS/HELLO/` holds
APP.INF, HELLO.ICN, HELLO.PRG and RUNS.TXT, which the update kept (it says 2).

**From the Desktop, as a user** (`ports/digger/tests/app.script`, `make test-app`):
`run816.py - --mode none --file DIGGER.HZA:/DIGGER.HZA --script tests/app.script`. Time 0
is the Desktop with Files open at the root: type `digger\n` (Files finds and opens the
archive), `+0 wait install: asks: Install /APPS/DIGGER`, `+500 \n` (Install), `+0 wait
install: installed /APPS/DIGGER`, `+500 \n` (the message), `{f10}` `{right}` (Programs),
`{end}` to "Games >" (the last line), `\n` (its pop-up opens beside the menu with its first
app highlighted: Right does not open it), `\n` again (Digger), then `+0 wait digger:
title`. (Digger's own script predates the `install:` lines and uses fixed delays there.)
`tests/app.sh` checks the four files in `card/APPS/DIGGER`, the title line, and that
`DIGGER.SCO` survived a second install (Replace). It passes.

## Where saves and settings go: hz_prog_dir

**In the app's own folder.** Replace keeps every file the archive does not have, so
scores, saved games and settings survive an update; "Remove app" deletes them.

Never assume the current folder: it is the starter's. The Programs menu starts an app in
its own folder; Files in the folder it shows; a desktop shortcut and run816's desktop mode
(a `/SYSTEM/PROGRAMS` entry) in `/`; a file of the app's type opened from Files in that
file's folder; the shell in its own (run816 shell mode: `/`); and the program cannot know
how it was started. Always find the folder with `hz_prog_dir` (Horizon 0.28+; assembly:
`task_path`, $35):

```c
#include <stdio.h>
#include <string.h>
#include <horizon.h>

/* open NAME in the program's own folder ("/APPS/HELLO/NAME") */
static FILE *open_here(const char *name, const char *mode)
{
    char path[160];
    if (hz_prog_dir(path, 128) < 0)     /* "/APPS/HELLO/", ends in '/' */
        return NULL;                    /* hz_errno HZ_ENOSYS: Horizon before 0.28 */
    strcat(path, name);
    return fopen(path, mode);
}
```

(Built with `-Wall`, run from `/APPS/F/`: the file landed in `/APPS/F/`.) The HELLO app
above, run in the shell after an install: `hello: folder /APPS/HELLO/, current folder /,
run 2`.
A port that opens files by relative names (Digger: `DIGGER.SCO`, `DIGGER.INI`,
recordings) instead changes folder once at start: `hz_prog_dir`, drop the last `/`,
`hz_chdir(dir)` (`ports/digger/horizon/hz_main.c`). `hz_task_path` gives the whole path of
the program file.

## Checklist

- [ ] `hcc --needs ...` (or `HZ_NEEDS`) with what the program really needs; APP.INF
      without `needs=` (pack copies the program's), or the same list.
- [ ] Data files found through `hz_prog_dir`; saves written there; none in the archive.
- [ ] `hzapp.py check` clean; `pack --mtime 0` in a `make app` target.
- [ ] Installed in the emulator (shell `install -y`, or the Desktop script), started,
      used, installed again: the user's files still there, no `/APPS/.INSTALL` left.

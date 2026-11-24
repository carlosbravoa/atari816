# Apps: packaging and installing

Horizon 0.29 and later. An app is a program with its files, in one folder on the card. You
install it from one archive file. You remove it by deleting its folder. There are no
shared libraries and no dependencies between apps: an app needs only a Horizon version,
the hardware, and its own files.

- [For users](#for-users): install, start, remove.
- [For developers](#for-developers): the folder, APP.INF, what a program needs, the archive,
  `hzapp.py`, saves, names.
- [Example: Digger](#example-digger).
- [Older Horizon versions](#older-horizon-versions).

## For users

### Install an app

An app comes as one file whose name ends in `.HZA` (a Horizon app archive), for example
`DIGGER.HZA`. Copy it anywhere on the card (with the PC link, or in a card reader).

- **In Files:** double click the `.HZA` file (Files shows it as a small parcel), or select
  it and press Enter. A window says
  what the app is: its name, version, description, size, and the folder it goes to. Click
  **Install**. A small window counts the files. At the end a message says that the app is
  in the Programs menu.
- **In the shell:** type `install DIGGER.HZA` and answer `y`. `install -y DIGGER.HZA`
  installs without the question. `install -l DIGGER.HZA` only lists the files.

The app goes to `/APPS/NAME`, a folder of its own (`/APPS/DIGGER`).

If the app is already there, the window says so and the button says **Replace**. Replace
keeps your own files in the app's folder: saved games, high scores, settings. Only the
files that are in the archive are replaced.

If the archive is damaged, or holds something that is not safe, nothing is installed and
a message says why. If the card gets full during the install, the install stops, the
files written so far are deleted, and the app that was there before stays as it was.

If the app needs a newer Horizon or other hardware, the install window says so ("It may
not run here: it needs Horizon 0.30 or later"). You can still install it.

### Start an app

Open the **Programs** menu of the Desktop. The apps come after Horizon's own programs,
below a line, sorted by name. Apps of a category (such as Games) are under one item,
"Games >": choose it (a click, or Enter), and a small menu with those apps opens beside the
Programs menu, its first app highlighted (Up and Down move, Enter starts one).

The menu has room for 24 lines. When there are more apps than fit, the last line is
"More apps >", with the others. A long list of that kind ends with "All apps in Files",
which opens Files in `/APPS`.

You can also start an app in Files (double click its program in its folder), or in the
shell (`/APPS/DIGGER/DIGGER.PRG`; it then runs in the shell's current folder). An app may open files of its own type: a double click
on such a file in Files starts the app with that file.

A shortcut to an app on the desktop (Files: select the app's program or folder, File >
Add to desktop) shows the app's own icon.

### Remove an app

- **In Files:** open `/APPS`, right-click the app's folder (or select it and press the
  menu key), choose **Remove app...**, and confirm.
- **In the shell:** `install -r DIGGER` (or `install -r /APPS/DIGGER`), and answer `y`.

This deletes the folder with everything in it, your saved games too. Copy them somewhere
else first if you want to keep them. (Files' Delete and the shell's `rm` delete only empty
folders: use Remove app... or `install -r` for an app.)

## For developers

### The folder

```
/APPS/DIGGER/
    APP.INF          what the app is (below)
    DIGGER.PRG       the program
    DIGGER.DAT       its data
    DIGGER.SCO       written by the program: high scores, saves, settings
```

The folder's name is the app's name on the card. Everything the app needs is inside it.
**Always find your own files with `hz_prog_dir`** (C; the whole path: `hz_task_path`;
assembly: `task_path`, $35): never a fixed path, and never the current folder. The current
folder a program starts in is its starter's: the Programs menu starts an app in its own
folder; a double click in Files, in the folder Files shows (the program's own); a desktop
shortcut, in `/`; a file of the app's type opened from Files, in that file's folder (the
file's path is given whole); the shell, in the shell's folder (so that relative arguments
mean what they mean at the prompt). Programs use the current folder as the user's folder
(a file dialog starts there), which is why Horizon does not move every app to its own.

**Saves go into the app's folder.** Replace keeps every file that the archive does not
have, so a game's high scores, saved games and settings survive an update. Do not put a
file into the archive that the program writes later (a default high-score table, for
example): the update would replace the user's file. Let the program make the file when it
is missing.

A program directly in `/APPS` (`/APPS/GAME.PRG`, where `sdk/tools/run816.py` puts
programs) is also listed in the Programs menu, by its file name. So is
a folder with a program but no APP.INF, by the folder's name.

### APP.INF

A small text file of `key=value` lines. Keys ignore case. Spaces around the key and the
value are dropped. Lines that start with `#`, empty lines and unknown keys are ignored. CR
LF or LF line ends. Horizon reads the first 1023 bytes. Every key is optional.

```
# APP.INF of Digger
name=Digger
version=1.0
description=Windmill Software's Digger (1983)
category=Games
program=DIGGER.PRG
icon=DIGGER.ICN
types=DRF
needs=horizon=0.28
```

| Key | Size | What |
| --- | --- | --- |
| `name` | 24 | The name in the Programs menu and in the Installer's messages. Default: the folder's name. |
| `program` | 63 | The program file in the folder. Default: `FOLDER.PRG` (the folder's name with `.PRG`), else the only `.PRG` in the folder. With several programs and none named like the folder, `program=` is needed. |
| `category` | 15 | The Programs menu groups the apps of one category under one item ("Games >"). Default: none (an item of its own). |
| `version` | 15 | Shown by the Installer. |
| `description` | 63 | One line, shown by the Installer. |
| `types` | 47 | The file types (extensions) the app opens, separated by commas: `types=DIG,LVL`. A double click on such a file in Files (or on the Desktop) starts the app with the file's full path as its argument, in quotes: `"/GAMES/LEVEL1.DIG"`. Horizon's own types keep their programs (`.TXT` opens in Edit, whatever an app says). When several apps register a type, the first app folder the card lists wins. |
| `icon` | 31 | The app's icon on the desktop (for a shortcut to the app). Either the name of a built-in icon (`folder`, `sd`, `atari`, `doc`, `text`, `writedoc`, `sheetdoc`, `picture`, `basdoc`, `disk`, `xex`, `cart`, `program`, `edit`, `write`, `sheet`, `paint`, `basic`, `calc`, `solitaire`, `terminal`, `files`, `settings`, `about`, `pc`, `freecell`, `music`, `musicdoc`; case is ignored), or the name of an icon file in the folder: 32 x 32 pixels, 8 bits a pixel (one index of the Desktop's palette each, row by row), 255 for transparent: exactly 1024 bytes. `hzapp.py icon ART.png NAME.ICN` makes one from any picture (below); Horizon's `tools/mkicons.py` makes one from a text drawing (a file with one icon in the format of `sdfiles/icons.txt`). (The SDK's test checks this list against the Desktop's own, `apinames` in `horizon/user/desk.s`.) |
| `args` | 127 | (Horizon 0.31) The arguments the Desktop starts the program with (the Programs menu, a double click on the program in Files, a shortcut without its own `args=`): `args=-fast "two words"`. The user's options file is added after them (below). Not used when a file of the app's type is opened (that passes the file's path alone). Older Desktops ignore it. |
| `console` | 7 | (Horizon 0.31) `yes`: the program runs in a Terminal window: what it prints (printf, stderr) shows there, the console's keys (getchar, conio) come from there, and at its end the window says `--- NAME ended (code N).` and waits for a key. `error`: the same, but the window closes by itself when the program ends with code 0, so it only stays when something went wrong (a game that prints why it stopped). `no` (the default): no window; what the program prints goes to the log, where nobody sees it. A program with windows or a full screen keeps getting its keys from them. |
| `needs` | 47 | What the program needs, for the Installer to show (the same list as `hcc --needs`, below). The program checks it itself; this line only informs. You need not write it: `hzapp.py pack` puts the program's own list into the archive's APP.INF when the line is missing (and warns when the two differ; `--needs-from-program` then takes the program's). |

Values longer than the size are cut. A broken APP.INF never stops the Desktop: a folder
whose `program=` file is missing is left out of the menu; junk lines are ignored.

### The user's options: NAME.ARG

(Horizon 0.31) A program started from the Desktop or Files without a command line (the
Programs menu, a double click, a shortcut) also gets the words of the text file next to it
named like it with `.ARG`: `/APPS/XCOM/XCOM.ARG` for `XCOM.PRG`. `#` starts a comment to
the line's end; line ends and blanks between words become one space; the first 382 bytes
are read. It comes after APP.INF's `args=`, so a program that takes the last of two
repeated options lets the user's win. The whole argument string is at most 127 characters
(the kernel's limit): a longer one gets an alert and the program does not start. Any
program has it, not only apps (`/BIN/EDIT.ARG` for Edit), and nothing has to be written for
it: the program just gets more arguments. This is the place for the user's settings that
a game takes as options (skip the intro, a measuring mode). **Do not ship a NAME.ARG in
the archive**: it is the user's file, and an update would replace it (`hzapp.py` warns);
put your defaults in `args=`. Opening a document passes no options file.

Files' **Run with...** (the pop-up menu of any .PRG) asks for arguments and runs the
program with exactly those, in a Terminal window (no options file): the quick way to try
options and see what the program prints.

### What a program needs

A program can say what it needs: a Horizon version, hardware, free memory. It checks this
itself when it starts. So a program file copied by hand to an old card is safe too: it
says what is missing and ends, instead of crashing.

The message goes to the console, and into a small window when the window system runs (a
click or a key closes it). The program then ends with exit code 1.

```
DIGGER needs Horizon 0.29 or later (this is 0.28).
GAME needs the OPL2 sound chip (hardware revision $0C).
GAME needs 1024 KB of free memory (512 KB free).
```

The needs:

| Need | Checked |
| --- | --- |
| `horizon=0.29` | Horizon's version is at least this one. |
| `rev=11` | The hardware revision is at least $0B (11). (`rev=13`: $0D, the blitter's colour remap; hgame remaps with the CPU on older boards, so a game needs it only if that is too slow for it.) |
| `lau` | Lau, the sample player (REV $0A and later). |
| `opl2` | The OPL2 FM synthesizer (REV $0C). |
| `sprites` | Marga's sprites and scrolling (REV $0B and later). |
| `blitter` | The blitter (REV $08 and later). |
| `mem=1024K` | So much free memory when the program starts (`mem=2M` is 2048 KB). |
| `joystick` | Not checked (a joystick cannot be detected). The Installer shows it. |

**In C:** `hcc --needs horizon=0.29,opl2,mem=1024K` (the option may be given more than
once). hcc adds a small check that runs before `main`. A program built with
`--code large` needs Horizon 0.28 anyway: with `--needs`, hcc raises `horizon` to 0.28 at
least. Without `--needs` nothing is added and nothing is checked.

**In assembly:** include `needs.inc` and put `HZ_NEEDS` first at the start:

```asm
        .include "horizon.inc"
        .include "needs.inc"
        .segment "CODE"
        .a16
        .i16
start:  HZ_NEEDS "GAME", 0, 29, 0, NEED_OPL2 | NEED_LAU, 1024
        ; the program: A and X are the start conditions still (the argument string)
```

The arguments: the name for the message (15 characters at most), the Horizon version
(major, minor; 0, 0 for any), the lowest hardware revision (0 for any), `NEED_*` flags
(`NEED_LAU`, `NEED_OPL2`, `NEED_SPRITES`, `NEED_BLITTER`, `NEED_JOY`), and the free memory
in KB (0 for any). The check is 650 to 720 bytes of code (its messages included) and uses no zero page.

**How it checks.** Horizon 0.29 has the call `sys_info` ($36): A = the version (major x
256 + minor), X = the hardware revision. On an older Horizon that call is missing; then
the check tells 0.28 (task_path works) and 0.27 (the OPL2 call exists), and calls
anything older "0.26 or older". Lau and the OPL2 are found by their own calls on every
version. A revision, sprites and the blitter cannot be checked before 0.29, so they pass
there.

The block is also readable by tools: `"HZNEEDS"`, the byte 1, then minor, major, revision,
flags, the KB (2 bytes), the name. `hzapp.py` reads it.

### The archive (.HZA)

An `.HZA` file is a plain POSIX **ustar** archive, not compressed. It holds one folder,
the app's, with APP.INF in it:

```
DIGGER/
DIGGER/APP.INF
DIGGER/DIGGER.PRG
DIGGER/DIGGER.DAT
```

The Installer reads it in two passes. First only the headers: it checks everything and
reads APP.INF. Then, after the question, it unpacks the files as they come, 16 KB at a
time (an archive of any size works; it is never loaded whole).

What it takes and refuses:

- Files (types `0`, NUL, `7`) and folders (`5`). Long names through ustar's `prefix`
  field (Python's tarfile and GNU tar with `--format=ustar` use it). Both ustar magics
  (POSIX and GNU tar's).
- pax headers (`x`, `g`) are skipped. The name in the ustar header is used, so names must
  fit there (they always do within the limits below).
- Refused: GNU long names (`L`, `K`: names over 100 characters from GNU tar's own format),
  links, devices, sizes in base-256, a header whose checksum is wrong, an archive cut short
  (it must end with a record of zeros).
- Refused names: a `..` part, an absolute name, an empty part, characters below 32 or
  above 126, any of `\ : * ? " < > |`, a part ending in `.` or a space, a part starting
  with a space, anything outside the one top folder.
- The top folder: at most 32 characters, not starting with `.`. A path inside it: at most
  112 characters, and `/APPS/NAME/path` at most 127.
- APP.INF must be in the top folder, and the program must be there (APP.INF's `program=`,
  else `NAME.PRG`, else the only `.PRG`).

The Installer unpacks into `/APPS/.INSTALL` and then renames that folder to `/APPS/NAME`.
On an update it first moves the user's files (those the archive does not have) from the
old folder into the new one, then deletes the rest of the old folder. Any error before
that deletes `/APPS/.INSTALL` and leaves the old app as it was.

The card has no call that tells its free space. A full card shows as a write that comes
back short; the Installer then stops, deletes what it wrote, and says "The card is full".

### hzapp.py

`sdk/tools/hzapp.py` makes and checks archives on the PC (Python 3, no other modules):

```
python3 sdk/tools/hzapp.py pack DIGGER            # -> DIGGER.HZA
python3 sdk/tools/hzapp.py list DIGGER.HZA        # its files and APP.INF
python3 sdk/tools/hzapp.py check DIGGER           # a folder or an .HZA: the checks only
python3 sdk/tools/hzapp.py icon art.png DIGGER/DIGGER.ICN   # an icon from a picture
```

`pack` prints what it packed (the name, version, description, category, types, needs,
the number of files and their size, the folder it will go to) and the archive's size.
Errors stop it (exit code 1); warnings do not.

`pack FOLDER [-o FILE.HZA] [--mtime N] [--needs-from-program]` checks the folder with the
Installer's rules and more: APP.INF is there and its values fit; `icon=` is a built-in name
or a file of 1024 bytes in the folder; the program is there and is a Horizon program; every
name is one the card and the Installer accept; files of 16 MB or more get a warning.

The needs are written once, in the program (`hcc --needs`, `HZ_NEEDS`): when APP.INF has
no `needs=` line, `pack` adds the program's list to the APP.INF it puts into the archive
(the file in your folder stays as it is) and says so. When APP.INF has a `needs=` that
differs from the program's, `pack` warns and keeps APP.INF's; `--needs-from-program` puts
the program's into the archive instead. `check` prints what the program checks
(`DIGGER.PRG checks: horizon=0.28,sprites,mem=1280K`, or that it checks nothing).

`icon IMAGE OUT.ICN [--no-shadow] [--preview FILE.png]` (needs Pillow) makes an icon file
from any picture Pillow reads, a game's own sprite for example: a picture larger than the
icon is scaled down (pixel art by a whole-number step when its size allows), a smaller one
is centred; each pixel becomes the nearest colour of the Desktop's palette; pixels with
alpha below 128 are transparent; then the house style's drop shadow (colour 15, one pixel
right and down). `--preview` writes the icon four times enlarged on the desktop's colours:
look at it. Files and folders whose names start with `.` (`.DS_Store`, `.git`) are left out,
with a warning. `--mtime N` gives every entry the same time (seconds since 1970) for
archives that are the same byte for byte.

Plain `tar` works too, from the folder that holds the app's folder:

```
tar --format=ustar -cf DIGGER.HZA DIGGER
```

GNU tar without `--format=ustar` is fine while no name is longer than 100 characters.
bsdtar (macOS) adds pax headers and `._` files; the pax headers are skipped, but use
`COPYFILE_DISABLE=1 tar --format=ustar -cf ...` to keep the `._` files out.

### Names on the card

The card is FAT32 with long names. Names ignore case (`Digger` and `DIGGER` are the same
folder) and keep the case they were made with. Spaces and most punctuation are fine:
`/APPS/My Game (2)/Start Me.PRG` works (in the shell, quote such paths). The emulator's
card (a folder on the PC) follows the same rules. A full path is at most 127 characters.

### How the Desktop finds the apps

(Horizon 0.31) The Desktop reads `/APPS` and every app's APP.INF when it starts, and again
when the apps change: the Installer tells it after an install or a removal (sysreq
`SR_APPS`), and so does Files after a change it sees in `/APPS` or in an app's folder (a
copy, a delete, a rename there, or a reload that finds the listing different). Opening the
Programs menu reads nothing: it opens at once. A full read of 20 apps takes about 275 ms at
the board's card speed (four card requests an app: OPEN, READ and CLOSE of APP.INF, a STAT
of the program). When you choose an app its APP.INF is read again (its `args=` and
`console=` as they are now, and a check that it is still there): a program that is not on
the card any more gets an alert, and the menu is read again. After you edit an APP.INF by
hand or change the card behind Horizon's back (the PC link, another machine), press **F5**
on the desktop: the menu and the icons are read again. (0.29 and 0.30 listed `/APPS` and
read `/SYSTEM/PROGRAMS` every time the menu opened, and the Installer left
`/SYSTEM/APPS.NEW`: about 2 s on the board with 5 apps.)

The Desktop keeps 64 apps at most.

## Example: Digger

Digger (`ports/digger`) is a C program with its data in a second file, the first real app.
`make -C ports/digger app` makes `DIGGER.HZA`; `make -C ports/digger test-app` installs it
in the emulator and plays it (below). What it took:

1. **Its needs, on the hcc line** (`ports/digger/Makefile`): `--needs
   horizon=0.28,sprites,mem=1280K`. 0.28 for its large code model; `sprites` for Marga's
   scrolling (its split view: REV $0B); about 1.2 MB of free memory (19 banks: the shown
   framebuffer and the one it draws into, its pictures, tables and code). Lau is not a
   need: without it the sound keeps time by the frame counter; a joystick is optional.
2. **APP.INF** (`ports/digger/app/APP.INF`):

   ```
   name=Digger
   version=1.0
   description=Windmill Software's Digger (1983), from Digger Remastered
   category=Games
   program=DIGGER.PRG
   icon=DIGGER.ICN
   needs=horizon=0.28,sprites,mem=1280K
   ```

   Not `types=DRF` for its recordings: Digger takes a recording as `/P:file`, not as a
   bare path, so a double click could not play it.
3. **Its icon** is made at build time from the game's own art (`tools/mkdata.py --icon`):
   the VGA digger sprite (32 x 30 with its mask), its 16 colours as the nearest of the
   palette's colour cube, transparent where the mask is, the house style's drop shadow
   (colour 15). 1024 bytes, `DIGGER.ICN`. (Digger's tool came first; `hzapp.py icon` does
   the same for any PNG of a sprite with alpha.)
4. **The folder and the archive**: `build/app/DIGGER/` gets APP.INF, DIGGER.PRG, DIGGER.DAT
   and DIGGER.ICN, and `hzapp.py pack build/app/DIGGER -o DIGGER.HZA --mtime 0` packs it
   (420 KB). No `DIGGER.SCO` or `DIGGER.INI` in it: the program makes them.
5. **Saves**: at its start the program goes to its own folder (`hz_prog_dir` and `hz_chdir`)
   and keeps its high scores (`DIGGER.SCO`), `DIGGER.INI` and its recordings there, by the
   relative names upstream uses: an update keeps them.
6. **The test** (`ports/digger/tests/app.script`, `run816.py --mode none`: the Desktop with
   nothing started): `DIGGER.HZA` opened in Files (its name typed, Enter), Install, then
   Programs (F10, Right), End to "Games >", Enter (its pop-up), Down, Enter:
   Digger's title; a game to a high score; Esc; the archive opened again: Replace. Then
   the card: the four files in `/APPS/DIGGER`, and `DIGGER.SCO` with the new score still
   there after the update. The script waits for the program's console lines (`wait
   digger: title`), not for fixed times.

Install it on a card: copy `DIGGER.HZA` anywhere on the card, double-click it in Files (or
`install DIGGER.HZA` in the shell), then Programs > Games > Digger.

## Older Horizon versions

- **0.28 and older** have no Installer, and their Desktop does not read `/APPS`. Install
  by hand: copy the app's folder to the card (unpack the `.HZA` on the PC with any tar),
  and start the program from Files or the shell. A Programs menu entry can be added to
  `/SYSTEM/PROGRAMS` (`Digger=/APPS/DIGGER/DIGGER.PRG`).
- A program with a needs block runs its check there too and says what is missing.
- A large C program (`hcc --code large`) needs 0.28: on 0.27 and older its loader refuses
  a file of 64 KB or more ("not a Horizon program"), and a smaller one stops with "needs
  Horizon 0.28 or later".
- `sys_info` ($36) is missing before 0.29 (ENOSYS).

# Printing and the 8-bit Atari

This page explains three things that came with Horizon 0.23: **printing**, the **folder disk** and **Run in Atari**.

## Printing

The Atari816 has no printer port. When you print, the text goes into a *print job*: a text file in the folder `/Printouts` on the SD card. Its name says when it was printed and by which program, for example `2026-11-18 15.30.12 Edit.txt`.

- **Edit**, **Write** and **Sheet**: *File > Print*.
- **BASIC**: `LPRINT` prints like `PRINT`; `LLIST` lists the program to the printer.
- **Files**: right-click a text file and choose *Print*.
- **The shell**: `print FILE`.
- **The 8-bit Atari** prints too: `LPRINT` in Atari BASIC, or any program that prints to `P:`. Its jobs are called `Atari`. A job ends when the Atari stops sending for 3 seconds.

When a job is finished, the menu bar says **Printed: NAME** for a few seconds. Click that text to open **Printer**.

**Printer** (*Programs > Printer*) lists the jobs, newest first, and shows the selected one. You can delete a job, open it in Edit, or send it to your PC.

### Paper on your PC

When the PC link's gateway runs on your PC, every new job is also sent to the PC as a PDF file in the folder `Printouts` of the shared folder (the menu bar then says "(to the PC)"). Print it from there. Printer's *Send to PC* sends an older job again.

Without the Desktop (the text shell) nothing is sent by itself and there are no notices; the jobs are still in `/Printouts`.

## The folder disk

A folder of the SD card can be a disk drive of the 8-bit Atari. The Atari sees an ordinary Atari DOS 2.0S disk made from the folder's files, and what the Atari saves on it is copied back into the folder. So you can move files between Horizon and the Atari without disk images.

1. Click the **Atari** icon to open the Atari panel.
2. Click **Folder disk...**.
3. Type the folder (`/Atari` is suggested; it is made if it is not there) and choose the drive. **D2:** is a good choice: the Atari cannot start from a folder disk, so keep your DOS disk in **D1:**.
4. Click **Mount**.

The panel then shows the folder on its drive and a line like "12 files, 3 left out, 120 free sectors". Click **Refresh** after you changed files in the folder from Horizon: the Atari's own changes are saved first, then the disk is made again from the folder. **Eject** saves the Atari's changes and removes the folder disk. The folder disk is remembered when you switch the Atari816 off.

**Which files the Atari sees:** only names that Atari DOS can show: 1 to 8 letters or digits, starting with a letter, and an optional extension of 1 to 3 letters or digits (`GAME.BAS`, `NOTES.TXT`). At most 64 files fit, and together they must fit on the disk (about 88 KB). Other files are left out: the Atari does not see them and never changes or deletes them. Folders inside the folder are ignored.

**From Atari DOS:** boot a DOS disk in D1:, then use the folder disk as `D2:` (DOS menu, `DIR D2:`, copy, and so on).

**From Atari BASIC:** Atari BASIC alone has no `D:` device. Boot a DOS disk in D1: with BASIC on, then:

```
LIST "D2:PROG.LST"
ENTER "D2:PROG.LST"
SAVE "D2:PROG.BAS"
```

A listing saved with `LIST` uses Atari line ends; **Edit** opens it as normal lines and keeps the Atari line ends when it saves, so the Atari can `ENTER` it again.

## Run in Atari

A BASIC program on the SD card can run on the 8-bit Atari directly: right-click it in **Files** or on the desktop and choose **Run in Atari**, or type `run FILE` in the shell. It works for files ending in `.BAS` or `.LST`: a listing (text) or a program saved by Atari BASIC.

The Atari starts with Atari BASIC on, a small loader types the program in and runs it. Press `F12` to come back. A double click on a `.BAS` file still opens Horizon's own BASIC.

Limits: the program must be at most 96 KB; a cartridge is taken out first (Atari BASIC is needed); the loader replaces the disk in D1:, so the folder disk is not reachable from such a run. To use the folder disk from BASIC, boot a DOS as described above.

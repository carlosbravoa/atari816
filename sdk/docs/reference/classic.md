# Syscalls: classic Atari

Inside the Atari816 runs a complete Atari 8-bit (400/800/XL/XE) with its own 6502, ANTIC,
GTIA, POKEYs and memory. It is frozen while the desktop is shown. A program can mount disk
images, executables and cartridges, boot the classic machine and show it; F12 always
returns to Horizon with the desktop exactly as it was. The classic machine's settings
(memory, keyboard layout, joystick from the arrow keys, (0.27) BASIC when a disk boots,
fast disk loading, ...) are in `/atari.ini` (Settings > Classic Atari edits it; they apply
after a full restart).

Kinds: `CK_AUTO` 0 (by the extension), `CK_DISK` 1 (.ATR .XFD), `CK_XEX` 2 (.XEX .COM
.EXE), `CK_CART` 3 (.CAR .ROM .BIN), (0.23) `CK_BASRUN` 4 (a BASIC program: "Run in Atari")
and `CK_FOLDER` 5 (a folder of the card as a disk), below. Errors: $44 no file, $C2 the
firmware does not support the operation, $C3 a bad kind, slot or extension, $C4 not a valid
image, $C5 the firmware's menu is open. (The emulator has no classic machine: it checks and
records the mounts, logs each operation on stderr, and boot always works.)

| Constant | Value |
| --- | --- |
| `CK_AUTO` | 0 |
| `CK_DISK` | 1 |
| `CK_XEX` | 2 |
| `CK_CART` | 3 |
| `CK_BASRUN` | 4 |
| `CK_FOLDER` | 5 |
| `FD_SAVING` | 1 |

**Run in Atari** (0.23, `CK_BASRUN`): the path is a BASIC program on the card, a text
listing (LF, CR LF or the Atari's $9B line ends; normally .BAS or .LST) or an Atari BASIC
SAVE file. It becomes the virtual boot disk on D1: in place of D1: and the executable, like
an executable: classic_mount returns `CK_XEX` (2) and classic_query reports it as item 4.
classic_boot then cold boots with Atari BASIC on; a small loader types the program in and
RUNs it. $C4: empty, or larger than 96 KB. ulib's `atari_run` does all of it for `.BAS` and
`.LST` (`atari_rkind` checks first: it returns 4 for them).

**The folder disk** (0.23, `CK_FOLDER`, A = 5 | slot << 8): a folder of the card (made if
missing) shows on that drive as an Atari DOS 2.0S single-density disk built from its files;
what the Atari writes is copied back into the folder. classic_mount returns `CK_DISK` (1).
The same folder on the same drive again is a refresh (the Atari's changes saved, the disk
built again from the folder); classic_eject of the drive saves, then ejects. One drive at
most: mounting a folder on another drive moves it (eject the old drive first, so
classic_query no longer reports it). The disk shows the files whose names fit Atari DOS 8.3 (1-8
letters or digits, the first a letter, optionally a dot and 1-3 letters or digits; shown in
upper case), at most 64, in name order, while they fit in 707 sectors of 125 bytes; the others
are left out and never touched. STAT of exactly `/D1:` .. `/D4:` returns its numbers:
```asm
; A = the drive 0-3 that is the folder disk -> C clear: buf = its numbers
fdinfo: clc
        adc     #'1'
        sep     #$20
        .a8
        sta     s_drv+2
        rep     #$20
        .a16
        ptr     sblk
        sys     SYS_STAT        ; C set ($44): not the folder disk
        rts                     ; buf+0 files shown, buf+1 left out, buf+2 (word) free
                                ; sectors; buf+4 bit 0 (FD_SAVING): changes wait to be saved
sblk:   .faraddr s_drv, buf
s_drv:  .byte   "/D1:", 0
```

The simplest way to run Atari software from a program is ulib's `atari_run` (X, Y = path):
"start this, and only this" (it ejects what would get in the way, mounts, boots, and
returns after F12):
```asm
        ptr     s_game
        jsr     atari_run       ; returns after F12 (C set: an error, A = code)
        rts
s_game: .byte   "/disks/GAME.ATR", 0
```

### $61 classic_mount (SYS_CMOUNT)
In: X, Y = path, A = kind | slot << 8 (slot 0-3 = D1:-D4:, disks only). Out: A = the kind
mounted. Mounts only; nothing is reset. A large cartridge can take seconds.
```asm
        ptr     s_disk
        lda     #CK_DISK | (1 << 8)     ; D2:
        sys     SYS_CMOUNT
        rts
s_disk: .byte   "/disks/DATA.ATR", 0
```

### $62 classic_eject (SYS_CEJECT)
In: A = kind | slot << 8 (disk slot 0 also ejects the executable). Ejecting an empty slot
is fine.
```asm
        lda     #CK_CART
        sys     SYS_CEJECT
```

### $63 classic_boot (SYS_CBOOT)
Cold boots the classic machine with what is mounted and shows it (as classic_show), until
F12. Only the keyboard holder, or any task while the window system runs. On a failed boot
the error is returned and the desktop stays. (0.18) A = `CB_STAY` ($C01D): cold boot (a
power cycle) and stay on the desktop.
```asm
        sys     SYS_CBOOT       ; returns after F12
```

### $60 classic_show (SYS_CLASSIC)
Shows the classic machine as it is (it runs while shown) and gives it the keyboard, until
F12. Same rule as classic_boot for who may call it.
```asm
        sys     SYS_CLASSIC     ; back here after F12
```

### $64 classic_query (SYS_CQUERY)
In: A = item (0-3 D1:-D4:, 4 the executable, 5 the cartridge), X, Y = 128-byte buffer.
Out: A = length of the path mounted there (0 = nothing). Only mounts made through Horizon
are reported.
```asm
        lda     #0              ; D1:
        ptr     path
        sys     SYS_CQUERY      ; -> A = length
        cmp     #0              ; (a syscall leaves N and Z as they were: test A)
        beq     @empty
@empty:
```

## Limits of native programs

- Paddles: no syscall reads them. The joysticks and triggers of the two DB9 ports are
  read with `SYS_JOY` (Horizon 0.15, [system.md](system.md)); the registers behind it,
  JOY_PORT / JOY_TRIG at $00:DE21-$DE22, are in the I/O page, which user programs cannot
  touch.
- ANTIC and GTIA: not available for native graphics. POKEY: only through `SYS_SNDW` and
  `SYS_BEEP` ([sound.md](sound.md)).
- Data exchange with a running classic program: not available (the supervisor mailbox at
  $00:DC30 is kernel-only and unused).

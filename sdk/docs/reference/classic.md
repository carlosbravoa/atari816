# Syscalls: the classic Atari

Inside the Atari816 runs a complete Atari 8-bit (400/800/XL/XE) with its own 6502, ANTIC,
GTIA, POKEYs and memory. It is frozen while the desktop is shown. A program can mount disk
images, executables and cartridges, boot the classic machine and show it; F12 always
returns to Horizon with the desktop exactly as it was. The classic machine's settings
(memory, stereo, keyboard layout, joystick from the arrow keys, ...) are in `/atari.ini`
(Settings > Classic Atari edits it; they apply after a full restart).

Kinds: `CK_AUTO` 0 (by the extension), `CK_DISK` 1 (.ATR .XFD), `CK_XEX` 2 (.XEX .COM
.EXE), `CK_CART` 3 (.CAR .ROM .BIN). Errors: $44 no file, $C2 the firmware does not know the
operation (the emulator does not implement mount, eject and boot: it answers $C2), $C3 a bad
kind, slot or extension, $C4 not a valid image, $C5 the firmware's menu is open.

| Constant | Value |
| --- | --- |
| `CK_AUTO` | 0 |
| `CK_DISK` | 1 |
| `CK_XEX` | 2 |
| `CK_CART` | 3 |

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
the error is returned and the desktop stays.
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
are seen.
```asm
        lda     #0              ; D1:
        ptr     path
        sys     SYS_CQUERY      ; -> A = length
        cmp     #0              ; (a syscall leaves N and Z as they were: test A)
        beq     @empty
@empty:
```

## What a native program cannot do (yet)

- Read the joysticks or paddles (the DB9 ports are read by the classic machine; the
  native-side registers JOY_PORT / JOY_TRIG at $00:DE21-$DE22 are in the I/O page, which
  user programs cannot touch, and there is no syscall).
- Use ANTIC / GTIA / POKEY 1 for native graphics or sound, or exchange data with a running
  classic program (the supervisor mailbox at $00:DC30 is kernel-only, unused today).

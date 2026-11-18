# Syscalls: files and folders

The SD card is a FAT32 volume served by the I/O processor. Paths are FAT paths,
case-insensitive, long names allowed (spaces too). A path that does not start with `/` is
relative to the task's current directory (inherited from the parent: the shell's `cd`).
The kernel makes every path absolute; the result must fit in 127 characters (EINVAL).

- **4 open files for the whole system** (an I/O processor limit): close files soon.
  A handle (0-3) belongs to the task that opened it and is closed when it exits.
- A file call blocks the caller until the answer comes; other tasks run meanwhile.
- Errors are $40 + the FatFs result: $44 no such file, $45 no such path, $46 bad name,
  $47 denied, $48 already exists, $52 too many open files; $C0 + n: an I/O processor error
  ($C7 no PC link, $C8 the PC link was lost, $C9 not the same volume: below).
- (Horizon 0.20) **The PC volume.** With the PC link, one folder of the PC is a second volume:
  paths starting `/PC:` (any case; `/PC:` alone is its root). Every call below works on it,
  with the same handles and errors; a rename between the card and the PC answers $C9 (copy,
  then delete: `ui_mvtree` in the controls library does it). Without the PC every `/PC:` call
  answers $C7 at once; if the link drops, $C8. A readdir of `/` lists a folder `PC:` at the
  end while the volume is there. A stat of `/PC:` gives the PC's current time (the clock).
  It is slower than the card (about 50-150 KB/s, a few ms a call). See Horizon's ABI.md,
  "The PC volume".
- Data reaches the card when the file is closed (or at `SYS_SYNC`): close files you
  write before the user can switch off.

Blocks: `u24` = 3 bytes (offset low, offset high, bank). `{u8 handle, u24 buffer, u16
length}` is 6 bytes. Examples use `iob` (6 bytes), `buf` (256), `path` (128) in BSS and
`fh`, `n` in ZEROPAGE.

### $20 open (SYS_OPEN)
In: X, Y = path, A = mode: `O_READ` 0, `O_RDWR` 1 (read and write, the file must exist),
`O_CREATE` 2 (create or truncate, read and write), `O_APPEND` 3 (write at the end; the
file is created if missing: seen in the emulator). Out: A = handle 0-3.
```asm
        ptr     fname
        lda     #O_READ
        sys     SYS_OPEN        ; -> A = handle
        bcs     @err            ; A = $44: no such file
        sta     z:fh
@err:   rts
fname:  .byte   "/docs/Read me first.txt", 0
```

### $21 close (SYS_CLOSE)
In: A = handle.
```asm
        lda     z:fh
        sys     SYS_CLOSE
```

### $22 read (SYS_READ)
In: X, Y = `{u8 handle, u24 buffer, u16 length}`. Out: A = bytes read; fewer than asked
= the end of the file (0: at the end). The buffer may be anywhere you may write (a bank
from SYS_BALLOC too) but must not cross a bank boundary.
```asm
        lda     z:fh            ; build {handle, buffer, length}
        sta     iob             ; (the high byte lands in iob+1, overwritten next)
        lda     #.loword(buf)
        sta     iob+1
        sep     #$20
        .a8
        lda     #^buf
        sta     iob+3           ; the bank byte
        rep     #$20
        .a16
        lda     #256
        sta     iob+4
        ptr     iob
        sys     SYS_READ        ; -> A = bytes read
```

### $23 write (SYS_WRITE)
In: the same block. Out: A = bytes written.
```asm
        ptr     wblk            ; {handle, buffer, length}
        sys     SYS_WRITE
        rts
wblk:   .byte   0               ; (the handle: store it here first)
        .faraddr s_line
        .word   6
s_line: .byte   "hello", 10
```

### $24 seek (SYS_SEEK)
In: A = handle, X = offset low 16 bits, Y = offset high 16 bits (from the start). Out: A =
the new position low, X = high. A file opened read-only is clipped to its size.
```asm
        lda     z:fh
        ldx     #$0200          ; to byte 512
        ldy     #0
        sys     SYS_SEEK
```

### $25 stat (SYS_STAT)
In: X, Y = `{u24 path, u24 out}`. Out: A = size low, X = size high; `out` gets 9 bytes:
u32 size, u8 attributes (bit 4 directory, bit 0 read-only, $20 archive), u32 FAT time
(date << 16 | time). The root `/` cannot be stat'ed (error $46); `/PC:` can (0.20: its time
is the PC's clock now).
```asm
        ptr     sblk
        sys     SYS_STAT        ; -> A, X = size
        bcs     @none
        lda     buf+4
        and     #$0010          ; a folder?
@none:  rts
sblk:   .faraddr s_bin, buf
s_bin:  .byte   "/BIN", 0
```

### $26 readdir (SYS_READDIR)
In: X, Y = `{u24 path, u24 buffer, u16 length, u16 skip}`. Out: A = entries returned.
The entries are packed into the buffer: u32 size, u8 attributes, u8 name length, the name
(no terminator). Sorted by name (in the emulator; on the board in FAT order: sort them
yourself), without "." and "..". `skip` entries are skipped: call again with skip +=
the count to continue. The buffer must also have room for the path (the kernel copies it
there first).
```asm
        ptr     dblk
        sys     SYS_READDIR     ; -> A = entries in buf
        sta     z:n
        ldx     #0              ; walk them: X = offset of an entry
@ent:   lda     z:n
        beq     @end
        lda     buf+5,x         ; name length (low byte)
        and     #$00FF
        clc
        adc     #6              ; next entry = X + 6 + length
        sta     z:t0
        txa
        clc
        adc     z:t0
        tax
        dec     z:n
        bra     @ent
@end:   rts
dblk:   .faraddr s_root, buf
        .word   256, 0          ; length, skip
s_root: .byte   "/", 0
```

### $27 delete (SYS_DELETE)
In: X, Y = path (a file, or an empty folder).
```asm
        ptr     s_old
        sys     SYS_DELETE
        rts
s_old:  .byte   "OLD.TXT", 0
```

### $28 mkdir (SYS_MKDIR)
In: X, Y = path. $48 if it exists.
```asm
        ptr     s_dir
        sys     SYS_MKDIR
        rts
s_dir:  .byte   "/SAVES", 0
```

### $29 rename (SYS_RENAME)
In: X, Y = `{u24 old path, u24 new path}`. Renames or moves a file or folder. $48 if the
new name exists; $C9 between the card and the PC volume (0.20).
```asm
        ptr     rblk
        sys     SYS_RENAME
        rts
rblk:   .faraddr s_from, s_to
s_from: .byte   "SCORES.TMP", 0
s_to:   .byte   "SCORES.DAT", 0
```

### $08 chdir (SYS_CHDIR)
In: X, Y = path. The task's current directory (relative paths allowed). EINVAL if it is
a file; $44/$45 if it does not exist. Inherited by the tasks it spawns.
```asm
        ptr     s_saves
        sys     SYS_CHDIR
        rts
s_saves: .byte  "/SAVES", 0
```

### $09 getcwd (SYS_GETCWD)
In: X, Y = buffer, A = its size. Out: A = length; the buffer holds the absolute path.
EINVAL if the buffer is too small.
```asm
        ptr     path
        lda     #128
        sys     SYS_GETCWD
        ptr     path
        jsr     out_str         ; print it
```

## Saving a file safely

Write to a new name, close it, then delete the old file and rename the new one: a power
cut in the middle leaves one complete file.

```asm
        ptr     s_tmp
        lda     #O_CREATE
        sys     SYS_OPEN
        bcs     @err
        sta     z:fh
        ; ... SYS_WRITE the data ...
        lda     z:fh
        sys     SYS_CLOSE
        ptr     s_dst
        sys     SYS_DELETE      ; (an error if it did not exist: fine)
        ptr     rblk2
        sys     SYS_RENAME
@err:   rts
s_tmp:  .byte   "HISCORE.TMP", 0
s_dst:  .byte   "HISCORE.DAT", 0
rblk2:  .faraddr s_tmp, s_dst
```

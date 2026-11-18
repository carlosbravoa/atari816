# Printing (Horizon 0.23)

The Atari816 has no printer port. "Printing" makes a **print job**: a text file in the card's
folder `/Printouts`, which the user reads in **Printer** (Programs menu) and, when the PC
link's gateway is there, gets as a PDF on the PC. The classic Atari prints the same way
(`LPRINT`, `P:`): its jobs are named `Atari`.

## How a program prints

Open the path `/PRN:NAME` (any open mode: it always makes a new job), write the text, close.
That is all: the handle is a normal file handle (0-3), and the job is finished at the close
(also when the program ends or crashes with the job open).

```asm
; print the zero-terminated text at s_text as a job named "Notes"
prjob:  ptr     s_job
        lda     #O_CREATE
        sys     SYS_OPEN
        bcs     @err                    ; A = the error ($40 + the I/O processor's code)
        sta     z:fh
        sta     blk                     ; {u8 handle, u24 buffer, u16 length}
        lda     #.loword(s_text)
        sta     blk+1
        sep     #$20
        .a8
        lda     #^s_text
        sta     blk+3
        rep     #$20
        .a16
        lda     #s_end - s_text
        sta     blk+4
        ptr     blk
        sys     SYS_WRITE
        php
        lda     z:fh
        sys     SYS_CLOSE               ; the job appears now
        plp
@err:   rts
s_job:  .byte   "/PRN:Notes", 0
s_text: .byte   "Shopping", 10, "- bread", 10, "- milk", 10
s_end:
```

- **NAME** is your program's name (Horizon's programs use `Edit`, `Write`, `Sheet`, `BASIC`,
  `Shell`, `Files`). It is cut to 24 characters; `\ / : * ? " < > |` and control characters
  become `_`.
- **The job's file** is `/Printouts/YYYY-MM-DD HH.MM.SS NAME.txt` (the date and time of its
  start; ` 2`, ` 3`, ... after NAME when that name is taken). While the job is open, the file
  has a `.` in front of its name; it gets its real name at the close, so a job is always
  complete when it appears. Programs that list `/Printouts` should leave out names starting
  with `.`.
- **The text:** plain text, LF line ends (CR LF is accepted), FF ($0C) starts a new page,
  Latin-1. Lines longer than about 80 characters are wrapped on the PC; there is no other
  formatting, so lay out columns with spaces.
- **Errors** are the usual file errors (for example $C2 from a firmware older than 0.23).
  Say why in an alert; on success a short message is enough: the Desktop shows "Printed: NAME"
  for every finished job.

## Watching for new jobs

STAT of exactly `/PRN:` answers, as the size, the number of jobs finished since the I/O
processor started (the classic Atari's too). It is cheap: ask it on a timer and read
`/Printouts` only when the number changed (the Desktop and Printer do this every second).

```asm
; C set when a job finished since the last call
newjob: ptr     sblk
        sys     SYS_STAT                ; A = the count (low word)
        bcs     @no
        cmp     z:n
        beq     @no
        sta     z:n
        sec
        rts
@no:    clc
        rts
sblk:   .faraddr s_prn, buf
s_prn:  .byte   "/PRN:", 0
```

## PDFs on the PC

STAT of exactly `/PC:` answers, as the size, the gateway's services: `PCS_FILES` (the PC
volume), `PCS_DEV`, `PCS_NET`, `PCS_FETCH`, and (0.23) `PCS_PRINT`: it makes PDFs. A file
created as `/PC:/Printouts/NAME.pdf` whose content starts with the marker below becomes a PDF
(A4, Courier) when it is closed:

```
ESC "A816PRINT 1" LF          (13 bytes: 1B 41 38 31 36 50 52 49 4E 54 20 31 0A)
title=TEXT LF
date=YYYY-MM-DD HH:MM LF
LF
the job's text
```

You rarely write this yourself: `/SYSTEM/PRINTD.PRG PATH` sends one job (exit code 0 sent,
1 an error, 2 no PC or no `PCS_PRINT`), and the Desktop runs it for every new job when the
PC can make PDFs.

| Constant | Value |
| --- | --- |
| `PCS_FILES` | $01 |
| `PCS_DEV` | $02 |
| `PCS_NET` | $04 |
| `PCS_FETCH` | $08 |
| `PCS_PRINT` | $10 |

In the emulator, emu816 makes the jobs the same way; `--classic-print FILE@SECONDS` makes a
job as if the classic Atari had printed FILE (ATASCII), and `--no-pc-print` gives a gateway
without `PCS_PRINT` (emu/README.md).

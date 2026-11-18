# Syscalls: tasks, time, memory, console, keyboard, ports, system

Every syscall is `sys NAME` (`COP #n`) with A, X, Y 16-bit. Carry clear = OK; carry set =
error, A = the error code. X, Y, D, DBR come back unchanged unless listed under "Out".
Pointers are X = offset, Y = bank (`ptr label`). The source of truth is `horizon/ABI.md`;
`make check` compares this reference with `horizon/user/horizon.inc` and the kernel.

The examples assume the usual `.a16` / `.i16` and these names from your program: `buf`
(256 bytes), `blk` (16), `ev` (8), `path` (128), `iob` (6) in BSS, `win`, `fh`, `n`, `t0`,
`t1` in ZEROPAGE.

## Error codes

| Name | Code | Meaning |
| --- | --- | --- |
| `EINVAL` | 1 | Bad argument, or a handle, port, window or bank you do not own |
| `ENOMEM` | 2 | No free bank |
| `ENOENT` | 3 | (reserved: file errors are $40 + n) |
| `EFAULT` | 4 | A pointer range you may not access (or crossing a bank boundary) |
| `ECHILD` | 5 | No such child (wait) or task (kill) |
| `EAGAIN` | 6 | Full or busy: no task slot, port, queue space; the keyboard is taken; nothing to poll |
| `ENOSYS` | 7 | Unknown syscall |
| `ERUNNING` | 8 | A single-instance program runs already (its windows were raised) |
| `ENODEV` | 9 | (0.17) The hardware is not there: the sample calls without Lau (REV < $0A) |
| `EIO` | $40 | + the I/O processor's result: $44 no such file, $45 no such path, $46 bad name, $47 denied, $48 exists, $52 too many open files; $C0 + n for the classic ops; (0.20) $C7 no PC link, $C8 the PC link was lost, $C9 not the same volume (the PC volume, `/PC:`) |

## Tasks

### $00 exit (SYS_EXIT)
In: A = exit code. Never returns. Use the `exit n` macro (it flushes ulib's buffered
output first) or `jsr exit_a` with A = code.
```asm
        lda     z:n             ; exit code in A
        jsr     exit_a          ; flush the output, then SYS_EXIT
```

### $01 yield (SYS_YIELD)
Gives the CPU to the next ready task of the same or higher priority. Rarely needed: the
kernel preempts every 10 ms tick.
```asm
        sys     SYS_YIELD
```

### $02 sleep (SYS_SLEEP)
In: A = milliseconds (10 ms resolution, rounded up; 0 = yield). Interrupted by kill.
```asm
        lda     #500            ; half a second
        sys     SYS_SLEEP
```

### $03 getpid (SYS_GETPID)
Out: A = your task id (1-62).
```asm
        sys     SYS_GETPID
        jsr     put_dec         ; print it
```

### $30 spawn (SYS_SPAWN)
In: X, Y = block `{u24 path, u24 args, u8 priority}`. Out: A = the child's task id.
`args` = a zero-terminated string of at most 127 characters (0 = none). Priority 0
(highest) to 3; normal programs use 1. Bit 7 (`SP_DETACH`) = no parent waits: the child is
freed at its exit. Returns once the program is loaded. Errors: ENOMEM (no banks), EAGAIN
(no task slot, 16 at most), $44/$45 (no such file), EINVAL (not a Horizon program),
ERUNNING (single instance, already running). ulib's `spawn` and ui.lib's `ui_launch` wrap it.
```asm
        ptr     spb             ; {u24 path, u24 args, u8 priority}
        sys     SYS_SPAWN       ; -> A = task id
        bcs     @err
        sys     SYS_WAIT        ; wait for it: A = its exit code
@err:   rts
spb:    .faraddr p_hello, a_hello
        .byte   1
p_hello: .byte  "/SYSTEM/TESTS/HELLO.PRG", 0
a_hello: .byte  "from a parent", 0
```

### $31 wait (SYS_WAIT)
In: A = a child's task id. Out: A = its exit code. Blocks until it exits, then frees it.
ECHILD if it is not your child (or already waited for, or detached).
```asm
        lda     z:n             ; the id from SYS_SPAWN
        sys     SYS_WAIT
        cmp     #$FF80          ; killed (kill or ctrl-C)?
```

### $32 kill (SYS_KILL)
In: A = task id. The task exits with code $FF80 at its next return to user mode (a sleep,
wait, recv or input read is cut short). Any live task may be killed. ECHILD: no such task.
```asm
        lda     z:n
        sys     SYS_KILL
```

### $33 task_info (SYS_TINFO)
In: A = slot 0-15, X, Y = a 16-byte record. The record: u8 id (0 = free slot), u8 state
(1 ready, 2 running, 3 blocked, 4 zombie), u8 priority, u8 banks owned, u8 parent id,
8 characters name (space padded), u8 flags (`TI_WINDOWS` 1, `TI_MODAL` 2, `TI_IDLE` 4,
`TI_SINGLE` 8), u8 number of windows, 1 spare byte.
```asm
        stz     z:n
@slot:  lda     z:n
        ptr     buf             ; 16 bytes
        sys     SYS_TINFO
        lda     buf
        and     #$00FF          ; id 0: a free slot
        beq     :+
        jsr     put_dec         ; print the task id
        jsr     put_nl
:       inc     z:n
        lda     z:n
        cmp     #16
        bcc     @slot
```

### $34 task_single (SYS_SINGLE)
One instance of this program (the same absolute path) only. If one runs already, its
windows are raised and the call returns C set, A = ERUNNING, X = its id: exit. Otherwise
later spawns of the same path raise this one and fail with ERUNNING.
```asm
        sys     SYS_SINGLE
        bcc     :+
        exit    0               ; already running
:
```

## Time

### $04 uptime (SYS_UPTIME)
Out: A = milliseconds since reset, low word; X = high word. From the hardware microsecond
counter. The board has no real-time clock.
```asm
        sys     SYS_UPTIME
        sta     z:t0            ; start time (low word: wraps every 65.5 s)
        ; ... work ...
        sys     SYS_UPTIME
        sec
        sbc     z:t0            ; A = elapsed ms (under 65 s)
```

For a steady rate in a window program use `SYS_WTIMER` (WE_TICK events) instead of
sleeping: see [windows.md](windows.md), or `SYS_VSYNC` below.

### $0F vsync (SYS_VSYNC)
Out: A = the frame counter. Blocks until the next vertical blank begins (60.03 a second).
Horizon 0.18: from REV $09 A is Marga's frame counter (as `SYS_FRAME`: a difference of more
than 1 between two results is a missed frame), and the call also waits until your draw list
is done. A game that calls it, then updates and draws, moves once a frame without tearing.
Interruptible by kill. The details, `frame` and WE_VBL: [games.md](games.md), "Frame sync".
```asm
        sys     SYS_VSYNC       ; the next frame starts: A = the frame counter
```

### $0D time_get (SYS_TGET)
Out: A = seconds since 2000-01-01 00:00, low word; X = high word; Y = how the clock was
set: CLK_NONE 0 (never: it counts from 0 at start), CLK_SAVED 1 (a provisional value, the
last one saved), CLK_SET 2 (set in this session). Horizon 0.14. The controls library turns
it into a date (`ui_clksplit`, `ui_clklong`).
```asm
        sys     SYS_TGET
        cpy     #CLK_SET
        bne     :+              ; not set: show "up" time instead
        jsr     ui_clksplit     ; ui_clk = the date
:
```

### $0E time_set (SYS_TSET)
In: A = seconds low, X = high, Y = CLK_SAVED or CLK_SET. The clock counts from there. The
board has no battery clock: the Desktop keeps the last value in /SYSTEM/CLOCK.
```asm
        lda     #0              ; 2000-01-01 00:00 ...
        ldx     #0
        ldy     #CLK_SET
        sys     SYS_TSET
```

## Memory

### $10 bank_alloc (SYS_BALLOC)
Out: A = a fresh 64 KB bank, yours (read + write). Contents undefined (not cleared).
ENOMEM when none is left. Address it with long addressing.
```asm
        sys     SYS_BALLOC      ; -> A = bank
        bcs     @nomem
        sta     z:t0+2          ; a long pointer t0 = bank:0000 (t0 is 4 bytes here)
        stz     z:t0
        lda     #0
        ldy     #0
:       sta     [t0],y          ; clear it, two bytes at a time
        iny
        iny
        bne     :-
@nomem:
```
(Here `t0` must be a 4-byte zero-page variable: `t0: .res 4`.)

### $11 bank_free (SYS_BFREE)
In: A = a bank from bank_alloc. EINVAL for anything else. Banks are freed at exit anyway.
```asm
        lda     z:t1            ; the bank
        sys     SYS_BFREE
```

### $12 mem_info (SYS_MINFO)
Out: A = free banks, X = total banks (92 on 8 MB).
```asm
        sys     SYS_MINFO
        jsr     put_dec         ; free 64 KB banks
```

## Console

The console is the text screen (78 x 29 characters, 8 x 12 cells) when the window system is
not running, or the Terminal window a program was started from; every byte also goes to
the kernel log (DBG_OUT). Use ulib's buffered output (`print`, `out_str`, `put_dec`,
[ulib.md](ulib.md)): one line is one `puts`, never mixed with another task's output.
Control characters: LF, CR, BS, FF (clear), TAB; VT52-style escapes: ESC Y r c (cursor to
row r - 32, column c - 32), ESC K (clear to end of line), ESC E (clear screen), ESC p / q
(inverse on / off), ESC f / e (cursor off / on).

### $05 putc (SYS_PUTC)
In: A = character (low byte). Unbuffered; prefer ulib's `out_char`.
```asm
        lda     #'*'
        sys     SYS_PUTC
```

### $06 puts (SYS_PUTS)
In: X, Y = a zero-terminated string, written as one piece.
```asm
        ptr     s_hi
        sys     SYS_PUTS
        rts
s_hi:   .byte   "Hello", 10, 0
```

### $07 con_size (SYS_CSIZE)
Out: A = columns, X = rows of the console (78 x 29 on the screen; a Terminal's own size).
```asm
        sys     SYS_CSIZE       ; A = columns, X = rows
        stx     z:t1
        sta     z:t0
```

A full-screen text program: cursor to row 5, column 10 (escapes go through `out_char`):
```asm
        lda     #27             ; ESC
        jsr     out_char
        lda     #'Y'
        jsr     out_char
        lda     #32 + 5         ; row 5
        jsr     out_char
        lda     #32 + 10        ; column 10
        jsr     out_char
        print   "here"
        jsr     out_flush
```

## Files, directories

See [files.md](files.md) (open, read, write, seek, stat, readdir, delete, mkdir, rename,
chdir, getcwd).

## Keyboard (console programs)

Window programs get their keys as window events (`WE_KEY`, [windows.md](windows.md)), not
from these calls. These are for console programs (the text shell, a Terminal window).

One task holds the keyboard. The shell lends it to the program it runs in the foreground,
so a console program can read keys at once. Key events: A = HID usage ($04 = A ... $1D = Z,
$1E-$27 = 1-9 0, $28 Enter, $29 Esc, $2A Backspace, $2B Tab, $2C Space, $4F-$52 Right,
Left, Down, Up), X = modifiers | down << 8 (modifier bits: 0 left ctrl, 1 left shift, 2
left Alt, 3 left GUI, 4-7 the right ones). ulib's `key_ascii` turns an event into ASCII
(US layout), `read_char` waits for a character, `getline` reads a line with editing.

### $50 input_claim (SYS_ICLAIM)
Take the keyboard (the queue is emptied). Nothing changes if you hold it already. EAGAIN if
another task holds it.
```asm
        sys     SYS_ICLAIM
```

### $51 input_read (SYS_IREAD)
Out (a key): A = HID usage, X = modifiers | down << 8. Out (the mouse, while you hold the
keyboard and the window system is not running): A = $0100 | buttons, X = x, Y = y; the
wheel: A = $0200, X = steps. F12 arrives as usage $FF. Blocks until an event comes.
```asm
@key:   sys     SYS_IREAD       ; A = usage, X = mods | down << 8
        cpx     #$0100          ; a press?
        bcc     @key
        cmp     #$29            ; Esc
        beq     @done
        jsr     key_ascii       ; (A, X as returned) -> A = ASCII or 0
@done:
```

### $54 input_poll (SYS_IPOLL)
As input_read, but returns C set, A = EAGAIN at once when nothing is queued.
```asm
        sys     SYS_IPOLL
        bcs     @nokey          ; nothing typed
        ; A, X = the event
@nokey:
```

### $52 input_release (SYS_IRELEASE)
Give the keyboard back (to whoever lent it). Done at exit anyway.
```asm
        sys     SYS_IRELEASE
```

### $53 input_lend (SYS_ILEND)
In: A = task id, X = 1 to let ctrl-C kill that task (0: ctrl-C is a key). Lend the
keyboard to a child (as the shell does); it comes back when the child releases it or exits.
```asm
        lda     z:n             ; the child's id
        ldx     #1              ; ctrl-C kills it
        sys     SYS_ILEND
```

### $5F mouse_inject (SYS_MINJECT)
In: A = dx | dy << 8, X = wheel | buttons << 8 (signed bytes). A test aid: feeds one mouse
event through the kernel as if the I/O processor had sent it. (Horizon 0.15 named it in
horizon.inc.)
```asm
        lda     #10 | (5 << 8)  ; 10 right, 5 down
        ldx     #0              ; no wheel, no buttons
        sys     SYS_MINJECT
```

### $55 joystick (SYS_JOY)
In: A = 0. Out: A = the directions (bits 0-3 port 1: JOY_UP 1, JOY_DOWN 2, JOY_LEFT 4,
JOY_RIGHT 8; bits 4-7 port 2 the same), X = the triggers (bit 0 port 1, bit 1 port 2);
1 = pressed. Horizon 0.15: the two DB9 ports, read when called (poll it once a frame).
A = 1 is a test aid: X = directions and Y = triggers are ORed into what the ports give
until it is called again with 0, 0. The emulator's ports read 0 (nothing pressed).
```asm
        lda     #0
        sys     SYS_JOY
        and     #JOY_LEFT | JOY_RIGHT | JOY_UP | JOY_DOWN   ; port 1's directions
        sta     z:t0
        txa
        and     #1              ; port 1's trigger
        sta     z:t1
```

## Message ports

16 ports for the whole system, 8 messages of 16 bytes queued per port. A port belongs to
the task that created it; any task may send to it. Pass a port number to a child in its
argument string (see `horizon/user/ping.s` and `pong.s`).

### $40 port_create (SYS_PCREATE)
Out: A = port (0-15). EAGAIN if all are taken.
```asm
        sys     SYS_PCREATE
        sta     z:n             ; my port
```

### $41 send (SYS_SEND)
In: A = port, X, Y = 16-byte message. EAGAIN if its queue is full, EINVAL if not open.
```asm
        lda     z:n             ; the port
        ptr     buf             ; 16 bytes
        sys     SYS_SEND
```

### $42 recv (SYS_RECV)
In: A = your port, X, Y = 16-byte buffer. Blocks while the queue is empty. EINVAL if the
port is not yours.
```asm
        lda     z:n
        ptr     buf
        sys     SYS_RECV        ; buf = the message
```

### $43 port_close (SYS_PCLOSE)
In: A = your port. Queued messages are dropped.
```asm
        lda     z:n
        sys     SYS_PCLOSE
```

## System

### $0A restart (SYS_RESTART)
In: A = 0 restart Horizon, 1 full restart (the classic machine and /atari.ini too). Closes
every file and flushes the card first. Does not return when it works. Programs should
ask the Desktop instead (`SYS_SYSREQ`), which lets every program save first.
```asm
        lda     #SR_RESTART
        sys     SYS_SYSREQ      ; ask the Desktop
        bcc     :+
        lda     #0              ; no Desktop: restart directly
        sys     SYS_RESTART
:
```

### $0B sync (SYS_SYNC)
In: A bit 0 = end every other program first (shut down). Closes every open file and has
the I/O processor flush the card; afterwards the power may be cut. Errors: $40 + the I/O
result.
```asm
        lda     #0              ; just flush, keep the programs
        sys     SYS_SYNC
```

### $0C sysreq (SYS_SYSREQ)
In: A = `SR_SHUTDOWN` 1, `SR_RESTART` 2, `SR_FULLRESTART` 3. Asks the Desktop, which asks
every program to close (WE_CLOSE) and then restarts or shuts down. EINVAL without the
Desktop.
```asm
        lda     #SR_SHUTDOWN
        sys     SYS_SYSREQ
```

### $87 setting (SYS_SETTING)
In: A = id, X = new value ($FFFF = only read). Out: A = the old value. Ids:

| Id | Setting |
| --- | --- |
| 0 | mouse speed 1-4 |
| 1 | the alert (beep) volume 0-15, 0 silent (POKEY 2: beeps and chimes) |
| 2 | key repeat delay in 10 ms ticks (0 = no repeat; default 40) |
| 3 | key repeat interval in ticks (default 5) |
| 4 | (Horizon 0.18) the sound volume 0-15: Lau's master volume, volume x 17 (default 8; before 0.18 Lau followed setting 1) |

These are the user's settings (Settings saves them): change them only in a settings
program. A game reads setting 4 only if it wants to show it; Lau applies it to every voice.
```asm
        lda     #2              ; key repeat delay
        ldx     #$FFFF          ; read only
        sys     SYS_SETTING     ; -> A = ticks
```

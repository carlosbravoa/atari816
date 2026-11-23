# Horizon ABI (version 0.30)

This file describes the interface between Horizon and user programs. `user/horizon.inc`
holds the same definitions for ca65.

## Syscalls

A syscall is `COP #n`. The signature byte n is the syscall number; the kernel reads it at
PBR:PC-1.

- **Arguments:** in A, X and Y, always taken as 16-bit values. Use `REP #$30` before COP.
- **Result:** in A (and in X where the table says so).
  - Carry clear means OK.
  - Carry set means error, with the error code in A.
- **Registers:** X, Y, D, DBR and the other flags come back unchanged, unless the table
  says otherwise. M and X also come back unchanged: if the caller had 8-bit registers, it
  sees the low byte of the result.
- **Pointers:** X = offset, Y = bank (0-255).
  - Bank 0 means the task's own window ($0000-$7FFF: direct page, stack, anything else
    put there).
  - Any other bank must be readable by the task: VALID, and the owner is the task or 63.
    A write also needs WRITE.
  - The whole range is checked. A range must not cross a bank boundary or $00:8000.
    Otherwise the error is EFAULT.
- **Blocks:** several calls take X, Y pointing at a small parameter block. In a block, a
  "u24" is a 3-byte pointer (offset low, offset high, bank). Pointers in blocks follow the
  same rules as pointers in registers.

| # | Name | In | Out | Notes |
| --- | --- | --- | --- | --- |
| $00 | exit | A = code | - | Never returns |
| $01 | yield | - | - | Gives the CPU to the next ready task of the same or higher priority |
| $02 | sleep | A = milliseconds | - | 10 ms resolution, rounded up. 0 = yield. Interruptible by kill |
| $03 | getpid | - | A = task id (1-62) | |
| $04 | uptime | - | A = ms low, X = ms high | Milliseconds since reset, from the hardware microsecond counter |
| $05 | putc | A = character (low byte) | - | Kernel console (DBG_OUT) |
| $06 | puts | X, Y = zero-terminated string | - | Written as one piece: never spliced with another task's output (see Console). EFAULT if the terminator is not inside the accessible region |
| $07 | con_size | - | A = columns, X = rows | The screen console's text area: 78 x 29. Programs that lay out text use this, not a constant |
| $08 | chdir | X, Y = path | - | The task's current directory (relative paths allowed). It must exist and be a directory: EINVAL if it is a file, $44/$45 if it does not exist. Inherited by tasks it spawns |
| $09 | getcwd | X, Y = buffer, A = its size | A = length | The current directory, absolute, zero-terminated. EINVAL if the buffer is too small |
| $0A | restart | A = 0 Horizon only, 1 full restart | - | (0.13) Every open file is closed and the card synced (I/O op $1C), then the I/O processor's SYS_RESTART (op $1B, ARG0 = A): 0 reloads and restarts Horizon, 1 re-reads /atari.ini, cold boots the classic core and reloads Horizon. It does not come back when it works; an error is the I/O result + $40 ($C2: a firmware without the op). Programs should rather ask the Desktop (sysreq), which lets every program save first. EINVAL for A > 1 |
| $0B | sync | A = bit 0: end every other program first | - | (0.13) Bit 0 (shutting down): every task except INIT, the caller and the window system's thread is killed, and the call waits until they are gone (3 s at most). Then every open file (of any task) is closed and the I/O processor flushes and closes everything on the card (I/O op $1C SYS_SYNC); afterwards the card may be removed or the power cut. Errors: the I/O result + $40 |
| $0C | sysreq | A = 1 shut down, 2 restart, 3 full restart, (0.31) 4 SR_APPS | - | (0.13) Asks the Desktop: the backdrop window gets WE_SYSREQ (a = A, c = the caller's task id); the Desktop asks every program to close, then restarts or shuts down (no confirmation: the asker confirmed). EINVAL without the window system or a backdrop. The shell's `restart` and `shutdown` use it. (0.31) SR_APPS: the apps changed (the Installer after an install or a removal, Files after a change in /APPS): the Desktop reads its Programs menu again at its next second, or at once if the menu opens first (several requests, one reading). Before 0.31: EINVAL |
| $0D | time_get | - | A = seconds low, X = seconds high, Y = state | (0.14) The clock: seconds since 2000-01-01 00:00, counted by the 10 ms tick from the value time_set gave (the board has no battery clock). Y: 0 CLK_NONE never set (it counts from 0 since the start), 1 CLK_SAVED a provisional value (the last one saved, loaded at start by the Desktop or the shell), 2 CLK_SET set in this session. The controls library turns it into a date (ui_clk*, ui.inc) |
| $0F | vsync | - | A = the frame counter (as frame, $9E) | (0.15) Blocks until the next vertical blank begins (NV_LINE 360; 60.03 a second), for games that draw once a frame. (0.18) From REV $09 Marga's VBLANK interrupt ends the wait and A is NV_FRAME, so a program sees the frames it missed (a difference above 1); before REV $09 the moment is derived from the raster line with a one-shot TIMER1 (the VBLANK interrupt as well) and A counts the vertical blanks waited for by any task. (0.18) Then it also waits until the caller's draw list is done and makes the CPU see what Ali wrote. Interruptible by kill |
| $0E | time_set | A = seconds low, X = high, Y = 1 CLK_SAVED or 2 CLK_SET | - | (0.14) The clock counts from there (the second starts now). EINVAL for another Y. Programs keep the value across restarts themselves: the Desktop and the shell save it to `/SYSTEM/CLOCK` (one line `YYYY-MM-DD HH:MM:SS`) when it is set and before a restart or shut down, and load it at start (ui_clkload / ui_clksave). (0.19) The kernel also gives the time to the I/O processor (op $1D SYS_TIME), which counts on from it and stamps the files it writes with it (STAT's FAT time; `ls` in the shell and Files' footer show it); until a time is given, files get the firmware's build date (an older firmware: a fixed date). (0.20) With the PC volume there, the Desktop and the shell set the clock from the PC (stat of `/PC:`; CLK_SET, saved) at start, and the Desktop again whenever the PC volume comes back (ui_clkpc) |
| $10 | bank_alloc | - | A = bank | A fresh 64 KB bank owned by the task (VALID + WRITE). Contents undefined. ENOMEM when none is left |
| $11 | bank_free | A = bank | - | Only a bank from bank_alloc: not the window or code bank, else EINVAL |
| $12 | mem_info | - | A = free banks, X = total banks | Total = free + owned by tasks + kernel banks taken from the pool: 92 on 8 MB, of which the kernel keeps 4 for the screen ($7C-$7F) |
| $20 | open | X, Y = path, A = mode | A = handle (0-3) | Mode 0 read, 1 read/write (the file must exist), 2 create/truncate, 3 append |
| $21 | close | A = handle | - | |
| $22 | read | X, Y = {u8 handle, u24 buffer, u16 length} | A = bytes | Fewer bytes than asked = end of file |
| $23 | write | same block | A = bytes | |
| $24 | seek | A = handle, X = offset low 16, Y = offset high 16 | A = position low, X = position high | |
| $25 | stat | X, Y = {u24 path, u24 out} | A = size low, X = size high | `out` gets 9 bytes: u32 size, u8 attr (bit 4 = directory, bit 0 = read-only, $20 = archive), u32 FAT time (fdate << 16 \| ftime). (0.23) Some names answer about the machine instead: `/PRN:` (the print jobs finished), `/PC:` (the gateway's services), `/D1:` .. `/D4:` (the folder disk): see "Printing, Run in Atari and the folder disk (0.23)" |
| $26 | readdir | X, Y = {u24 path, u24 buffer, u16 length, u16 skip} | A = entries | Entries are packed into the buffer: u32 size, u8 attr, u8 name length, name (no terminator). Without "." and ".."; in the I/O processor's order: the directory's own (FatFs) order on the board, sorted by name in the emulator. Programs that show a list sort it themselves (Files, the file dialog, FILES do). `skip` entries are skipped, for continuation. The buffer must have room for the path, which the kernel copies there first (an I/O processor rule) |
| $27 | delete | X, Y = path | - | |
| $28 | mkdir | X, Y = path | - | |
| $29 | rename | X, Y = {u24 old path, u24 new path} | - | Renames or moves a file or folder on the card (I/O processor RENAME). Both paths are resolved like any other. Errors as for open. (0.20) Inside the PC volume too; between the card and the PC volume: $C9 (copy, then delete: the controls library's ui_mvtree does it) |
| $30 | spawn | X, Y = block {u24 path, u24 args, u8 priority (bit 7 SP_DETACH)} | A = task id | `args` = a zero-terminated argument string of at most 127 characters, or 0 for none; the kernel copies it to the top of the child's window (see Task start conditions). Priority 0 (highest) to 3. Returns once the program is loaded: a load error is returned here and no task is left behind (the causes a launcher tells apart: ENOMEM no banks, EAGAIN no task slot, $44/$45 no such file, EINVAL not a valid program, ERUNNING a single-instance program already runs). SP_DETACH ($80 in the priority byte): the child has no waiting parent and is freed at its exit (the parent still gets the load result) |
| $31 | wait | A = task id | A = exit code | Only for the caller's own children. Blocks until the child exits, then frees it. ECHILD if the task is not a child (or was already waited for). Interruptible by kill |
| $32 | kill | A = task id | - | Any live task, including the caller. The target exits with code $FF80 at its next return to user mode. A sleep, wait, recv or input_read in progress is cut short. A pending file operation finishes first. ECHILD (5) if no such task |
| $33 | task_info | A = slot 0-15, X, Y = 16-byte record | - | Record: u8 id (0 = free slot), u8 state (1 ready, 2 running, 3 blocked, 4 zombie), u8 priority, u8 banks owned, u8 parent id (0 = none), 8 characters name (space padded), u8 flags (0.13: TI_WINDOWS 1 it has windows, TI_MODAL 2 a WF_MODAL window is open, TI_IDLE 4 it waits in win_event with nothing queued, TI_SINGLE 8 single instance), u8 its number of windows, 1 spare byte (0) |
| $34 | task_single | - | - | (0.13) One instance of the caller's program (the same absolute path) only. If another live task runs it already, that task's windows are raised (the top one gets the focus) and the call returns C set, A = ERUNNING, X = its id: the caller should exit. Otherwise the caller is marked, and a later spawn of the same path raises its windows instead and returns ERUNNING. The Desktop, About and Settings call it first thing |
| $35 | task_path | X, Y = buffer, A = its size | A = length | (0.28) The absolute path of the file the caller's program was loaded from, zero-terminated, as the loader opened it: "/GAMES/MINE/GAME.PRG" (the path given to spawn, made absolute with the parent's current directory; upper or lower case as it was given). At most 127 characters: a 128-byte buffer always fits. EINVAL if the buffer is too small (as getcwd), EFAULT a bad buffer. A program finds its own data files next to it this way. Before 0.28 the call does not exist (ENOSYS) |
| $36 | sys_info | - | A = version, X = the hardware revision | (0.29) Horizon's version as major << 8 \| minor ($001D for 0.29, $001E for 0.30) and SYS_REV (what About shows; $0C: the OPL2, $0B: sprites, $0A: Lau, $08: the blitter). No side effects (unlike ws_config). A program checks what it needs with it: HZ_NEEDS (user/needs.inc) and hcc --needs, see sdk/docs/apps.md. Before 0.29 the call does not exist (ENOSYS): task_path answering (EINVAL for a buffer of size 0) tells 0.28 |
| $40 | port_create | - | A = port (0-15) | The caller owns the port. EAGAIN if all 16 are in use |
| $41 | send | A = port, X, Y = 16-byte message | - | Any task may send. EAGAIN if the port's queue (8 messages) is full, EINVAL if the port is not open |
| $42 | recv | A = port, X, Y = 16-byte buffer | - | Owner only (else EINVAL). Blocks while the queue is empty. Interruptible by kill. (0.26) A = port \| RV_POLL ($8000): EAGAIN at once when the queue is empty (a window program reads its port at each event without waiting) |
| $43 | port_close | A = port | - | Owner only. Queued messages are dropped |
| $50 | input_claim | - | - | The caller receives the keyboard: KB_ROUTE = 0, the queue is emptied. If the caller already holds it (claimed or lent), nothing changes and the queue is kept. EAGAIN if another task holds it |
| $51 | input_read | - | Key: A = HID usage ($00-$FF), X = modifiers \| down << 8. Mouse: A = $0100 \| buttons, X = x, Y = y. Wheel: A = $0200, X = wheel delta (signed) | Holder only. Blocks while the queue is empty. The system key (F12, NMI) arrives as usage $FF, down; F12's own key events are dropped. Y is set by mouse and wheel events (0 for wheel) and unchanged by keys. Interruptible by kill (see Mouse) |
| $52 | input_release | - | - | Back to the task that lent it, if any, else KB_ROUTE = 1. Also done automatically at exit |
| $53 | input_lend | A = task id, X = flags | - | Holder only. The keyboard goes to that task; the queue is kept and KB_ROUTE stays 0, so typeahead survives. It comes back when the borrower releases it or exits. X bit 0 = break: ctrl-C then kills the borrower (see Keyboard) |
| $54 | input_poll | - | as input_read | As input_read, but when nothing is queued it returns EAGAIN at once (C set). (0.22) Also for a task attached to a terminal window (ws_term): it polls the window's keys, as input_read reads them (before 0.22 it ignored the terminal) |
| $55 | joystick | A = 0 | A = directions, X = triggers | (0.15) The two DB9 ports (JOY_PORT, JOY_TRIG), 1 = pressed. A: bits 0-3 port 1 (JOY_UP 1, JOY_DOWN 2, JOY_LEFT 4, JOY_RIGHT 8), bits 4-7 port 2 the same; X: bit 0 port 1's trigger, bit 1 port 2's. A = 1 is a test aid: X = directions and Y = triggers are ORed into what the ports give from then on (0, 0: off). EINVAL for another A. Any task may read them |
| $5F | mouse_inject | A = dx \| dy << 8, X = wheel \| buttons << 8 (signed bytes) | - | Test aid: feeds one MOUSE event through the same kernel path as the I/O processor's (pointer, queue, coalescing) |
| $60 | classic_show | - | - | Holder only (else EINVAL). Lets the classic Atari run (it is frozen whenever the desktop is shown, REV $06+) and hands the screen (NV_CTRL.ENABLE = 0) and the keyboard (KB_ROUTE = 1) to the classic Atari, and blocks until the system key (F12) is pressed. That F12 press gives no $FF event. Then the classic Atari is frozen again, the desktop and keyboard come back, the key queue is emptied, and key events are swallowed until every key reported down meanwhile has been released (at least 30 ms, at most 300 ms). Interruptible by kill |
| $61 | classic_mount | X, Y = path, A = kind \| slot << 8 | A = kind mounted (1 disk, 2 executable, 3 cartridge) | Kind 0 = by extension (.ATR .XFD disk; .XEX .COM .EXE executable; .CAR .ROM .BIN cartridge), 1 disk, 2 executable, 3 cartridge, (0.23) 4 CK_BASRUN (a BASIC program: answered as 2), 5 CK_FOLDER (a folder as a disk: answered as 1); see "Printing, Run in Atari and the folder disk (0.23)". Slot 0-3 = D1:-D4: (disks only; an executable is the virtual boot disk on D1:). Mount only, no reset: the classic machine is frozen while the desktop is shown. Errors: $44 no file, $C3 bad kind, slot or extension, $C4 not a valid image, $C5 the firmware menu is open, $C2 the firmware does not know the op. A large cartridge can take seconds (the caller blocks; other tasks run). (0.18) A cartridge: the I/O processor loads its image into banks $70 and up (its SDRAM from $400000), so the kernel first takes those banks out of the pool (size / 64 KB, at most 12: 768 KB) and keeps them until the cartridge is ejected; ENOMEM if one of them is in use (then nothing is mounted). The kernel allocates its own runs of banks (the screen, window bitmaps) below $70 first |
| $62 | classic_eject | A = kind \| slot << 8 | - | Kind 1 disk (slot 0 also ejects the executable), 2 executable, 3 cartridge. Ejecting an empty slot is OK |
| $63 | classic_boot | - | - | Keyboard holder only (else EINVAL). In order: lets the classic machine run, routes the keyboard to it, sends CLASSIC_BOOT and waits (0.2-0.8 s), then shows it exactly as classic_show does (F12 returns, the machine is frozen again). On a failed boot, freeze and keyboard are put back (held keys swallowed) and the error is returned. (0.18) A = CB_STAY ($C01D): the same cold boot, then the classic machine is frozen again and not shown (the call returns at once after the boot): what the Desktop does when a cartridge is attached or ejected, as switching a real machine off and on |
| $64 | classic_query | A = item: 0-3 D1:-D4:, 4 executable, 5 cartridge; X, Y = 128-byte buffer | A = length (0 = nothing mounted) | The absolute path mounted there, as recorded by classic_mount / classic_eject (mounts made by the firmware's own menu are not seen). (0.19) A cartridge the I/O processor loaded by itself at power-on (`boot=ash` in /atari.ini) is asked for at start (op $1E CLASSIC_STATE): its banks are reserved as classic_mount reserves them, and item 5 reports its path |
| $65 | beep | A = pitch (POKEY AUDF1), X = duration in 10 ms ticks, Y = volume 0-15 | - | REV $07+: channel 1 of POKEY (the classic machine's, lent while that machine is frozen; POKEY 2, its second one, before REV $0C), pure tone, stopped by the timer tick; a new beep replaces the one playing; X = 0 silences channel 1. Ignored on older boards and while the classic machine runs. (0.15) Channel 1 counts as the caller's (see sound_write). The user interface's own sound is the chime ($67) |
| $66 | sound_write | A = register $00-$13, X = value | - | REV $07+: raw write to $00:DB00 + A ($00-$0F POKEY, $10-$13 the DACs: 0, 1 left, 2, 3 right). REV $0C has no DACs (those writes do nothing: use Lau) and its POKEY takes AUDF1-AUDC4, AUDCTL, STIMER and SKCTL bits 0-1 only (Docs/02-register-spec.md, "POKEY"). EINVAL above $13. The hardware takes these only while the classic machine is frozen; the kernel silences AUDC1-4 and the DACs before every unfreeze. (0.15) The kernel keeps a copy of every register written and who wrote it last: a channel (AUDFn / AUDCn), a DAC, or the rest (AUDCTL, SKCTL, ...). When that task ends (exit, kill, crash) its channels and DACs are silenced, and AUDCTL / SKCTL go back to 0 / 3 if it wrote them. While the chime borrows a channel, writes to it go only to the copy and reach the hardware when the chime ends |
| $67 | sound_chime | A = kind: 0 CH_INFO, 1 CH_WARN, 2 CH_QUESTION, 3 CH_ERROR; X = volume 0-15 ($FFFF: the beep volume setting) | - | (0.15) The chime of the user interface (the alerts, the error beep): two soft notes, pure tone, the volume falling every 10 ms tick: the first note 60 ms (16, 14, 12, 11, 10, 9 sixteenths of the peak) and 10 ms of silence, the second 150 ms (16, 14, 12, 10, 9, 8, 7, 6, 5, 4, 3, 2, 2, 1, 1 sixteenths), 0.22 s in all; peak = (volume * 3 + 2) / 4. Notes (AUDF at the 64 kHz clock): information A5, E5 (35, 47); warning A5, A5; question E5, A5; error E5, C5 (47, 60). It takes a channel no task owns (4, 3, 2, 1, one whose AUDCTL bits are clear); when all four are owned it borrows channel 4 (its AUDCTL bits cleared meanwhile) and gives the owner's values back at the end. A new chime replaces the one playing. Volume 0 or a board without the sound page: nothing. EINVAL for kind > 3 |
| $68 | sample_play | X, Y = 16-byte block (below) | A = the voice 0-7 | (0.17) Lau, the sample player (REV $0A): plays signed PCM from the caller's memory on a voice; the hardware then needs nothing more. Block: u24 address of the first sample (16-bit samples: an even address), u24 length in samples (1 or more), u24 loop start in samples (with the loop flag: it plays to the end, then from there again; length - loop start at least 4), u16 pitch (the step per 48 kHz output sample, 2.14 fixed point: $4000 = 48,000 samples a second, $2000 = 24,000, $1555 = 16,000; up to $FFFF), u8 left volume, u8 right volume (0-255), u8 flags (bit 0 SPF_LOOP, bit 1 SPF_16: signed 16-bit little-endian samples, else signed 8-bit; (0.26) bit 2 SPF_KEEP: music, the voice plays on while the classic Atari is shown), u8 voice (0-7, or SP_ANY $FF: the first voice not playing; when all eight play, the caller's voice that started first), u8 0. The whole sample must lie in memory the caller owns: its window (bank 0, $0000-$7FFF), its code bank or banks it allocated; it may run across consecutive banks it owns (8 MB at most: 16 M samples). Errors: ENODEV no Lau (REV < $0A: use POKEY), EFAULT any other memory (Lau reads RAM by itself, past FREDDIE II's protection, so the kernel checks the range), EINVAL no samples, an odd 16-bit address, a loop shorter than 4, voice above 7, EAGAIN the voice asked for plays for another task (or SP_ANY: all eight play and none is the caller's). See "Samples" below |
| $69 | sample_stop | A = voice, $FFFF: every voice of the caller | - | (0.17) Stops the voice at once and frees it. EINVAL: not the caller's voice (one it started and that was not stopped or taken since); ENODEV without Lau |
| $6A | sample_stat | - | A = the caller's voices playing, X = all voices playing | (0.17) Bit n = voice n (a voice that reached its end without the loop flag no longer plays). ENODEV without Lau: a program asks this once at its start to choose between Lau and POKEY |
| $6B | sample_set | A = voice, X = pitch, Y = left volume \| right volume << 8 | - | (0.17) Changes the pitch and volumes of one of the caller's voices while it plays (slides, fades, panning): the hardware takes them at its next output sample. EINVAL: not the caller's voice |
| $6C | sample_timer | A = own port ($FFFF: off), X = period low 16 bits, Y = high 8 bits (microseconds, 1,000 or more) | A = the generation | (0.26) The music timer (TIMER1, REV $0A+): at every period the kernel puts the message {u8 $FF, u8 the generation, u16 the count of periods since the start, 12 x 0} into the port (when the queue has room; the count goes on regardless, and it follows the microsecond clock: periods that passed while the kernel kept interrupts off count too, so a receiver that runs the difference catches up) and wakes the task waiting in recv. Called again while on: the new period counts from the next one on (a tempo change, no gap). Off (A = $FFFF), at the owner's end, and when the port is no longer the owner's. Each start from off is a new generation (+1, in A and in byte 1 of the messages), so messages of an earlier start can be told apart. One owner at a time: EAGAIN; ENODEV without Lau; EINVAL another task's port, a period below 1 ms or above 24 bits. See "Music (0.26)" |
| $6D | opl_write | A = OPL2 register $00-$F5, X = value; or A = $FFFE probe, $FFFF reset, $FFFD release | A = OPL_STAT | (0.27) The OPL2, a YM3812 FM synthesizer (REV $0C; Docs/02-register-spec.md, "OPL2"): writes the register and waits as a YM3812 needs (5 us after the address, 26 us after the data: about 45 us a call). **One owner**, like the music timer: the first task that writes a register or resets the chip owns it until it ends or releases it; meanwhile another task's write, reset or release returns EAGAIN. $FFFE writes nothing and only returns the status ($06 in bits 4-0: the test for the chip); it never takes the chip and always answers. $FFFF writes 0 to every register $01-$F5 (about 10 ms, the kernel is not interrupted meanwhile) and takes or keeps the chip. $FFFD keys off the nine channels and the rhythm instruments and gives the chip up; the same happens when the owner ends (exit, kill, crash). While the classic machine is shown (F12, classic_show, classic_boot) the kernel keys the notes off, nothing else: pitches, the rhythm mode and the vibrato / tremolo depths stay, the owner keeps the chip, and music goes on with its next notes. Errors: ENODEV before REV $0C, EINVAL for any other A above $F5, EAGAIN |
| $70 | ws_start | - | A = 1 started now, 0 already running | Starts the window system: 6 contiguous free banks become the 640x360 8 bpp screen (stride 1024), the system palette is loaded, the menu bar is created, the mouse and keyboard go to the window manager. The caller is its owner. ENOMEM without 6 contiguous free banks |
| $71 | ws_stop | - | - | Its owner only (else EINVAL): every window closes, the banks are freed, the text console comes back as it was |
| $72 | win_open | X, Y = {i16 x, i16 y, u16 width, u16 height, u24 title, u8 flags} | A = window (0-15) | Opens a window on top of its class (it gets the focus unless a backdrop). x, y = its outer top-left; width, height = its content area. It is kept fully on screen and below the menu bar (y >= 16). Flags: WF_RESIZE 1 (a bottom strip with a size grip), WF_PLAIN 2 (no frame or title: the content is the window), WF_BACK 4 (backdrop: always below the other windows; gets F12 and shows its menus first, as the system menu), WF_TERM 16 (a terminal, see ws_term), WF_MODAL 32 (a dialog: while it is open, a click on another window of the same program raises the dialog instead, with the error beep), WF_HOVER 64 (motion events also without a button, and WE_LEAVE: see win_event). The content starts C_BODY. The title is copied (31 characters). Banks are contiguous. ENOMEM: no banks; EAGAIN: no free window |
| $73 | win_close | A = window | - | The caller's own windows only (else EINVAL). A task's windows close when it exits |
| $74 | win_draw | A = window, X, Y = {u8 op, u8 c1, u8 c2, u8 font, i16 x, i16 y, i16 w, i16 h, u24 ptr} (ops 10 and 11: + u16 stride, 17 bytes) | - | Draws in the window's bitmap, content coordinates, clipped to the content. Op 1 fill rectangle in c1; 2 frame (1 pixel) in c1; 3 line from x, y to w, h in c1; 4 text: the zero-terminated string at ptr at x, y (its top), font 0 UI (proportional, 9 rows of ink, line 11) or 1 fixed 8x12, ink c1, paper c2 ($FF = transparent); 5 blit: the w x h 8 bpp image at ptr (rows of w bytes, one bank); 6 the same skipping pixels of colour c2; 7 a checker of c1 and c2 (c2 where x + y is odd); 8 like 5 with a source stride c1 \| c2 << 8 (a part of a larger image); 9 copy (WD_COPY): the rectangle x, y, w, h of the window's own content moves to (c1 \| c2 << 8, the low word of ptr), both signed; the two may overlap in any direction (scrolling); what lies outside the content on either side is left out of both (ptr is not a pointer here). One blitter COPY (BACKWARDS when the destination lies after the source); without the blitter the CPU copies line by line in the safe order. (0.14) 10 expand (WD_EXPAND): the w x h 1 bpp image at ptr (bit 7 is the leftmost pixel), its first pixel at bit `font` (0-7, 0 = bit 7) of the first byte, rows `stride` bytes apart (0: the bytes one row needs, (font + w + 7) / 8); set bits are drawn in c1, clear bits in c2, or left as they are when c2 = $FF; one blitter EXPAND (EXPAND_KEY for c2 = $FF), clipped with the source offset and SRC_BIT; without the blitter the CPU, pixel by pixel. 11 keyed blit with a stride (WD_KSBLIT): the w x h 8 bpp image at ptr, rows `stride` bytes apart (0: w), pixels of colour c2 skipped (one COPY_KEY). For both the whole source (stride * (h - 1) + one row) must be readable. (0.15) The ops that read the caller's memory (5, 6, 8, 10, 11) return only when the blitter has finished reading it, so the program may change its buffer right after the call (before 0.15 the blit could still be running: on the board a program that rewrote its buffer at once could corrupt the picture). The other ops (fills, text, lines, copies inside the window) still return while the blitter works. Shown at the next repaint, or at once: while no other window overlaps the window's content and no repaint over it is pending, every op is drawn on the screen itself (see Window system, "Direct drawing"). EINVAL bad window or op, EFAULT bad pointer |
| $75 | win_event | A = 0 wait / 1 poll, X, Y = 8-byte buffer | - | The next event of any of the caller's windows: {u8 type, u8 window, u16 a, u16 b, u16 c}. Types: 1 key (a = HID usage, b = modifiers \| down << 8; F12 is usage $FF and goes to the backdrop), 2 button (a, b = content x, y, signed; c = buttons, bit 0 left; a release goes to the window that got the press. A left press in a window's content, or a first press of another button while the pointer is over the top window, holds the press: the window gets the motion events and the release; other button changes go to the window holding the press, else the top window), 3 close box clicked (the window stays open until win_close), 4 wheel (a = signed steps, to the window under the pointer), 5 timer tick, 6 resized (a, b = new content size), 7 menu (a = menu, b = item, counting separators), 8 drop (see win_drop), (0.13: in 2 and 9, c = buttons \| modifiers << 8, the HID modifier bits as in key events: bit 0 left ctrl, 1 left shift, 2 left Alt, 3 left GUI, 4-7 the right ones; mask with $0007 for the buttons), 9 motion (while a button is held after a press in the window, and, for a WF_HOVER window, whenever the pointer moves over it while no other window holds a press and no menu, window drag or resize runs: a, b = the pointer in its content, c = buttons; a motion event still queued gets the newer position), 10 leave (WF_HOVER: the pointer is no longer over the window, or a menu, drag or another window's press took it; a, b, c = 0), 11 sysreq (0.13, the backdrop: a = what SYS_SYSREQ asked, c = the asking task's id), 12 status (0.14, the backdrop: the status text at the right of the menu bar was clicked; a = b = c = 0), 13 menu open (0.14, the backdrop: one of its menus is opening, a = the menu; it may call win_menu at once: the menu opens again with the new items), 14 focus (0.15: the window got the keyboard focus: it is the top-most normal window, or the backdrop with no other window), 15 unfocus (0.15: it lost the focus; just before it, every key the window holds (got a press of and no release yet) gets a release, b = 0, and the real release and any repeat of that key later go to nobody: a game never sees a key stuck down), (0.18) 16 vblank (win_vbl: a vertical blank came while the queue was empty; a = b = c = 0; in full-screen mode buttons and motion give the pointer on the screen), (0.22) 17 net (WE_NET: a = the bit mask of the program's stream handles with news; see "The internet"). (0.15) A key the window manager takes (a menu's keys, F10, Alt+Tab, ...) sends its release to nobody either. (0.14) In 8 (drop) c = the sender's task id \| the modifier keys << 8 at the drop. 32 events per window; when full, new ones are dropped; when three quarters full, key releases are dropped. EAGAIN when polling and empty. Interruptible by kill |
| $76 | win_twidth | A = font, X, Y = string | A = width in pixels | The width win_draw's text op would take |
| $77 | ws_sync | - | - | Waits until the screen shows everything drawn so far |
| $78 | win_move | A = window, X = x, Y = y | - | Moves a window (kept fully on screen) |
| $79 | ws_redraw | - | - | Repaints the whole screen (for measurements) |
| $7A | ws_stats | - | A, X = microseconds the last repaint took (low, high word) | For measurements |
| $7B | ws_config | A = bit 0 blitter off, bit 1 the compositor sleeps on the blitter interrupt, bit 2 no direct drawing | A = 1 if the blitter is used; (0.16) X = the hardware revision (SYS_REV) | For measurements and tests. The blitter (Ali) is used on REV $08+ unless bit 0 is set. X tells what else the machine has: POKEY's sound on REV $07+, Lau (the sample player) on REV $0A+, the OPL2 on REV $0C+ |
| $7C | win_timer | A = window, X = period in 10 ms ticks (0 = off) | - | WE_TICK events for that window |
| $7D | win_menu | A = window, X, Y = menus | - | The window's menus: "title", "item", ..., "", "title", ..., "", "" (zero-terminated strings; an item starting with '-' is a separator). 256 bytes at the pointer are read and 254 kept (where only 128 are readable: 126 of them). The bar shows the backdrop's menus, then the focused window's. (0.14) Up to 2045 bytes are kept: the list is read up to its end, or to the end of the pointer's bank (or of the window in bank 0); a longer one is cut at a string, keeping the menus well formed. Calling it while one of the window's own menus is open opens that menu again with the new items (the Desktop refreshes its Programs menu this way, on WE_MENUOPEN). (0.29) Before 0.29 such a call while a menu was open lost the new menus (the old ones stayed until the next call that changed them): fixed. (0.13) An item may start with a state byte MS_STATE \| bits ($10-$13, not drawn): MS_CHECK 1 a check mark in the left margin, MS_DIM 2 greyed, it cannot be highlighted or chosen; see win_mstate. An item may hold a TAB: the text after it (a shortcut, "Ctrl+S") is drawn right-aligned and the drop-down widens to fit. Menus without these look as before |
| $7E | ws_status | X, Y = string | - | The text at the right end of the menu bar (31 characters) |
| $7F | ws_term | A = terminal window (or $FF: detach) | - | The caller's console output (putc, puts) and keyboard input (input_*) go to that WF_TERM window from now on, and so do those of the tasks it starts afterwards (inherited at spawn). EINVAL if it is not the caller's terminal window |
| $80 | clip_put | X, Y = {u24 data, u16 length} | - | The system clipboard: copies the bytes (64 KB at most, one bank's range); length 0 empties it |
| $81 | clip_get | X, Y = {u24 buffer, u16 size} | A = the clipboard's length | Copies min(length, size) bytes; size 0 asks the length only |
| $82 | win_info | A = window (any program's), X, Y = 8-byte buffer | - | {i16 content x, i16 content y on the screen, u16 content width, u16 content height} |
| $83 | win_at | X = screen x, Y = screen y | A = window, $FF = none | The top-most window there (a backdrop too; not the menu bar) |
| $84 | win_drop | A = window (any program's), X, Y = string (127 characters) | - | Drag and drop: the window gets WE_DROP (a, b = the pointer in its content, c = the sender's task id) and reads the string with win_dropget |
| $85 | win_dropget | A = own window, X, Y = 128-byte buffer | - | The last string dropped on that window |
| $86 | ws_palette | A = index, X = red \| green << 8, Y = blue | - | Sets one palette entry. 0-15 (the UI colours): the system palette, for everyone (Settings' desktop colour, entries 2 and 3). (0.18) 16-255: the entry becomes the caller's own (if nobody holds it; EAGAIN if another program does) and shows its colour while one of its windows has the focus; see "Palette entries". In full-screen mode: the program's own palette, all 256 entries |
| $87 | setting | A = id, X = value ($FFFF: read only) | A = the old value | 0 mouse speed 1-4, 1 alert (beep) volume 0-15 (0 silent), 2 key repeat delay in 10 ms ticks (0 = no repeat; default 40), 3 key repeat interval in ticks (default 5), (0.18) 4 the sound volume 0-15: Lau's master volume, volume x 17 (default 8; 0.17 used setting 1 for it), (0.24) 5 the screen saver's delay in seconds (0 = off, default 300; Settings offers 0, 60, 300, 600; the Desktop reads it), 6 the seconds since the last input (read only in practice; writing it is a test aid): see "Idle time and the screen saver". A held key (not a modifier) repeats as further down events |
| $88 | win_title | A = own window, X, Y = string | - | A new title (31 characters) |
| $89 | ws_pointer | A = 0 arrow, 1 drag (a document), 2 crosshair, 3 column resize, 4 row resize (0.13; hot spot at the centre) | - | The pointer's shape (back to the arrow when the task exits or the window system ends) |
| $8A | ws_mouse | A = window ($FF: none), X, Y = 10-byte buffer | A = buttons, X = the window under the pointer ($FF: none) | The pointer now, without waiting for an event: {i16 x, i16 y on the screen, i16 x, i16 y relative to the content of window A (any program's; with $FF the screen position again), u16 buttons (bit 0 left, 1 right, 2 middle)}. X is the top-most window there as win_at gives it ($FF also for the menu bar, and without the window system). Window A must exist (EINVAL); without the window system only $FF is allowed |
| $8B | ws_hold | A = 1 hold, 0 release | - | (Added after 0.12.) While a program draws one change in several win_draw calls (a scroll and the rows that come in), the compositor waits for it (at most 5 ticks), so the screen never shows the change half done; the release repaints at once. Released at the program's exit. Windows drawn on the screen directly (see Direct drawing) do not need it |
| $8C | win_mstate | A = own window, X = menu \| item << 8, Y = MS_CHECK 1 \| MS_DIM 2 | - | (0.13) The item's state byte becomes MS_STATE \| Y (item counting separators, as WE_MENU; menu = the index among that window's menus). EINVAL if there is no such window, menu or item, or the item does not start with a state byte. An open drop-down showing it is redrawn |
| $8D | ws_closeall | - | - | (0.13) Every window of every other task (backdrops too; not the menu bar or drop-downs) gets WE_CLOSE. The Desktop's Restart and Shut down. EINVAL without the window system |
| $8E | win_geom | A = own window, X, Y = {i16 x, i16 y, u16 width, u16 height} | - | (0.14) Moves and resizes the window: x, y its outer top-left, width, height its content (as win_open; x = $8000: it stays where it is). Kept on the screen and below the menu bar; the size at most the screen below the bar. No longer maximized. The bitmap is kept if large enough (the new area is C_BODY, as after a resize by the grip); no WE_RESIZE is sent (the program knows) |
| $8F | task_name | A = task id (0 = the caller), X, Y = string | - | (0.14) The name the menu bar shows for the task's windows (bold, after the system menus; 15 characters; "" = the default, the program's file name with only its first letter capital: "Edit"). Any task may name any other: ui_launch names what it starts after the title it was given ("Calculator", "Terminal"). EINVAL: no such task. Cleared when a task starts. (0.15) A = id \| $8000 (0: the caller) reads it instead: X, Y = a 16-byte buffer that gets the name as the bar shows it (the default one too), zero-terminated (Force quit lists the programs this way) |
| $90 | win_popup | A = own window, X, Y = {u24 items, i16 x, i16 y, u8 flags} | A = the item chosen, $FFFF none | (0.15) A pop-up menu: its top left corner just right of and below the point x, y of the window's content (x = $8000 POP_HERE: the pointer), to its left or above it where the screen ends. The items are a menu's ("item", ..., "": state bytes MS_DIM / MS_CHECK, '-' separators, a TAB before a shortcut text; at most 24, read to the end of their bank). The caller blocks until an item is chosen (A = its index, counting separators) or the menu is dismissed (A = $FFFF: Esc, a press outside it, another menu opened, F10). With the mouse: a release of any button over an item chooses it (so a right press, a drag and the release on an item works), a press outside dismisses it (and is used up); the press that opened it gives up its capture (the menu gets that button's release). From the keyboard (flags bit 0, POP_KEY: the first item highlighted): Up / Down, Home / End, a letter, Enter, Esc. A menu of the bar that was open is closed first. Interruptible by kill (the menu closes). Programs open it on a right press (WE_BUTTON with c & 2) and on the menu key ($65) or Shift+F10 (which, with Shift, reaches the program instead of opening the bar's menus). EINVAL: not the caller's window |
| $91 | spr_alloc | A = count 1-16, X = own window | A = the first sprite | (0.18) count sprites in a row (sprite 0 is in front of 1, ...), hidden, without an image, for that window (its content's coordinates; the screen's in full-screen mode). See "Sprites". ENODEV before REV $0B, EINVAL a bad count or not the caller's window, EAGAIN no such run free |
| $92 | spr_free | A = first sprite, X = count; A = $FFFF: all of the caller's | - | (0.18) EINVAL: one of them is not the caller's (then none is freed) |
| $93 | spr_set | A = count 1-16, X, Y = count entries of 10 bytes | - | (0.18) Entry: u8 sprite, u8 ctrl (Marga's CTRL: SPR_EN 1 shown, SPR_HFLIP 2, SPR_VFLIP 4, SPR_MAG 8, SPR_WIDE 16 (4 bpp), SPR_TALL 32, SPR_BPP4 64, SPR_BEHIND 128), i16 x, i16 y, u24 image, u8 pal (4 bpp: the palette bank 0-15). Every field of each sprite; all of them change together from the next frame on. Checked first, then set: EINVAL a sprite not the caller's, an image not 16-byte aligned; EFAULT an image (256 / 512 bytes at 8 bpp, 128-512 at 4 bpp) not wholly in the caller's memory; then nothing changes |
| $94 | spr_move | A = sprite, X = x, Y = y | - | (0.18) Its position only: the cheap per-frame call. (0.24) A = $8000 \| count (1-16): X, Y = count entries of 6 bytes {u8 sprite, u8 0, i16 x, i16 y}, all moved in one call (checked first: EINVAL a sprite not the caller's, EFAULT the table; then nothing moves). Before 0.24 every spr_move rebuilt all 16 records; now only the sprites it moves |
| $95 | spr_show | A = sprite, X = 1 show, 0 hide | - | (0.18) EINVAL: not the caller's, or shown without an image (never given, or its bank was freed) |
| $96 | fs_enter | A = own window, X, Y = 10-byte block | - | (0.18) Full-screen mode for that window: {u8 mode (FS_640X8 0, FS_640X4 1, FS_320X8 2), u8 flags (FS_PTR 1: the pointer shown; not in 320x180), u16 stride (a multiple of 16, at least 640 / 320 / 320, at most 4096), u16 rows (360 / 360 / 180 .. 1024), u24 base (256-byte aligned: row 0), u8 0}. rows x stride bytes from base must be the caller's memory (EFAULT). Again for the same window: a new framebuffer, mode or geometry from the next frame on (page flipping; the scroll set must still fit, else EINVAL). EAGAIN: another window is in full-screen mode; EINVAL: a bad value, a backdrop or terminal window. See "Full-screen mode" |
| $97 | fs_leave | A = own window | - | (0.18) Back to the desktop. EINVAL: not in full-screen mode |
| $98 | fs_scroll | X, Y = 14-byte block | - | (0.18) Marga's scroll registers for the full-screen program (REV $0B, else ENODEV): {u16 x, u16 y (the first set: pixels skipped, the row on line 0), u16 x2, u16 y2 (the second set, from the split line), u16 vheight (rows of the virtual bitmap, 0 = no vertical wrap), u16 split line (1-359, even in 320x180), u8 ctrl (FSC_HWRAP 1: a row is a ring of stride bytes, FSC_SPLIT 2), u8 0}; all taken together at the next vertical blank. EINVAL: not the full-screen program, or Marga could read outside the framebuffer (every row and byte is checked) |
| $99 | fs_raster | A = count 0-16, X, Y = count entries of 6 bytes | - | (0.18) The raster table (REV $09, else ENODEV): {u16 line (1-359; with the split on, the split line or later), u8 index, u8 red, green, blue}, lines ascending: from that line on the entry has that colour; every frame starts with the palette's own colours. 0: off. EINVAL: not the full-screen program, or a bad line |
| $9A | pal_set | A = first \| count << 8 (count 0 = 256), X, Y = count x 3 bytes red, green, blue | - | (0.18) Several entries in one call, each by the rules of ws_palette; EAGAIN (nothing set) if one of them is another program's; EINVAL past 255 |
| $9B | pal_alloc | A = count 1-240, X = the first entry wanted ($FFFF: any) | A = the first entry | (0.18) count entries in a row that nobody holds become the caller's, with their system colours (nothing changes until it sets them). With $FFFF the kernel chooses: first in 76-113 and 136-175 (no desktop icon or UI colour uses them), then from 16 up. A = 0: every entry of the caller goes back. EAGAIN: no such run |
| $9C | draw_list | A = window \| count << 8 (1-128), X, Y = count records of 20 bytes | A = records drawn | (0.18) Many blits in one call, run by Ali as one command list (REV $09; started one by one on REV $08, drawn by the CPU before), returning at once. See "Draw lists". EINVAL a bad window, count or op, more than 460,800 pixels; EFAULT the records or a source not wholly in the caller's memory; then nothing is drawn |
| $9D | list_wait | A = 0 wait, 1 ask | A = 1 while the caller's list runs | (0.18) Waiting (or an answer of 0) also makes the CPU see what Ali wrote (CACHE_FLUSH; (0.30) also while the window system does not run, for fill_runs) |
| $9E | frame | - | A = the frame counter | (0.18) NV_FRAME: + 1 at every vertical blank since the start, wraps at 65536 (REV $09); before REV $09 the vertical blanks waited for (vsync) |
| $9F | win_vbl | A = own window, X = 1 on, 0 off | - | (0.18) WE_VBL (16) at every vertical blank while the window's event queue is empty, for event-loop programs that draw once a frame. ENODEV before REV $09 |
| $A0 | win_front | A = own window | - | (BASIC 2.0) The window comes back if minimized, is raised to the top of its class and gets the keyboard focus (with a WF_MODAL dialog of its program over it, as the Windows menu does). For a program that must show a window again by itself: the sprites of a window show only while it has the focus, and a full-screen window shows its screen only then (BASIC's SCREEN, CONT and the end of INPUT use it). EINVAL: not the caller's window |
| $A1 | sheet_new | X, Y = {u24 address, u8 0, u16 stride, u16 width, u16 height} | A = the sheet (1-32) | (0.19) Registers a sheet: width x height 8 bpp pixels from the address, rows stride bytes apart, all of it the caller's own memory (its window, its code bank, banks it allocated, across consecutive banks it owns; not the kernel's, another program's or a shared bank: EFAULT). Checked once here; sheet_draw's records then name the sheet and a rectangle in it. EINVAL: width 0 or above 4096, height 0 or above 1024, a stride below the width; EAGAIN: 32 sheets exist (all programs together), or the rows of all sheets would pass 4096. See "Sheets" |
| $A2 | sheet_free | A = sheet, $FFFF: every sheet of the caller's | - | (0.19) The caller's running list (draw_list's or sheet_draw's) is stopped first (Ali's ABORT). EINVAL: not the caller's sheet. A sheet also goes when the program frees a bank it lies in (bank_free) and when the program ends |
| $A3 | sheet_draw | A = window \| count << 8 (1-128), X, Y = count records of 16 bytes | A = records drawn | (0.19) Copies and keyed copies from the caller's sheets, and fills, as one of Ali's command lists: the targets, the clipping, the revisions and the waiting of draw_list, at a fraction of its cost (the kernel only compares a record's numbers with the sheet's size). See "Sheets". EINVAL: a bad window, count or op, a sheet not the caller's, sx + w or sy + h past the sheet, more than 460,800 pixels; EFAULT: the records not wholly in the caller's memory; then nothing is drawn |
| $A4 | fill_runs | A = count (0-2688), X, Y = 10-byte block {u24 page, u8 0, u16 size, u24 runs, u8 0} | A = count | (0.30) Many horizontal runs, each of one colour, filled by Ali in one call: run k is 4 bytes {u16 offset, u8 colour, u8 width 0-255} and fills width bytes from page + offset. The page (size bytes, 0 = 65,536) must be the caller's own memory (its full-screen framebuffer, banks it allocated, its window: Ali writes past FREDDIE II), and every run must end inside it (offset + width <= size). The page is checked once, each run with one compare; returns when the last runs are started, while Ali still fills (list_wait, vsync or the next list call wait for it; the runs' memory may be reused at once: the kernel has copied them). See "Fill runs". EINVAL count above 2688, flags not 0, a run past the page (X = its index: the runs before it may be drawn, none after it); EFAULT the page not wholly the caller's own memory, the block or the runs not readable; ENOMEM no bank for the kernel's list (taken at the first call); ENODEV before REV $09 or with the blitter turned off (ws_config bit 0): fill by the CPU then (hgame does). The window system need not run |
| $A5 | uptime_us | - | A = microseconds since reset, bits 0-15, X = bits 16-31 | (0.30) The system block's free-running microsecond counter (UPTIME, $00:DE18), which tasks cannot read themselves (the I/O page is the kernel's). Wraps after 71.6 minutes. For timing: one call costs about 40 us (the syscall's own entry and return), uptime ($04) steps 10 ms |

Any other number returns ENOSYS.

**Paths.** FAT paths, case-insensitive, long names allowed (spaces, punctuation; the I/O
processor's FatFs uses code page 437). A path that does not start with `/` is relative
to the task's current directory (chdir; a new task inherits its parent's). The kernel
turns every path into an absolute one and resolves `.`, `..` and repeated `/` before the
I/O processor sees it (FatFs runs without relative paths). The result must fit in 127
characters (the I/O processor's limit), else EINVAL. The I/O processor serves one request at a time. A task that makes
a file call blocks until the answer arrives; the other tasks keep running.

**The PC volume** (0.20, the PC link). With the PC gateway connected, the I/O processor shows
one folder of the PC as a second volume: a path whose first four characters are `/PC:` (any
case), followed by the end or `/`, is on it; `/PC:` alone is its root. The kernel treats `:`
as a normal character (`..` from `/PC:` gives `/`). On the PC volume:

- Every file call works as on the card (open in all modes, read, write, seek, close, stat,
  readdir, mkdir, delete, rename inside the volume, spawn and load), with the same 4 handles
  (a handle can be a card file or a PC file) and the same error codes ($44 no file, $45 no
  path, $46 bad name, $47 denied: also anything that would leave the shared folder and a
  folder that is not empty, $48 exists, $52 too many open files, $41 another I/O error).
- Names are looked up ignoring case; new files get the case given. Names starting with `.`
  are not listed. readdir lists by name (the gateway sorts).
- readdir of `/` (the card's root, exactly "/") gives one more entry at the end while the
  volume is there: a folder named `PC:` (size 0, attribute $10); `skip` counts it like any
  other entry.
- stat of `/PC:` (its root) answers size 0, attribute $10 and, as its time, the PC's
  **current** local time (FAT format, 2-second steps): this is how programs learn the PC's
  clock (see time_set, and ui_clkpc in the controls library). stat of anything else on it:
  the PC file's size, attribute ($10 folder, $01 read-only, else $20) and modification time.
- When the volume is not there (no gateway, or one without the file service), every call on a
  `/PC:` path fails at once with $C7. If the link drops, a call in progress fails with $C8
  (within about 3 s), and later read, write and seek on a handle opened on the PC fail with
  $C8; close frees such a handle (OK). sync (`SYS_SYNC`) also closes the PC's files.
- classic_mount of a `/PC:` path: $C7 without the volume, $C2 with it (not in this step: copy
  the image to the card).
- Speed: about 100 KB/s to read and 55 KB/s to write, a few ms for each call (the card: about
  170 and 100 KB/s). (0.21) While the I/O processor serves a long call (on the PC or the card),
  key and mouse events keep coming: other programs keep working. A program that copies large
  files should do it in pieces and show its progress (the controls library: ui_cptree in
  pieces of 16 KB, ui_cpcb, the progress window ui_cpwin).
- (0.21) **Unfinished files:** a file opened with mode 2 (create) is written under a temporary
  name; at close the gateway gives it its name in one step. Until then an older file of that
  name stays as it was (stat and readdir show the old one, or none). If the link drops, the
  board is reset or the gateway stops while the file is open, the temporary file is deleted
  and the older file stays. Modes 1 and 3 write in place.

**The internet** (0.22, the PC link step 2; `Docs/04-pc-link.md`, "Channels 4 and 5"). With the
gateway on a PC connected (and not started with `--no-net`), a **URL is a path**:

- `http://...`, `https://...`, `ftp://...` open as **read-only files** with the normal calls:
  open (mode 0; another mode: $47), stat (size: the server's size if it gave one, else 0;
  attribute $21; the time: the PC's clock now), read (it waits until the length asked for has
  come or the file ended: fewer bytes = the end, as with any file), close. seek: $C2. write,
  delete, mkdir, rename: $47; readdir, spawn: $C2. An `ftp://` URL that ends with `/` reads as
  the folder's listing (text, one name per line). A stat and then an open of the same URL
  within 15 s make one request (the shell's `cp` and `get` do this).
- `tcp://host:port` and `tls://host:port` (TLS done by the PC) open a **connection**: open
  waits until it is connected or failed (at most about 20 s); then **read never waits**: it
  gives the bytes that have come, up to the length asked for (0 = none yet), and $D0 once the
  other end has closed and everything was read; **write never waits**: it takes what fits
  (perhaps 0 bytes: try again a little later) and returns that count. seek, stat: $C2. close
  ends the connection. There is no separate status call: a read tells it (bytes, 0, or an
  error).
- **Paths.** The kernel passes a path that starts with letters followed by `://` on as it is:
  no current folder in front, no `.`/`..`/`//` handling. It must fit in 127 characters with its
  scheme.
- **Handles.** URLs and connections have their own 4 handles, **4 to 7** (open returns them),
  so they never take a file's handle (0-3). They are closed when the program ends.
- **Waiting without polling.** When something new happens on a connection (bytes came, it
  ended, it failed) and the program has read from it since the last time, the program's first
  window (the lowest window number it owns) gets **WE_NET (17)**, a = the bit mask of its
  handles with news (bit n = handle n). A program without windows polls (read, then sleep).
  An open or read that waits for the internet does not hold up other programs' file calls.
- **Errors** (also on handles): $C7 no PC link, $C8 the link was lost, $CA no such service (an
  older gateway, or `--no-net`; an older firmware answers $46 bad name), $CB bad address, $CC
  name not found, $CD refused or unreachable (also an FTP login refused or a missing FTP
  file), $CE timeout, $CF HTTP status 400 or more (**open and stat return the status in X**,
  e.g. 404), $D0 the connection was closed, $D1 TLS failed, $D2 too many connections on the
  PC, $D3 another network error, $52 all four stream handles in use. `user/horizon.inc` names
  them (E_NOSVC ...).
- Programs on the Atari816 can reach whatever the PC can reach, including the home network.

**Printing, Run in Atari and the folder disk (0.23).** The PC link's step 3. The kernel passes
these paths on like any other (`:` is a normal character; they start with `/`); nothing new in
the kernel.

- **Printing: `/PRN:NAME`.** OPEN (any case for `PRN`; any mode counts as "create") gives a
  normal file handle (0-3): a **print job**. WRITE (also READ and SEEK) works as on any card
  file; CLOSE finishes the job (so does the kernel's close at a program's end or crash). The I/O
  processor writes it as `/Printouts/YYYY-MM-DD HH.MM.SS NAME.txt` (its clock: the time
  SYS_TIME gave, as for file dates; `/Printouts` is made if missing). NAME is the text after
  `/PRN:`, cut to 24 characters, `\ / : * ? " < > |` and bytes below 32 made `_`, blanks and
  dots at both ends removed (empty: `Job`); when that name is taken: `... NAME 2.txt`, `3`, ...
  up to 99. While the job is open its file has a `.` in front of its name
  (`/Printouts/.2026-11-18 15.30.12 Edit.txt`); CLOSE gives it its name, so a job is complete
  when it appears. Programs that list `/Printouts` leave out names starting with `.`. Horizon's
  programs use their own name as NAME (`Edit`, `Write`, `Sheet`, `BASIC`, `Shell`, `Files`);
  the classic Atari's jobs are named `Atari`.
- **What a job holds:** plain text, LF ($0A) line ends (CR LF is accepted), FF ($0C) starts a
  new page, Latin-1 / ASCII. Lines longer than about 80 characters are wrapped on the PC side;
  there is no other formatting.
- **The classic Atari's printer (P:)**: the I/O processor answers the Atari's printer; what it
  prints becomes a job `... Atari.txt` (ATASCII turned into text: $9B a line end, inverse video
  as normal characters, graphics characters as look-alikes). The job ends after 3 s without
  data, or when the classic machine is frozen or cold booted.
- **STAT of exactly `/PRN:`**: size = the number of print jobs finished since the I/O processor
  started (both kinds), attribute $10, time = now. A program that waits for new jobs asks this
  (cheap) and reads `/Printouts` only when the number changed (the Desktop, Printer). Other
  calls on `/PRN:...` paths (READDIR, DELETE, MKDIR, RENAME, LOAD, classic_mount, STAT of
  `/PRN:NAME`): $C2.
- **STAT of exactly `/PC:`** answers, as its size, the gateway's services: bit 0 PCS_FILES (the
  PC volume), 1 PCS_DEV (developer), 2 PCS_NET (connections), 3 PCS_FETCH (URLs), 4 PCS_PRINT
  (it makes PDFs, below). (Before 0.23 the size was 0.)
- **PDF on the PC:** a file created (mode 2) as `/PC:/Printouts/NAME.pdf` whose content starts
  with the 13 bytes ESC `A816PRINT 1` LF (`1B 41 38 31 36 50 52 49 4E 54 20 31 0A`), then the
  lines `title=TEXT` LF, `date=YYYY-MM-DD HH:MM` LF, an empty line (LF), then the job's text,
  is turned into a PDF (A4, Courier) by the gateway when it is closed. `/SYSTEM/PRINTD.PRG
  PATH` does this for one job (exit code 0 sent, 1 an error, 2 no PC or no PCS_PRINT); the
  Desktop runs it for every new job when the PC has PCS_PRINT, and Printer's "Send to PC".
- **Run in Atari: classic_mount kind 4 (CK_BASRUN).** The path is a BASIC program on the card:
  a text listing (LF or CR LF lines, or the Atari's $9B; any extension, normally .BAS or .LST)
  or an Atari BASIC tokenised SAVE file (the I/O processor tells them apart). It becomes the
  virtual boot disk on D1:, in place of D1: and the executable, exactly like an executable:
  the answer is **2** (the kernel records it as item 4, "executable"; classic_query and the
  Atari panel show it as the program). classic_boot afterwards cold boots with Atari BASIC on;
  a small boot program types the program in and RUNs it (a last `RUN` line of the listing is left out: the loader types RUN itself). A cartridge must be ejected first (Atari BASIC is needed): ulib `atari_run` does. Errors as for kind 2: $44 no file,
  $C4 not a valid program (empty, or larger than 96 KB). ulib `atari_run` (the shell's `run`,
  Files' and the Desktop's "Run in Atari") uses it for `.BAS` and `.LST`.
- **The folder disk: classic_mount kind 5 (CK_FOLDER)**, A = 5 \| slot << 8 (slot 0-3 =
  D1:-D4:). The path is a folder on the card (made if missing). That drive then shows the folder
  to the classic Atari as an Atari DOS 2.0S single-density disk built from the folder's files;
  what the Atari writes is copied back into the folder. The answer is **1** (the kernel records
  the folder's path as the drive's). Mounting the same folder on the same drive again is a
  **refresh**: the Atari's changes not yet saved are saved first, then the disk is built again
  from the folder. classic_eject kind 1 of that drive saves the changes first, then ejects.
  Only one drive can be the folder disk: mounting a folder on another drive moves it (eject the
  old drive first, so the kernel's record of it goes too: the Desktop does). The I/O processor
  keeps it in /atari.ini (`folder=PATH`, `folderdrive=N`): mounted again at power-on, forgotten
  at eject (a restart of Horizon forgets the kernel's record: classic_query then says nothing
  for that drive, STAT still answers).
  Which files show: names that fit Atari DOS 8.3 (1-8 letters or digits, the first a letter,
  optionally a dot and 1-3 letters or digits; any case on the card, shown in upper case), at
  most 64 files in name order; a file needs max(1, ceil(size / 125)) sectors and all of them
  together at most 707 (in name order: a file that does not fit is left out and the next ones
  are tried); folders inside are ignored. A file left out is not shown and never changed or
  deleted by the Atari.
- **STAT of exactly `/D1:` .. `/D4:`**: for the folder disk's drive: size bits 0-7 = the files
  shown, bits 8-15 = the files of the folder left out (a bad name, too many, too big), bits
  16-31 = the free sectors on the disk; attribute $10 \| FD_SAVING (bit 0: the Atari's changes
  wait to be saved into the folder); time = when the disk was last built or saved. Any other
  drive: $44.

**File handles.** The I/O processor has 4 file handles (and, from 0.22, 4 stream handles) for the whole system. The kernel records
which task owns each one. A task can only use its own handles, and they are closed when it
exits.

## Samples (Lau, 0.17)

Lau plays eight voices of signed 8- or 16-bit PCM from RAM at the HDMI audio rate, 48 kHz,
without interpolation (Docs/02-register-spec.md, "Lau"). Horizon gives programs four calls
($68-$6B) and keeps these rules:

- **Memory.** The sample is read by the hardware while it plays, from the physical memory the
  range had when sample_play checked it. The program must keep it there and unchanged as
  long as the voice plays (writing it while it plays is allowed and heard: streaming into a
  loop). When the program frees a bank (bank_free), its voices that read from that bank stop
  first; when it ends (exit, kill, a crash) all its voices stop before its memory is freed. A
  voice that ends by itself (no loop) stays the program's for sample_stop / sample_set until
  another start takes it.
- **Ownership.** Each voice remembers the task that started it. A program cannot stop, change
  or take another task's playing voice (EAGAIN / EINVAL); SP_ANY never takes another task's
  playing voice.
- **Volume.** Lau's master volume follows the sound volume setting ((0.18) setting 4, Settings'
  "Sound volume"; in 0.17 it was setting 1, the alert volume): volume x 17 (0 silent, the default 8 gives 136 of 255). One voice at volume 255
  reaches about a quarter of full scale at the default; louder sums are clipped.
- **The classic machine.** When it is shown (F12, classic_show, classic_boot) every voice
  stops, as POKEY is silenced; (0.26) except the voices started with SPF_KEEP (music): they
  play on, mixed with the classic Atari's sound.
- **No Lau** (REV < $0A): every sample call returns ENODEV. Programs fall back to POKEY
  (sound_write); the alert chime is always POKEY's.

```
spb:    .faraddr sample          ; address (a label in the program: its code bank)
        .faraddr 8000            ; length: 8000 samples
        .faraddr 0               ; loop start (unused)
        .word   $1555            ; 16 kHz
        .byte   200, 200         ; left, right
        .byte   0                ; 8-bit, once
        .byte   SP_ANY, 0        ; any voice
        ...
        ptr     spb
        sys     SYS_SPLAY        ; A = the voice, or C set: ENODEV -> use POKEY
```

## Music (0.26)

Horizon plays ProTracker modules and WAV files on Lau, steadily, whatever the other programs
do. (0.27) The same engine plays Standard MIDI Files (.MID, formats 0 and 1, General MIDI) on
the OPL2 (REV $0C; opl_write, $6D): nine voices, the drums of channel 10 as FM patches, the
instruments built in or from a WOPL bank file /SYSTEM/OPL2.WOPL (versions 1 to 3, the first
two-operator pair of each instrument). While it plays a MIDI song the engine owns the OPL2;
it releases it when the song stops or ends. Three parts:

- **The music timer** (`sample_timer`, $6C): TIMER1 sends its owner's port a message every
  period (microseconds). A task at **priority 0** that waits in `recv` on that port runs
  within a fraction of a millisecond of each period (the kernel is never preempted, but its
  long jobs let interrupts in: the compositor between lines, file transfers wait for the I/O
  processor with interrupts on). Measured in emu816 (the board's timing): the ticks of a
  module come 1.6-2.3 ms after the first one's phase with a spread (jitter) of 0.35 ms while
  eight CPU-bound programs run, and of 0.8 ms during a 1 MB file copy; none is lost. The
  kernel's longest jobs with interrupts off still delay a tick: a program being loaded
  (relocated), the text console scrolling (the shell printing a long listing): up to about
  8-10 ms then, never lost (the count catches up). In Music's Desktop session (emu816), with Edit started
  and typed in while the music plays, every tick but one came within 0.8 ms of its place; one
  came 4.8 ms late while Edit was being loaded. A program never runs code in
  interrupts.
- **The engine**, `/SYSTEM/MUSICD.PRG` (user/musicd.s): spawned at priority 0 with the
  arguments `-p PORT` (a port of the caller's), it loads a file (a path on the card, `/PC:`
  or an `http://`, `https://`, `ftp://` URL), plays it and answers port messages: play,
  pause, stop, seek, volume, separation, loop, reading the module's header and patterns, quit
  (user/music.inc has the messages). It sends its status (state, order, row, pattern, time,
  the level of every channel) after every tick. It ends with its parent: a program that
  started it and ends (exit, kill, crash) takes the music with it within a second. From the
  shell, `musicd [-l] FILE` plays a file once (or again and again) and returns at its end.
  It needs Lau (REV $0A): without it, it says so (shell) or answers MST_ERROR with ENODEV.
  The Music Player program (`/BIN/MUSIC.PRG`; "Music" before 0.27) is its window. It is a
  single-instance program; a file opened from Files while it runs reaches it through
  `/SYSTEM/OPEN.REQ` (two lines: the program's path and the argument), which the controls
  library's `ui_launch` writes when the kernel answers ERUNNING to a spawn with an argument,
  and Music Player reads (then deletes).
- **The replayer library**, user/modplay.s (build/modplay.o; API in user/modplay.inc; the
  SDK's sound reference): the engine's player, for programs that play a module themselves (a
  game: `mp_tick` from its own timer task or frame loop).

**Voices.** A module of N channels takes voices 8 - N .. 7 (4 channels: 4-7), so programs'
sound effects (SP_ANY takes the lowest free voice) never meet the music; a voice another
program took makes that channel take any free one. WAV: voice 7 (mono) or 6 and 7. The
music's voices are started with SPF_KEEP: they play on while the classic Atari is shown.
Nothing ties sound to the keyboard focus: the music plays on while another window is in front
(the main use: music while working in Edit), while the player is minimised, during copies.

**Loops on Lau.** A MOD sample plays from its start to its loop end and then repeats its loop:
exactly Lau's LEN and LOOP (the part after the loop end is never played, as in most players).
The one case Lau cannot start directly is a sample offset (9xx) inside a loop (the loop start
would lie before the start): the piece to the loop end and then the loop (2 KB at most) are
copied into a small buffer and played from there with its own loop; longer ones start at the
loop start. (A Lau improvement that would make this exact and free: a start position
register, KEYON starting the voice at that position instead of 0.)

**Pause** sets the voices' pitch and volume to 0 (they keep their place); resume writes them
back.

**What it costs** (emu816, the board's timing): about 0.9 ms of CPU a tick in all at 125 BPM
(50 ticks a second: 4.5 % of the CPU), of which the replayer's own work is about 0.3 ms and
the wake-up through the kernel (interrupt, message, task switch, recv) about 0.6 ms; the
level meters for a client (Music Player) add about 0.5 ms every second tick (0.25 ms a tick on
average), plus one status message (send) a tick.

## The games round (0.18)

Marga, Ali and Lau read and write memory by themselves, past FREDDIE II's protection. So every
address a program hands over for them is checked against the calling program's own memory (its
window, its code bank, banks it allocated; a range may run across consecutive banks it owns, not
into shared banks), and whatever a program holds goes back when it ends (exit, kill, crash), and
when it frees the memory involved. These calls live in the kernel's second code segment
(`kernel/k2*.s`).

### Frame sync

`vsync` waits for Marga's VBLANK interrupt (REV $09+) and returns NV_FRAME; `frame` ($9E) reads
it without waiting. A game loop: `vsync`, read input (`input_poll` / `win_event` polling,
`joystick`), update, draw (a draw list with LS_VBL on its first record is the tear-free way),
repeat. A difference of more than 1 between two `vsync` results is a missed frame. An event-loop
program can ask for WE_VBL instead (`win_vbl`). Before REV $09 `vsync` keeps its timer fallback.

### Palette entries

The system palette (0-15 UI, 16-231 the cube, 232-255 greys) is the same for every program. A
program takes entries 16-255 for colours of its own with `pal_alloc` (entries nobody holds,
chosen by the kernel, or a given place) or by setting an entry nobody holds (`ws_palette`,
`pal_set`). **An entry a program holds shows its colour while one of its windows has the
keyboard focus, and the system colour otherwise**; it goes back to the system when the program
ends or calls `pal_alloc 0`. So the program in front always looks as it means to, and no
program's own colours change what another program shows while that one is in front (a program
in the background may look different meanwhile; games pause there anyway). Two programs never
hold the same entry (EAGAIN). A program that draws with fixed system colours and wants to keep
them right also while another program is in front can claim those entries with `pal_alloc`
at their place (they keep their system colours; the kernel then gives other programs other
entries). Entries 0-15 stay global. In full-screen mode the program has a whole palette of its
own (below).

### Sprites

Marga's 16 sprites (REV $0B; ENODEV before): `spr_alloc` takes count sprites in a row for one of
the caller's windows (lower numbers are in front), `spr_set` gives each its image, position,
size, flips, magnification, BEHIND and 4 bpp palette bank (a table: many sprites in one call,
all changing together), `spr_move` moves one (the cheap call; 0.24: or several in one call), `spr_show` shows or hides one,
`spr_free` gives them back. Positions are relative to the window's content (to the screen in
full-screen mode). Images: 8 bpp 16x16 (256 bytes) or 16x32 (512); 4 bpp 16x16 (128), 32x16,
16x32 (256), 32x32 (512); rows top to bottom; colour 0 transparent; 16-byte aligned; in the
caller's memory (EFAULT otherwise) and left there while shown.

**The rule for windows:** hardware sprites cannot be cut to a window's shape, so a window's
sprites are shown only while that window has the keyboard focus, nothing lies over its content
(no other window, menu or pop-up menu) and the desktop is on the screen, and only those that
lie wholly inside its content; the others are hidden until that holds again. Their screen
position follows the window (it is brought up to date after every repaint, so a window that
moves takes them along). The mouse pointer stays in front of every sprite. Changes are written
to Marga in the vertical blank (NV_SPR_COMMIT), so a frame never shows half of a change.
A program's sprites are freed when it ends or closes their window; a sprite whose image lies
in a bank the program frees loses its image (hidden; `spr_show` then gives EINVAL until
`spr_set` gives a new one).

### Idle time and the screen saver (0.24)

The kernel counts the **seconds without input** (`setting` 6): every key event (also F12),
every mouse event (a move, a button, the wheel, whatever program gets it, and also while a
long I/O request runs: the step-22 input layer brings them) and every `joystick` read that finds
a direction or a trigger pressed set it to 0. It stays 0 while the classic Atari is shown, while
a program is in full-screen mode (in front or in the background), while a mouse button is held
(a drag) and while a menu of the bar or a pop-up menu is open. It stops at 65535.

The **Desktop** compares it every second with `setting` 5 (the delay in seconds, 0 = off; the
kernel starts with 300, Settings sets it from /SYSTEM/CONFIG `saver=`) and starts
`/SYSTEM/SAVER.PRG` (detached) when the delay is reached, once until the next input. The saver
is an ordinary program: a small plain window put in full-screen mode (320 x 180, a black
framebuffer of one bank), Marga's 16 sprites drifting on it (REV $0B; without sprites, or when
`spr_alloc` fails because another program holds them, one block drawn by the CPU at a new place
once a second), and the end of the program brings the desktop back unchanged (the kernel's
way out of full-screen mode: the window closes, the focus goes back to the window below). It
ends at a key or a button pressed (it waits up to half a second for its release, so neither
reaches another program), the wheel, the pointer moved by more than 6 pixels, a joystick change
or the loss of the focus (F12 shows the classic Atari at once; Alt+Tab; another program's new
window). Because of the full-screen rule above, it never starts over a full-screen game or the
classic Atari, and the kernel needs nothing else for it. A program may read setting 6 (a
program of its own that dims or pauses when nobody is there); it should not write it.

### Full-screen mode

`fs_enter` (A = one of the caller's windows) gives the kernel a framebuffer in the program's
own memory and a mode: 640x360 at 8 bpp, 640x360 at 4 bpp (entries 0-15; x in the scroll
registers counts pixels, a draw list's x bytes) or 320x180 at 8 bpp (shown at 4x). While that
window has the keyboard focus, Marga shows that framebuffer instead of the desktop, with:

- the program's own palette: all 256 entries (`ws_palette`, `pal_set`), starting as the
  palette shown when it entered;
- its scroll registers (`fs_scroll`, REV $0B): pixel offsets, horizontal wrap (a row is a
  ring of stride bytes), vertical wrap at `vheight`, a split line with a second set (a fixed
  status panel above or below a scrolling playfield). The whole range Marga can read with
  these values (every row of both sets, wrap and split included, and every byte of each line)
  is checked against the framebuffer that `fs_enter` checked;
- its sprites in screen coordinates (in 320x180 pixels in that mode);
- its raster table (`fs_raster`, REV $09): up to 16 palette changes at given lines, written
  by the kernel's LINE interrupt handler in the horizontal blank (it takes the interrupt one
  line early and waits for the line to begin). Programs never run code in interrupts. A change
  is exact from its line on while the CPU runs a program or idles; kernel work with
  interrupts masked (a file read, a CPU blit) can delay it. With the split on, raster lines
  start at the split line (the split takes NV_LINE_CMP at the start of the frame).
- the pointer if FS_PTR is set (never in 320x180).

Keys, buttons, motion (with a button held, or always with WF_HOVER) and the wheel go to that
window as usual events, with the pointer's position on the screen (halved in 320x180). The menu
bar is not shown and the window manager keeps only its way out:

- **Alt+Tab, Alt+Esc** minimize the full-screen window: the desktop comes back as it was;
- **F12** does the same, then shows the classic machine as always;
- **Alt+F4** sends WE_CLOSE;
- whenever the window loses the focus otherwise (another program's window comes up, the
  program's own dialog, the Windows menu) the desktop comes back too;
- the program's end (exit, kill, crash), `fs_leave`, closing the window and freeing a bank
  the framebuffer lies in end full-screen mode.

So the user can never be trapped: those keys work whatever the program does. On leaving, the
program gets WE_UNFOCUS (it should pause); when its window gets the focus again (Alt+Tab, the
Windows menu, a click on its window) its screen is shown again exactly as it was (the
framebuffer is its own memory, untouched) and it gets WE_FOCUS.

**What is saved and restored on a switch.** Nothing of the desktop needs saving: its
framebuffer is untouched (the compositor keeps it current meanwhile), and leaving restores
mode 0, NV_BASE, NV_STRIDE 1024, the scroll registers at their reset values, NV_LINE_CMP 511
(raster interrupt off), the system palette with the front program's entries, the desktop's
sprites, the pointer, then repaints. The kernel keeps of the full-screen program: mode, flags,
framebuffer address, stride, rows, the scroll set, its 256-entry palette, its raster table and
its sprites; entering again writes them back. One program at a time is in full-screen mode
(another gets EAGAIN, also while the first one is in the background).

Drawing: the framebuffer is the program's own memory, so the CPU may draw into it directly;
Ali draws into it through draw lists (below), with coordinates in the framebuffer (all of its
rows and its whole stride, so the parts off the screen can be prepared before they scroll in).


### Memory a full-screen program could get back (a note for later; not done)

While a full-screen program is in front, about 1.1 MB stays allocated for screens nobody
sees: the text console's framebuffer (4 kernel banks, kept from the boot so that ws_stop
brings the console back as it was), the window system's screen (6 banks,
640x360 at 8 bpp with a stride of 1024, kept current by the compositor meanwhile) and the
Desktop's backdrop window's bitmap (6 banks: every window's bitmap is its own memory). A
game that wants 1-2 MB more (X-COM, Prince of Persia) could get them back:

- **The console's 4 banks**: not needed while the window system runs at all (ws_start to
  ws_stop). Freed at ws_start, taken again at ws_stop with the console cleared, or with its
  text kept as characters (78 x 29 x 2 bytes in a kernel bank) and drawn again. Cost: the
  kernel's screen code (screen.s) must accept "no framebuffer" (skip drawing, keep the
  cursor) and ws_stop must handle "no 4 banks free" (the console then waits, or ws_stop
  refuses). Small and self-contained: the cheapest of the three.
- **The window system's 6 banks**: freed at fs_enter, taken again (contiguous) and the
  whole desktop repainted from the window bitmaps at fs_leave and at every switch back
  (Alt+Tab, F12, a dialog). Cost: the switch is no longer instant (a full repaint, about
  0.1 s with the blitter), the compositor must skip all work while there is no screen, and
  6 contiguous banks may not be free when the program leaves (its memory fragmented the
  pool): the kernel must then keep them reserved, or leave full screen only when they are
  there, or repaint into what it can get (a second, scattered layout the compositor does
  not have). Medium.
- **The backdrop's 6 banks** (and the bitmaps of other programs' windows): the kernel
  cannot redraw them, only their programs can. It needs a protocol: an event telling a
  program that its window's bitmap was dropped (when a full-screen program enters) and
  another one asking it to draw everything again (when the desktop comes back); the
  Desktop can (it draws the backdrop from its icons), most programs cannot yet. Large: a
  new event pair, a "bitmap gone" state in the window system, and every program that
  wants to take part.

### Draw lists

`draw_list` (A = window | count << 8) takes up to 128 records of 20 bytes from the caller's
memory:

| Offset | Field |
| --- | --- |
| 0 | u8 op: LS_FILL 0, LS_COPY 1, LS_KEY 2 (pixels of colour c2 skipped), LS_EXPAND 3 (1 bpp: set bits c1, clear bits c2), LS_EXPANDK 4 (clear bits left as they are), LS_MOVE 5 (inside the target, overlap-safe) |
| 1 | u8 flags: bit 0 LS_VBL (wait for the vertical blank before this record), bits 4-6 expand's first source bit (0 = bit 7) |
| 2, 3 | u8 c1, c2 |
| 4-11 | i16 x, i16 y, u16 w, u16 h: the destination |
| 12-14 | u24 source (copy, keyed copy, expand); move: i16 sx at 12, i16 sy at 14 |
| 16 | u16 source stride (0: the width; expand: the bytes a row needs) |
| 18 | u16 0 |

Each record is checked (its whole source must be the caller's memory: EFAULT) and clipped to
the target: the window's content (on the screen itself while nothing lies over it and no
repaint over it is pending, else its bitmap, which the compositor then shows: the rule of
`win_draw`), or the full-screen framebuffer of that window. Ali then runs them as one command
list (REV $09) and the call returns at once (A = the records drawn, those clipped away left
out); without command lists the kernel starts them one by one (REV $08), without the blitter
the CPU draws them: the picture is the same. **While a list runs its sources are being read and
its target written: leave them alone until `list_wait` (or `vsync`, or the next `draw_list`,
which wait for it).** `list_wait` also makes the CPU see what Ali wrote (before reading a
framebuffer Ali drew into). A program's running list is stopped (Ali's ABORT) when it ends or
frees a bank. A call covers at most 460,800 pixels (two screens). With LS_VBL on the first
record, the blits start in the vertical blank: a frame's whole update in one syscall, tear-free.

### For BASIC (2.0)

BASIC 2.0 (BASIC.md, "Games" and "Samples") maps its statements onto these calls, a few a
frame: BASIC keeps the 16 `spr_set` entries in its window bank and `SPRITE` changes them, then
`VSYNC` gives them to the kernel in one `spr_set` (all 16: the changes of one frame together),
sends the frame's `fs_scroll` block (`SCROLL`, `PANEL`) and `fs_raster` table (`RASTER`) when
they changed, sends the frame's draw list (`PUT`, `COPY`, `FRECT`, `GCLS` in full screen; LS_VBL
on its first record) and calls `vsync`. Sprite images are made from BASIC's pictures into a bank
of its own; `SCREEN 1` / `SCREEN 2` take consecutive banks for `fs_enter` (a stride of the
width rounded to 16, 64 rows of panel below the drawing area; BASIC's drawing code writes into
it as into its window's shadow, rows that run into the next bank included); `PLAY` is
`sample_play` from BASIC's sample banks, `PALETTE` `ws_palette`, `FRAME` `frame`. On END, an
error or a break BASIC frees its sprites (`spr_free`), stops its voices and leaves the full
screen (`fs_leave`, the framebuffer kept for CONT, which calls `fs_enter` again and `win_front`).

(BASIC 2.0) A fix: `fs_raster` with A = 0 (the table off) returned EINVAL (its count test read
the flags of the `cmp #17` before it); it now turns the table off as documented.

### Sheets (0.19)

`draw_list` checks every record's source against the caller's memory, which costs about 1,300
CPU cycles a record. A **sheet** moves that check to the start: a program registers a rectangle
of its own memory holding art once (`sheet_new`: address, stride, width, height, 8 bpp), and
`sheet_draw`'s records then name the sheet and a rectangle in it. The kernel only compares
those small numbers with the sheet's size, and finds the source's address in a table of the
sheet's rows that `sheet_new` made.

| Offset | Field |
| --- | --- |
| 0 | u8 the sheet (1-32; a fill: 0, not used) |
| 1 | u8 op: SH_FILL 0, SH_COPY 1, SH_KEY 2 (pixels of the key colour skipped); + SH_VBL $80: wait for the vertical blank before this record |
| 2 | u8 the fill colour or the key colour |
| 3 | u8 0 |
| 4, 6 | u16 sx, sy: the source's top left corner in the sheet |
| 8, 10 | u16 w, h: sx + w <= its width, sy + h <= its height (else EINVAL) |
| 12, 14 | i16 x, y: the destination |

(`horizon.inc`: SH_*, SD_* offsets, SHN_* for sheet_new's block.)

Everything else is `draw_list`'s: the target is the window's content (on the screen itself while
nothing lies over it and no repaint over it is pending, else its bitmap) or its full-screen
framebuffer, each record is clipped to it (the source moves with the cut), empty and clipped-away
records are left out (A = the records drawn), a call covers at most 460,800 pixels (records up to
16 x 16 counted as 256), SH_VBL works as LS_VBL (on the first record: the whole update in the
vertical blank), and Ali runs the records as one command list (REV $09+; the call returns at
once), or the kernel starts them one by one (REV $08), or the CPU draws them (REV $07): the same
picture. **While the list runs its sources are being read and its target written** (`list_wait`,
`vsync` or the next call wait for it).

**The fast path.** A record costs about 300 CPU cycles (emulated: 21 us) when the window is drawn
on the screen directly or is in full-screen mode, the record is a copy or a keyed copy from the
same sheet and op as the record before it, and it lies wholly inside the content; others (fills,
SH_VBL, clipped records, a covered window's bitmap) take the full path, about 1,100 cycles, still
less than draw_list's. A call itself costs about 3,800 cycles (265 us), as draw_list's.

**Rules.** A sheet is the program's that made it: another program's handle is EINVAL. 32 sheets
for all programs together, at most 1024 rows each and 4096 rows in all (EAGAIN). The kernel
keeps the physical address of every row: the memory must stay the program's and in place, and
it does, since a sheet goes (and the program's running list is stopped) when the program frees
a bank the sheet lies in, calls `sheet_free`, or ends (exit, kill, crash). Writing new pixels
into a sheet is allowed at any time a list is not reading them (a sheet can be an arena drawn
into by the CPU). Fills need no sheet. There is no move, expand or stride per record: those stay
`draw_list`'s (one call a frame either way: a frame that needs both sends one `draw_list`).

```
tiles:  .faraddr art            ; sheet_new's block: 16 x 16 tiles, one under the other
        .byte   0
        .word   16, 16, 16 * 8  ; stride, width, height: 8 tiles
        ...
        ptr     tiles
        sys     SYS_SHEETNEW    ; A = the sheet
        sta     sheet
        ...                     ; a record: tile 3 at (40, 20), colour 0 left out
        .byte   1, SH_KEY, 0, 0 ; (the sheet's number in byte 0)
        .word   0, 3 * 16, 16, 16, 40, 20
```

### Fill runs (0.30)

`fill_runs` exists for programs that draw many small pieces a frame: a road made of spans, a
polygon renderer's scan lines, a voxel column's runs turned on their side. SkyRoads' road is
700-2,100 runs a frame (about 23 pixels each); as `draw_list` or `sheet_draw` fills each run
costs the kernel 1,100-1,300 CPU cycles, more than filling the run with the CPU, so the
blitter could not help. `fill_runs` checks the page once and each run with one compare, and
Ali fills them while the kernel makes the rest.

**The call.** A = the number of runs (0-2688; 0 does nothing), X, Y = the block:

| Offset | Field |
| --- | --- |
| 0 | u24 page: the address of offset 0 (any alignment) |
| 3 | u8 flags: 0, or FR_GROUPS (1): the runs pointer points at groups (below); others EINVAL |
| 4 | u16 size: the page's bytes, 1-65,535, or 0 for 65,536 |
| 6 | u24 runs (or groups): the first one |
| 9 | u8 0 |

A run (`horizon.inc`: FRR_*):

| Offset | Field |
| --- | --- |
| 0 | u16 offset: the run's first byte, from the page's start |
| 2 | u8 colour |
| 3 | u8 width: 0-255 bytes (0: nothing) |

Run k fills `page + offset .. page + offset + width - 1` with its colour. A run is a line of
bytes in memory, not a rectangle: for a framebuffer of stride S the offset of pixel (x, y)
of the page is y * S + x, and a run that passes the end of a row goes on at the start of
the next (the page has no rows of its own). Runs are drawn in order: a later run over an
earlier one wins. Wider runs: several runs, or `sheet_draw`'s fills.

**Groups** (FR_GROUPS; A = the number of groups). A group is a program's own array of runs
drawn in one colour, in its own layout, so spans prepared once (a shape's) need no copying
into run records each frame (`horizon.inc`: FRG_*):

| Offset | Field |
| --- | --- |
| 0 | u24 its elements: the first one |
| 3 | u8 the colour of all its runs |
| 4 | u16 the elements, 0-1024 |
| 6 | u8 stride: the bytes from one element to the next, 1-255 |
| 7 | u8 fields: bits 0-3 the place of an element's u16 offset, bits 4-7 the place of its u8 width |

Element k of a group is the run {u16 at elements + k * stride + (fields & 15), u8 at
elements + k * stride + (fields >> 4)}. The elements must be readable by the caller (not in
its window: EFAULT; the bank is checked once while the groups keep to it) and every element
must lie below offset $FF00 of that bank (EINVAL). A group whose runs would make the call's
more than 2688 ends the call there: A = the groups taken, the program sends the rest in
another call. EINVAL with X = the group's index for a group past these rules or a run of it
outside the page. (A run array of the 4-byte layout is the group {runs, colour, n, 4, $30};
SkyRoads' 5-byte spans {u16 left, u16 right, u8 width} are {spans, colour, n, 5, $40} for
the left side and $42 for the right.)

**Rules.**
- The page must lie wholly in the caller's own memory (the rule of every address Ali, Marga
  or Lau use: its window, its code bank or banks it allocated, across consecutive banks it
  owns; never the kernel's, a shared bank or another program's): EFAULT. A window's content
  is not the program's memory: in a window, use `draw_list` / `sheet_draw` (or the CPU on an
  image of its own). A program in full-screen mode passes its framebuffer (or a part of it:
  one page of a framebuffer taller than the screen).
- Every run must end inside the page (offset + width <= size). The first run that does not
  stops the call: EINVAL, X = its index (a group's: the group's); the runs before it may be
  drawn (Ali may have started on them), none after it.
- The runs (groups) must be readable by the caller (EFAULT); they are read by the kernel, so
  they may be changed as soon as the call returns. A group's elements are read while the call
  runs too: change them after the call returns, as well.
- A call takes at most 2688 runs (EINVAL above; groups: see above): more need more calls;
  each one waits for the list before it (as every list call does).
- REV $09 and later, the blitter not turned off (ws_config bit 0; the window system need not
  run); else ENODEV and nothing is drawn: the program
  fills the runs with the CPU (hgame's `hg_fill_runs` and `hg_fill_groups` do so by
  themselves). `hcc --needs rev=9` (HZ_NEEDS revision $09) makes a program that has no CPU
  path of its own refuse to start on an older board.

**How it runs.** Like `draw_list`, the call returns while Ali still fills (A = count): leave
the page alone until `list_wait`, `vsync` or the next list call, which wait for it; `list_wait`
also makes the CPU see what Ali wrote. The program's running list is stopped (Ali's ABORT)
when it ends (exit, kill, crash) or frees a bank. Inside the kernel:
- At its first call the kernel takes one bank for its lists (kept until Horizon restarts:
  ENOMEM when none is free) and writes the bytes of its 2688 Ali records that never change:
  HEIGHT 1, OP FILL, FLAGS and RFLAGS 0 (about 25 ms, once).
- Each run then costs two loads, one compare and five bytes written into its record (DST's
  three, WIDTH's low byte, FG): about 138 CPU cycles (9.6 us) on the board, a third of it the
  SDRAM's write stall (about 4.5 cycles a byte the CPU writes). Runs that start in the page's
  last 255 bytes take a slower exact test. A group's element costs about 150 cycles, and the
  group itself about 300 (its record read, its bank and layout compared with the group
  before): groups pay when they are long (a shape of many spans), not for two runs each.
- After every 64 runs the kernel serves the interrupts that are due (music timers, the
  frame) and, when Ali is idle, gives it the records made so far; so Ali fills while the
  kernel makes the rest. At the end it waits for the part Ali is running (short while the
  runs are short: Ali fills a 23-pixel run in about 70 cycles, faster than the kernel makes
  one) and starts the rest. The call is not preempted meanwhile (other tasks run after it):
  2688 runs keep the CPU about 26 ms.
- Ali's own cost for a record: about 40 cycles (reading its 24 bytes as three bursts, the
  set-up) plus the 32-bit words it writes, about 4.6 cycles each in 320 x 180 (a run that
  starts or ends inside a word writes the whole word with a mask); emu816 models this from
  the RTL (`emu/blitter.c`, `emu/tests/asm/blitruns.s`).

**What it costs**, against the other ways (emu816, board timing, 320 x 180, 2,000 runs at
scattered places: `sdk/c/game/tests/gt_runbench.c`; CPU cycles a run until the program has
the CPU again; see `sdk/docs/reference/performance.md`):

| 23-pixel runs | cycles a run |
| --- | --- |
| a C loop through a `__far` pointer | 1,700 |
| hgame's CPU path (assembly, 16-bit stores) | 610 |
| SkyRoads' unrolled assembly (a jump into 127 16-bit stores; PORTING-NOTES) | about 260 |
| one `sheet_draw` fill record each, 128 a call (`hg_fill`) | 3,400 |
| one call a run (`hg_fill` + `hg_flush`) | 10,000 |
| `fill_runs` (`hg_fill_runs`) | 140 (8- and 100-pixel runs: 138 and 175) |
| `fill_runs` with groups of 20 (`hg_fill_groups`) | 170 |
| `fill_runs` with groups of 2 | 300 |

So the kernel's floor is about 140 cycles a run on this hardware: the program still pays for
every run, about half of what a tight assembly fill of a 23-pixel run costs, and nothing for
the pixels (a 100-pixel run costs the CPU 1,550 cycles in assembly, `fill_runs` 175).

**For a later hardware revision** (not built): what is left per run is writing five bytes
of Ali's 24-byte record. A *run list* mode in Ali would take the runs where the program
keeps them: a command RUNS (BL_CTRL bit 6) with BL_DST = the page, BL_SRC_STRIDE = its
size - 1 (a bound Ali enforces: a run past it ends the list with ABORTED and BL_COUNT
telling which), BL_LIST = the first run (any address; or a group's elements with a stride
and the two field places in BL_FLAGS), BL_COUNT their number and BL_FG the colour (groups);
Ali reads 8-byte bursts (two 4-byte runs each) and fills each run at once, with no 24-byte
record and no per-record set-up. The kernel would check the page and the runs' range once a
call (the run list must be the caller's memory, as a sheet's rows are) and do
nothing per run; a run would cost the program only what it takes to write it (about 25
cycles for 4 bytes), or nothing for prepared groups, and Ali about 10 cycles plus its words.

## Window system

The desktop. While it runs, the screen is the window system's (mode 0, 640x360, 8 bpp)
and the classic machine stays frozen (F12 or classic_show shows it; F12 there brings the
desktop back unchanged).

- **Palette** (`horizon.inc` C_* names): 0-15 UI colours (C_BLACK, C_WHITE, C_DESK,
  C_DESK2, C_TITLE, C_TITLE_OFF, C_BODY, C_DARK, C_MID, C_LIGHT, C_SELECT, C_RED,
  C_YELLOW, C_GREEN, C_ORANGE, C_SHADOW), 16-231 a 6x6x6 cube (16 + 36 r + 6 g + b,
  each 0-5), 232-255 a grey ramp (8 to 238).
- **Windows**: a 1-pixel black border, a 14-line title bar with a close box, then the
  content; resizable windows (WF_RESIZE) have a 12-line bottom strip with the size grip
  at its right. Outer size: content + 2 wide; content + 17 (+ 12) high. WF_PLAIN windows
  have none of this. Every window has its own bitmap, so programs never redraw on
  exposure. Z order: backdrops, normal windows, the menu bar and its drop-downs.
- **Menu bar** (16 lines, always on top): the backdrop's menus (the Desktop's system
  menu), then the focused window's (win_menu), and the status text at the right
  (ws_status). (0.14) With a backdrop: its menus, then the kernel's **Windows** menu (every
  window, the focused one checked, minimized ones in [brackets]; choosing one restores it
  if minimized, raises it, and a dialog of its program with it), then, when a program's
  window has the focus, a thin divider, that program's name in bold (task_name) and its
  menus. With no program window in front only the system menus show. A click on the
  status text sends WE_STATUS to the backdrop. A press on a title opens its menu; releasing on an item picks it
  (WE_MENU); releasing on the title keeps the menu open until the next click.
- **Pop-up menus** (0.15): win_popup ($90) opens a menu anywhere (the controls library:
  ui_popup at the pointer, ui_popat from the keyboard); while it is open it takes the keys
  and buttons as an open menu of the bar does. Shift+F10 is passed to the program (F10
  alone opens the bar's menus).
- **Keyboard menus** (0.13): F10, or Alt pressed and released with no other key or click
  between, opens the bar's first menu with its first selectable item highlighted (again:
  closes it). Alt+letter opens the menu whose title starts with that letter (the focused
  window's menus first, then the backdrop's; with none, the key goes to the program). While
  a menu is open: Left / Right the previous / next menu, Up / Down the previous / next item
  (separators and dimmed items skipped; both wrap), Home / End, Enter chooses (WE_MENU, as a
  click), Esc, F10 or Alt alone close, a letter goes to the next item starting with it. No
  other key reaches programs then; Alt key events still go to the focused window; the mouse
  works as usual. Alt+Tab raises the bottom-most normal window (pressed again and again it
  cycles through all; a dialog of its program comes up with it; 0.14: a minimized window
  comes first, restored). Alt+F4 and ctrl+W send
  WE_CLOSE to the focused window, as its close box does. None of these keys reach programs.
- **Title bar buttons** (0.14): at the right of the title bar, minimize (every normal window
  but dialogs, WF_MODAL) and maximize (resizable ones only). **Minimize** hides the window
  (out of the z order; its bitmap is kept and still drawn into; the Windows menu, Alt+Tab or
  starting a single-instance program again brings it back). **Maximize** (also a double
  click on the title) makes the window the whole screen below the menu bar; again, or the
  restore button, gives back the geometry it had; the program gets WE_RESIZE both times. A
  maximized window is not dragged; resizing it by the grip ends the maximized state.
- **Window manager**: a click on a lower window raises it (that click is not passed on);
  a press on the top window's title bar drags it (live); the close box sends a close
  event; the grip resizes live (the new area is C_BODY; WE_RESIZE at the release); other
  presses in the top window's content, and in a backdrop, send button events (0.14: a right
  or middle press over a backdrop goes to the backdrop, which holds the press: the Desktop
  gets right clicks while another window has the focus). Keys go to
  the focused window (the top-most normal one, else the backdrop) as key events, not to
  the keyboard queue; F12 goes to the backdrop. Wheel steps go to the window under the
  pointer.
- **Terminals** (WF_TERM): a text screen of 8x12 cells (as many as the content holds: Terminal uses 76 x 24, 608 x 288),
  with the screen console's control codes: CR, LF, BS, TAB, BEL (a beep), ESC Y r c,
  ESC K, ESC E, ESC p / q, ESC f / e. Tasks attached with ws_term print there and read
  their keys from the terminal's own queue with input_read; input_claim is a no-op there,
  input_lend / input_release hand the keys between the attached tasks as on the console,
  and ctrl-C kills a borrower lent with the break flag. con_size gives the terminal's
  size. So the shell runs there unchanged.
- **Direct drawing** (added after 0.12). While no window above a window overlaps its content
  and no repaint over it is pending, win_draw draws on the screen itself, at once, instead of
  into the window's bitmap and then (a tick later) again onto the screen: one pass instead of
  two, and a WD_COPY scroll is one copy on the screen. The window's bitmap is brought up to
  date from the screen before anything needs it (the window is covered, moved or resized, or
  a repaint over it comes). Programs see no difference, except that the screen shows each op
  as it is drawn (draw with the text's paper, as the controls do, to avoid a blank moment).
  Terminals scroll the same way, and their output is drawn in bursts: one move for all the
  rows scrolled since the last repaint (ws_config bit 2 turns direct drawing off).
- A task's windows close when it exits; ws_stop (or the end of its owner) ends the window
  system. While it runs, any task may call classic_show / classic_boot (not only the
  keyboard holder).

## Video state (Marga)

A copy of what Marga, the video chip, shows, at the fixed address **$01:F000** in kernel memory (not
readable by tasks: it is for tools that read memory from outside, such as the PC link's
screenshot, `core/tools/a816_screen.py`; Marga's palette and most of its registers
cannot be read back). The kernel keeps it current at every change. Little-endian:

| Offset | Size | Contents |
| --- | --- | --- |
| 0 | 4 | Magic `HZVS` |
| 4 | 1 | Version (2; 1 before 0.30) |
| 5 | 1 | Header length (32): the palette starts there |
| 6 | 2 | Change counter: + 1 at every change except pointer moves (read it again after the rest: a different value means a torn read) |
| 8 | 1 | NV_CTRL as written (bit 0 ENABLE, 1-2 mode, 3 POINTER_EN; 0 while the classic machine is shown) |
| 9 | 3 | NV_BASE |
| 12 | 2 | NV_STRIDE |
| 14 | 1 | State: bit 0 the classic machine is shown, bit 1 the window system runs |
| 15 | 1 | The NV_CTRL value of the native screen when it is shown (the desktop or the text console) |
| 16 | 2 | PTR_X (the hot spot, 0-639) |
| 18 | 2 | PTR_Y (0-359) |
| 20 | 1 | PTR_HOT (bits 0-3 x, 4-7 y, in 2-pixel steps: the image's top left is x - 2 hx, y - 2 hy) |
| 21 | 3 | PTR_IMG: the 32x32 2 bpp image (256 bytes) |
| 24 | 3 | PTR_C1, PTR_C2, PTR_C3 |
| 27 | 1 | The shape set with ws_pointer (0 arrow, 1 drag, 2 crosshair, 3 column resize, 4 row resize) |
| 28 | 2 | The mouse buttons now |
| 30 | 2 | (version 2) SYS_REV, the hardware revision (0 in version 1) |
| 32 | 768 | The palette as written to Marga: red, green, blue of entries 0-255 (the text console sets entries 0-5 over the system palette, which the kernel loads at boot) |
| 800 | 2 | (version 2) Not 0 while a full-screen program's screen is on Marga (its scroll set below is then what Marga uses, REV $0B+) |
| 802 | 14 | (version 2) That program's scroll set as fs_scroll took it: u16 x, y, x2, y2, vheight, split line, u8 ctrl (FSC_*), u8 0 |

(0.30) Version 2 adds the revision and the full-screen scroll set (the kernel keeps its own
variables there, so the copy costs nothing), so a screenshot of a scrolled full-screen
program needs no search of the kernel's code; the header is still 32 bytes and the palette
still at 32, so a reader of version 1 works unchanged. `core/tools/a816_screen.py` uses the
block's scroll set from version 2 on and the code search before it.

## Keyboard

One task holds the keyboard at a time. Key events go into a 128-entry kernel queue.

**Lending.** The holder can lend the keyboard with input_lend, typically to a foreground
child. The queue stays and KB_ROUTE stays 0, so keys typed meanwhile are kept as typeahead.
Lending nests: when a borrower releases the keyboard or exits, it goes back to whoever lent
it to that borrower. INIT holds the keyboard and lends it to the shell; the shell lends it
to its foreground jobs.

**Key codes.** ulib's `key_ascii` turns events into ASCII (US layout, shift, caps lock;
ctrl + letter gives 1-26). The arrow keys give KEY_RIGHT $80, KEY_LEFT $81, KEY_DOWN $82
and KEY_UP $83; Home, Page Up, Delete, End and Page Down give KEY_HOME $84, KEY_PGUP $85,
KEY_DEL $86, KEY_END $87 and KEY_PGDN $88.

**Break key.** Ctrl-C (usage $06 with a ctrl modifier, key down) arriving while the
keyboard is lent *with the break flag* is not queued. Instead the kernel kills the
borrower, exactly as kill() would (exit code $FF80). The shell lends with the flag and
INIT lends without it, so ctrl-C stops a foreground job but never the shell. With the
keyboard not lent, or lent without the flag, ctrl-C is an ordinary key event.

**Classic machine.** classic_show gives screen and keyboard to the Atari until F12. In
every other situation F12 gives the $FF event.

Why lend instead of release and claim again: whenever KB_ROUTE goes to 1, the I/O
processor counts every key as released. When the keyboard comes back, a key that is still
held is reported again as a new press. A shell that exited on Enter would then hand an
empty line to its successor.

## Mouse

The I/O processor sends MOUSE events (relative dx, dy, wheel and the button byte: bit 0
left, 1 right, 2 middle) while the keyboard is routed to Horizon. For each one the kernel:

- moves the pointer position, clamped to 0-639 x 0-359;
- updates Marga's hardware pointer at once. This happens in interrupt service, so the
  pointer moves smoothly while tasks compute. The pointer is a 2 bpp arrow, black
  outline, white fill, hot spot at its tip; it appears with the first mouse event;
- queues an event for the keyboard holder in the same queue as the keys.

Events as input_read returns them:

| Event | A | X | Y | Queueing |
| --- | --- | --- | --- | --- |
| Motion | $0100 \| buttons | x | y | If the last queued event is a motion with the same buttons, it is updated to the new position instead: a slow reader gets the latest position, not a backlog |
| Button change | $0100 \| buttons (the new ones) | x | y | Never coalesced |
| Wheel | $0200 | delta (signed) | - | Consecutive wheel events are summed |

The pointer (and the desktop) are hidden while the classic machine is shown.

## Console

The console is the screen and DBG_OUT (the I/O processor's log); every byte goes to both.

**Screen.** 78 columns x 29 rows of 8x12 characters on Marga in mode 1 (640x360, 16
colours), inside a border of 8 pixels left and right and 6 lines top and bottom (paper
colour; the mouse pointer still covers the full 640x360): light text on dark blue, with an amber underline cursor at the output position.
The screen interprets these control characters:

| Byte | Effect |
| --- | --- |
| LF (10) | New line and return |
| CR (13) | Return to column 0 |
| BS (8) | One column left (not past column 0) |
| FF (12) | Clear the screen, cursor home |
| TAB (9) | To the next multiple of 8 |

Other control bytes are ignored on the screen. Characters 32-126 are printed and wrap at
column 78.

Escape sequences (a VT52 subset, for full-screen programs such as FILES):

| Sequence | Effect |
| --- | --- |
| ESC Y r c | Cursor to row r - 32, column c - 32 (clamped to the text area) |
| ESC K | Clear from the cursor to the end of the line, in the current video mode (with inverse on: a bar) |
| ESC p / ESC q | Inverse video on / off |
| ESC f / ESC e | Text cursor off / on |
| ESC E | Clear the screen (as FF) |

If a task that switched the cursor off or inverse on ends (even killed), the kernel
switches them back. The escapes also go to DBG_OUT. DBG_OUT receives every byte unchanged.

**Interleaving.** Each puts call (and each kernel `[kill]` line) is written to DBG_OUT under a console
lock, so it is never spliced with another task's output. While DBG_STAT is busy, the
writing task keeps interrupts serviced and gives up the CPU when a reschedule is due,
still holding the lock; other tasks that print wait for the lock. This works at any
console speed (about 90 us per byte on the board while its log is read, sometimes
milliseconds).

ulib buffers output and sends it one line per puts. A line therefore stays whole, but the
order of lines from different tasks depends on timing.

## Error codes

| Code | Name | Meaning |
| --- | --- | --- |
| 1 | EINVAL | Bad argument, or a handle, port or bank the caller does not own |
| 2 | ENOMEM | No free bank |
| 3 | ENOENT | (reserved: file errors use $40 + n, below) |
| 4 | EFAULT | A pointer range the caller may not access |
| 5 | ECHILD / ESRCH | No such child (wait) or task (kill) |
| 6 | EAGAIN | Full: no task slot, port, port queue space, or the input is taken |
| 7 | ENOSYS | Unknown syscall |
| 8 | ERUNNING | (0.13) spawn / task_single: a single-instance program runs already; its windows were raised |
| 9 | ENODEV | (0.17) The hardware is not there: the sample calls on a board without Lau (REV < $0A); (0.18) sprites and fs_scroll before REV $0B, fs_raster and win_vbl before REV $09 (BASIC 2.0 says "Not available on this machine") |
| 10 | ECANCELED | (0.21) User side only (the kernel never returns it): a copy cancelled by the user, from the controls library (ui_cptree, ui_mvtree: ui_cpcb returned C set; the progress window's Cancel; the shell's ctrl-C during `cp`, `mv`). Programs show no error for it |
| $40 + n | I/O | I/O processor result n. n is a FatFs FRESULT: 4 no file, 5 no path, 6 invalid name, 7 denied, 8 exists, 18 too many open files. $80 is a bad handle, $81 a bad address. (0.20) The PC volume: $C7 no PC link (the volume is not there), $C8 the PC link was lost (during the call, or the handle was opened before the link dropped), $C9 not the same volume (rename between the card and the PC) |

## Program format

A program is an **o65** file as written by ld65 (`FORMATS { o65: type = small; }`):

- The header has 16-bit sizes.
- The text, data, bss and zp segments are relocatable.
- The relocation tables use byte-wise entries.

ld65 handles 65816 code correctly here. `.loword`, bank bytes (`^label`, SEG) and 24-bit
addresses (`.faraddr`, JSL/JML, `lda f:`, SEGADR) all produce correct entries, so no extra
tool is needed. One quirk: ld65 writes mode $0800 and does not set the 65816 CPU bit, so the
loader does not check the CPU bits.

Build a program with `user/prog.cfg`:

```
ca65 -I user -o prog.o prog.s
ld65 -C user/prog.cfg -o PROG.PRG prog.o build/ulib.o
```

The config links text (CODE, RODATA), data and bss from $0100 in bank 0, and zp from $0000.

The loader:

1. STATs the file. A file shorter than 64 KB must be at least 26 bytes long.
2. Allocates the window bank and the code bank, owned by the new task, and a scratch bank.
3. LOADs the file into the scratch bank. (0.28) A file of 64 KB or more is read only in
   part: its first 65,535 bytes. The o65 must lie in them. Before 0.28 such a file was
   refused with EINVAL.
4. Checks the header:
   - Magic `01 00 'o' '6' '5' 00`.
   - No 32-bit sizes and no page-wise relocation.
   - text + data + bss must fit in $0100-$FFFF.
   - zp must be 256 bytes or less.
   - No undefined references.
5. Copies text and data to code bank $0100. Clears bss, which follows them, and clears the
   zp area at window $0000.
6. Applies the text and data relocation tables. A reference to the text, data or bss
   segment gets offset + (load address - link address) and the code bank as its bank byte.
   A reference to zp gets the direct page offset and bank 0. The supported types are WORD,
   LOW, HIGH, SEG (bank byte) and SEGADR (24-bit).
7. Frees the scratch bank.

Bytes after the o65 (after the end of its relocation tables and exports) are allowed, in a
file of any size. The loader never copies them into the program's memory. A program can keep
its own data there and read it from its own file: task_path ($35) gives the file's path.
The C SDK's large code model keeps its extra code banks there (sdk/docs/c/reference.md,
"The two code models").

(0.28) The loader keeps the program's absolute path for task_path in the window bank at
$8000-$807F. That half of the window bank is not part of the window, so the program cannot
see it or change it through bank 0.

## Task start conditions

| Register | Value |
| --- | --- |
| Mode | native, user mode, P = $00 (A/X/Y 16-bit, decimal off, interrupts enabled, carry clear) |
| PC | code bank:$0100 (the start of the text segment) |
| PBR, DBR | the code bank |
| D | $0000 (the zp segment is at window $0000-$00FF, cleared) |
| X | window offset of the argument string: $7FFE - length (bank 0) |
| A | length of the argument string (0 when spawn passed none, and for INIT) |
| S | X - 1 (the stack grows down from just below the argument string) |
| Y | 0 |

The argument string is zero-terminated and ends at window $7FFE. $7FFF is a spare byte,
so a 16-bit read of the terminator stays inside the window.

A task must end with `exit`; RTL/RTS from the entry point are not supported. Window bank
$0000-$7FFF is private. The rest of the window and of the code bank (past bss) is
undefined.

## Programs started from the Desktop and Files (0.31)

The shell passes what was typed after the command. The Desktop and Files have no command
line; they start a program (the Programs menu, a double click on a .PRG, a shortcut) with
the controls library's `ui_run` (`user/uiopen.s`), which builds the argument string so:

1. **APP.INF's `args=`** (an app's program: `/APPS/NAME/...`, the one its APP.INF names):
   the developer's default arguments, 127 characters at most; a shortcut (.LNK) with its own
   `args=` gives those instead.
2. **The options file `PROG.ARG`** next to the program (`/APPS/XCOM/XCOM.ARG` for
   `XCOM.PRG`; any folder, also `/BIN`): the user's own options, appended after one space.
   Its words: `#` to the line's end is a comment, line ends and runs of blanks become one
   space, only its first 382 bytes are read. Absent: nothing (one OPEN that fails, about
   25 ms on the board). The whole string is at most 127 characters (the kernel's limit,
   spawn): longer, an alert says so and the program is not started.
3. **APP.INF's `console=`**: `yes` starts the program in a Terminal window
   (`/BIN/TERM.PRG "PATH" ARGS`): its output (putc, puts, printf, stderr) and its console
   keys are there, and at its end the window says `--- NAME ended (code N).` and waits for a
   key or its close box; `error` the same, but the window closes by itself when the
   program ends with code 0, so it only stays when something went wrong. Without it (or
   `no`) the program is started detached as before: its console output goes to the log
   (DBG_OUT) and the hidden text console, where nobody sees it. A program with its own
   windows or a full screen still gets its keys from its windows (win_event): only the
   console calls (input_*) read the Terminal's keys.

Opening a document (a file by its type) passes the document's path alone: no `args=`, no
options file. Files' **Run with...** (the pop-up menu of a .PRG) asks for the arguments and
starts the program with exactly those in a Terminal window (no options file).

`TERM [-e] PROG [ARGS]` (`user/term.s`): the Terminal window runs PROG ("quoted" when it
has spaces) with ARGS instead of the shell, titled with PROG's file name; at the end
`--- NAME ended (code N).` in the window (`NAME was stopped` when killed) and
`term: NAME ended (code N)` in the log; `-e`: closed at once after code 0. The close box
kills the program.

Before 0.31 the Desktop and Files passed no arguments (a .LNK's `args=` only); programs
such as ports/xcom read an options file themselves when started without arguments, and
keep working (they get the options as arguments now).

## Faults

The kernel kills a task that triggers an ABORT, executes BRK, switches to emulation mode,
or enters the kernel with a stack pointer the entry frame could not be pushed through. It
prints:

```
[kill] task N NAME cause CC addr AAAAAA pc PPPPPP
```

and the task exits with code $FF00 + cause.

| Cause | Meaning | addr | pc |
| --- | --- | --- | --- |
| $01-$1F | ABORT_CAUSE: bit 0 write, 1 not owner, 2 not valid, 3 I/O page, 4 WP_VEC | ABORT_ADDR | The aborted instruction (`??????` when the frame was lost) |
| $20 | BRK | The BRK | PC after the BRK and its signature byte |
| $21 | The entry frame was lost or lies outside the window (bad S at an IRQ, NMI, COP or BRK) | S before the entry | `??????` |
| $22 | Emulation mode | 000000 | PC in bank 0 (PBR is unknown in emulation mode) |
| $23 | The watchdog expired while the task ran: it kept interrupts off (SEI) for 2 s | 000000 | The interrupted instruction |

Exit codes: $FF00 + cause for faults, $FF80 for kill() and the break key.

A task may execute SEI: on the 65C816 that is not privileged. The kernel survives it:

- It services pending interrupts at every return to user mode, so a task that keeps
  making syscalls with I set still gets ticks.
- A task that loops with interrupts off is killed by the watchdog (cause $23).

If the watchdog expires while the kernel itself runs, the kernel panics.

If the task's S points into kernel memory when it executes COP, the COP's push is refused
and the CPU takes ABORT instead. This gives cause $03 at addr 009000 with pc `??????`, as
CRASH mode 4 shows.

## NMI hold (hardware REV $04)

The CPU pushes every entry frame on the stack the task chose. If S is bad, the pushes made
in user mode are refused and dropped, and the kernel kills the task. The entry code then
runs 15 instructions on that S, in supervisor mode, before it switches to its own stack.

On REV $03 hardware, an NMI in that window could push 8 bytes with supervisor rights
wherever S pointed, possibly into kernel memory. REV $04 closes the window: after any
entry from user mode, the hardware holds the NMI off until the kernel writes FR_CTRL.

The kernel writes FR_CTRL right after its TCS to the kernel stack, on every user-mode
entry, before any other work. The idle loop and the WAI are only reached later, so never
with the hold set. A user-mode NMI entry first clears NMI_STATUS inline, without using
the stack: releasing the hold while a source is still set would raise a second NMI edge.
On REV < $04 the kernel prints a warning at boot.

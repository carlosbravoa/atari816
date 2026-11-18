; horizon.s - Horizon kernel, top level. One assembly unit: the modules are included here so
; every label resolves inside bank $01 without far imports.
;
;   boot.s     boot: hardware set-up, vectors, first task
;   entry.s    vector entry, user context save/restore, faults, NMI, panic
;   sched.s    scheduler, blocking, idle loop, timer tick, interrupt service
;   mem.s      bank allocator, FREDDIE II table, user pointer checks, memory copy
;   syscall.s  syscall table and the small syscalls
;   task.s     task creation, exit, wait, kill
;   mbox.s     I/O processor mailbox and the file syscalls
;   loader.s   o65 program loader (runs in the new task's own context)
;   ports.s    message ports
;   input.s    keyboard event queue
;   classic.s  Atari software: mount, eject, cold boot
;   console.s  kernel console (DBG_OUT + screen), console lock
;   screen.s   text console on Marga's framebuffer
;   mouse.s    mouse events and the hardware pointer
;   ws.s       the window system: surfaces, compositor, window manager, window syscalls
;   sound.s    REV $07 sound: POKEY 2 and the DACs, beep, sound_write
;   sys13.s    0.13: restart, sync and shut down, the Desktop request, single instance
;   ws13.s     0.13: window system additions (menu states, keyboard menus, close all, task flags)
;   ws15.s     0.15: pop-up menus, focus events, held keys
;   sys15.s    0.15: joystick, vsync
;   vstate.s   the video-state block at $01:F000 (for tools reading memory from outside)
;   kdata.s    kernel variables (BSS)

        .p816
        .smart  -
        .feature string_escapes

        .import __BSS_RUN__, __BSS_SIZE__, __BSS2_RUN__, __BSS2_SIZE__
        .import __K2CODE_RUN__, __K2CODE_SIZE__, __K2DATA_SIZE__, __K0BSS_RUN__, __K0BSS_SIZE__
        .import k2_sys: far, k2_vbl: far, k2_frameval: far, k2_task_exit: far
        .import k2_bank_gone: far, k2_wclose: far, k2_focus: far, k2_service: far
        .import k2_painted: far, k2_fsmove: far, k2_fskey: far, k2_fsbtn: far
        .import k2_fswheel: far, k2_pal_apply: far, k2_wspal: far, k2_classic: far
        .import k2_line: far, k2_lwait: far, k2_ws_end: far        ; (0.18) the second code segment, k2.s

        .include "hw.inc"
        .include "kdefs.inc"

        .segment "CODE"
        .a8
        .i8
        jmp     boot                    ; $01:0000: entered in native mode, M = X = 1

        .include "boot.s"
        .include "entry.s"
        .include "sched.s"
        .include "mem.s"
        .include "syscall.s"
        .include "task.s"
        .include "mbox.s"
        .include "loader.s"
        .include "ports.s"
        .include "input.s"
        .include "classic.s"
        .include "console.s"
        .include "screen.s"
        .include "mouse.s"
        .include "ws.s"
        .include "menu.s"
        .include "term.s"
        .include "wsx.s"
        .include "sound.s"
        .include "vstate.s"
        .include "sys13.s"
        .include "ws13.s"
        .include "ws14.s"
        .include "ws15.s"
        .include "sys15.s"
        .include "sys17.s"
        .include "kfar.s"
        .include "uifont.inc"
        .include "kdata.s"

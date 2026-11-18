; kdefs.inc - kernel constants, bank 0 layout, direct page variables and macros.
;
; Kernel conventions (everywhere unless a routine says otherwise):
;   native mode, A/X/Y 16-bit, D = KDP ($00:8000), DBR = $01 (kernel bank), I = 1.
;   Kernel code may block (k_block): across any call that can block, every register and
;   every direct page temporary (kt_*) is lost. State that must survive lives on the
;   task's kernel stack or in its TCB.
;   A slot index is always handled as slot*2 ("slot2"), ready for word-array indexing.

        .include "version.inc"
.define KVERSION_STR .concat("Horizon ", HORIZON_VERSION)

; ---- bank 0 kernel area ($00:8000-$CFFF) ----
KDP         = $8000         ; kernel direct page
IDLE_TOP    = $82FF         ; idle / boot stack: $8100-$82FF
KSTK_BASE   = $8300         ; 16 kernel stacks of 512 bytes: $8300-$A2FF
KSTK_SIZE   = 512
REQ_RING    = $00B000       ; mailbox request ring (4 KB aligned)
RSP_RING    = $00C000       ; mailbox response ring
KBANK       = $01           ; kernel code and data bank

; ---- tasks ----
NSLOT       = 16
NONE        = $FFFF         ; "no slot"

TS_FREE     = 0
TS_READY    = 1
TS_RUNNING  = 2
TS_BLOCKED  = 3
TS_ZOMBIE   = 4

W_IO        = 1             ; mailbox answer (not interruptible)
W_SLEEP     = 2
W_WAIT      = 3             ; wait() for a child
W_RECV      = 4             ; port receive
W_INPUT     = 5             ; key event
W_SPAWN     = 6             ; child is loading (not interruptible)
W_CONS      = 7             ; console lock (not interruptible)
W_CLASSIC   = 8             ; classic machine shown, waiting for the system key
W_WS        = 9             ; the window system thread (object 0) / ws_stop (object 1)
W_WEVENT    = 10            ; win_event: waiting for an event of one of its windows
W_BLIT      = 11            ; the compositor: waiting for the blitter's interrupt
W_POP       = 12            ; (0.15) win_popup: its pop-up menu is open
W_VSYNC     = 13            ; (0.15) vsync: waiting for the next vertical blank

WE_KEY      = 1             ; window events
WE_BUTTON   = 2
WE_CLOSE    = 3
WE_WHEEL    = 4
WE_TICK     = 5
WE_RESIZE   = 6
WE_MENU     = 7
WE_DROP     = 8
WE_MOTION   = 9
WE_LEAVE    = 10            ; (WF_HOVER) the pointer left the window
WE_FOCUS    = 14            ; (0.15) the window got the focus
WE_UNFOCUS  = 15            ; (0.15) the window lost it (its held keys were released first)

CB_STAY     = $C01D         ; (0.18) classic_boot: A = this, cold boot without showing it
CART_B0     = $70           ; (0.18) a cartridge's image: banks $70 .. $70 + CART_NB - 1
CART_NB     = 12            ;   (at most 768 KB while Horizon runs; $7C-$7F are the console's)
K2_NSYS     = $A0           ; (0.18) syscalls $91 .. K2_NSYS - 1 are in k2.s

SLICE_TICKS = 2
TICK_US     = 10000
TICK_MS     = 10

; syscall error codes
EINVAL      = 1
ENOMEM      = 2
ENOENT      = 3
EFAULT      = 4
ECHILD      = 5
EAGAIN      = 6
ENOSYS      = 7
ERUNNING    = 8             ; a single-instance program runs already (sys13.s)
EIO_BASE    = $40           ; file errors: I/O processor result + $40

; kill causes (low byte of the exit code $FF00 + cause); 1-$1F are ABORT_CAUSE values
CAUSE_BRK   = $20
CAUSE_STACK = $21           ; entry frame lost (bad S)
CAUSE_EMUL  = $22           ; the task switched to emulation mode
CAUSE_WDOG  = $23           ; the watchdog expired while the task ran (interrupts off)
EXIT_KILLED = $FF80         ; exit code of a task ended by kill()

; bank states (bank_st)
BK_FREE     = $00
BK_NONE     = $FF           ; reserved or not installed
BK_KERNEL   = $FE           ; allocated by the kernel (owner 0 in the table)

; FR_CTRL values
CTRL_KERNEL = FRC_PROT | FRC_B0WIN | FRC_WPVEC
CTRL_USER   = CTRL_KERNEL | FRC_ARM

; entry kinds
K_COP       = 0
K_BRK       = 2
K_ABORT     = 4
K_IRQ       = 6
K_NMI       = 8
K_EMU       = 10            ; any emulation-mode vector

; ---- direct page ($00:8000) ----
; Entry scratch, used with long addressing before D is set: one full entry at a time.
e_a         = $00
e_x         = $02
e_y         = $04
e_s         = $06
e_d         = $08
e_kind      = $0A
e_stop      = $0C           ; kernel stack top of the current task
n_a         = $0E           ; NMI scratch (an NMI may hit any kernel code)
r_a         = $10           ; return-to-user scratch
r_x         = $12
r_y         = $14
ctrl_base   = $16           ; FR_CTRL without USER_ARM (0 during early boot)
nmi_cnt     = $18           ; system key presses counted by the NMI handler
nmi_seen    = $1A           ; ... and already queued as key events
cur         = $1C           ; current slot*2, NONE in the idle loop
need_resched = $1E
ticks       = $20           ; 32-bit tick counter
ms_lo       = $24           ; 32-bit milliseconds
ms_hi       = $26
booted      = $28
nmi_wd      = $2E           ; nmi_status: NMI_STATUS bits seen
nmi_pend    = $2F           ; NMI_STATUS bits collected by a user-mode NMI entry
kout        = $5A           ; non-zero: kputc appends to this bank $01 buffer
us_last     = $2A           ; UPTIME at the last clock update (32 bits)
us_acc      = $5C           ; microseconds not yet counted as milliseconds (32 bits)
kt0         = $30           ; temporaries (lost across k_block)
kt1         = $32
kt2         = $34
kt3         = $36
kt4         = $38
kt5         = $3A
kt6         = $3C
kt7         = $3E
kp0         = $40           ; 24-bit pointers for [dp] access (4 bytes each)
kp1         = $44
kp2         = $48
kphys       = $4C           ; result of uaccess: physical address (24 bits)
kd_lo       = $50           ; loader: relocation delta
kd_hi       = $52
kv_lo       = $54
kv_hi       = $56
pv0         = $60           ; panic / print scratch
pv1         = $62
pv2         = $64
pv3         = $66

KDPL        = $008000       ; long address of the kernel direct page

; ---- macros ----
.macro  a8
        sep     #$20
        .a8
.endmacro
.macro  a16
        rep     #$20
        .a16
.endmacro
.macro  i8
        sep     #$10
        .i8
.endmacro
.macro  i16
        rep     #$10
        .i16
.endmacro
.macro  a16i16
        rep     #$30
        .a16
        .i16
.endmacro

; print an inline string on the kernel console (a16 i16; keeps A X Y)
.macro  kprint  str
        jsr     kputs_inline
        .byte   str, 0
.endmacro

; "[panic] str" + registers, then STP (D = KDP)
.macro  kpanic  str
        jsr     panic_inline
        .byte   str, 0
.endmacro

; long conditional branches (inverse branch over a JMP; no label, so @locals survive)
.macro  jeq     dst
        bne     *+5
        jmp     dst
.endmacro
.macro  jne     dst
        beq     *+5
        jmp     dst
.endmacro
.macro  jcc     dst
        bcs     *+5
        jmp     dst
.endmacro
.macro  jcs     dst
        bcc     *+5
        jmp     dst
.endmacro
.macro  jmi     dst
        bpl     *+5
        jmp     dst
.endmacro
.macro  jpl     dst
        bmi     *+5
        jmp     dst
.endmacro

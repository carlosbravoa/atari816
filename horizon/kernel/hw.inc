; hw.inc - Atari816 hardware registers used by Horizon (see core/src/a816/a816_sys.sv).

; FREDDIE II
FR_CTRL     = $00D800       ; 0 PROT_EN, 1 USER_ARM, 2 B0WIN_EN, 3 WP_VEC, 7 MODE (R)
PT_INDEX    = $00D801
PT_DATA     = $00D802       ; 7 VALID, 6 WRITE, 5-0 OWNER
CUR_TASK    = $00D803
ABORT_ADDR  = $00D804       ; 24 bits
ABORT_CAUSE = $00D807       ; 0 WRITE, 1 NOT_OWNER, 2 NOT_VALID, 3 IO_PAGE, 4 WP_VEC (W1C)
B0WIN       = $00D808
RAM_BANKS   = $00D809
CACHE_FLUSH = $00D80A

FRC_PROT    = $01
FRC_ARM     = $02
FRC_B0WIN   = $04
FRC_WPVEC   = $08

PTE_VALID   = $80
PTE_WRITE   = $40

; system block
SYS_ID      = $00DE00
SYS_REV     = $00DE01
SV_CTRL     = $00DC00       ; REV $06: bit 2 FREEZE_REQ (bit 0 reads 1)
SV_STATUS   = $00DC01       ; bit 0 FROZEN
IRQ_STATUS  = $00DE08       ; 2 TIMER0, 6 IOP (live level)
IRQ_EN      = $00DE09
NMI_STATUS  = $00DE0A       ; 0 SYSTEM_KEY, 1 WATCHDOG (W1C)
TM0_RELOAD  = $00DE10
TM0_CTRL    = $00DE13
UPTIME      = $00DE18
WATCHDOG    = $00DE1C
KB_ROUTE    = $00DE20
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1       ; bit 7 = busy

IRQ_TIMER0  = $04
IRQ_IOP     = $40
IRQ_BLITTER = $10

; I/O processor mailbox
MB_REQ_BASE = $00DD00
MB_REQ_HEAD = $00DD03
MB_REQ_TAIL = $00DD04
MB_RSP_BASE = $00DD05
MB_RSP_HEAD = $00DD08
MB_RSP_TAIL = $00DD09
MB_STATUS   = $00DD0A       ; 0 IOP_READY, 1 IOP_ERROR

MBOP_OPEN    = $01
MBOP_CLOSE   = $02
MBOP_READ    = $03
MBOP_WRITE   = $04
MBOP_SEEK    = $05
MBOP_STAT    = $06
MBOP_READDIR = $07
MBOP_MKDIR   = $08
MBOP_DELETE  = $09
MBOP_RENAME  = $0A
MBOP_LOAD    = $10
MBOP_STIME   = $1D           ; (0.19) the time for file dates (ARG0 = seconds since 2000)
MBOP_CSTATE  = $1E           ; (0.19) ARG0 = 5: the cartridge's size (ARG1) and path (BUF)
MBEV_KEY     = $E0
MBEV_MOUSE   = $E1

; emu816 mailbox test: OPEN/READ/CLOSE a file from --sd, LOAD, READDIR (with skip), STAT,
; WRITE + DELETE, and the error codes. Waits for answers with WAI on the IOP interrupt
; (I flag set, so WAI just resumes). Output goes to DBG_OUT; the run script compares it.
        .include "common.inc"

MB_REQ_BASE = $00DD00
MB_REQ_HEAD = $00DD03
MB_RSP_BASE = $00DD05
MB_RSP_HEAD = $00DD08
MB_RSP_TAIL = $00DD09
MB_STATUS   = $00DD0A
REQ_RING    = $0E0000
RSP_RING    = $0E1000
RDBUF       = $0D0000
DIRBUF      = $0D2000
LOADBUF     = $0C0000
ptr         = $10               ; direct page: 24-bit pointer
cnt         = $13

        .macro  REQ op, tag, len, buf, flags, arg0, arg1
        .byte   op, tag
        .word   len
        .faraddr buf
        .byte   flags
        .dword  arg0
        .dword  arg1
        .endmacro

        .segment "CODE"
        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        ldx     #$01FF
        txs
        phk
        plb
        print   m_hello

        lda     #$00                    ; rings at $0E:0000 and $0E:1000
        sta     f:MB_REQ_BASE
        sta     f:MB_REQ_BASE+1
        sta     f:MB_RSP_BASE
        lda     #$10
        sta     f:MB_RSP_BASE+1
        lda     #$0E
        sta     f:MB_REQ_BASE+2
        sta     f:MB_RSP_BASE+2
:       lda     f:MB_STATUS
        and     #$01
        beq     :-
        print   m_ready

; 1. open (lower case: FAT names are case-insensitive), read, print, close
        ldx     #.loword(q_open)
        jsr     mbdo
        jsr     expect0
        ldx     #.loword(q_read)
        jsr     mbdo
        jsr     expect0
        print   m_read
        ldx     rsp+12
        stx     cnt
        jsr     puthex16
        jsr     crlf
        ldx     #0
:       lda     f:RDBUF,x
        jsr     putc
        inx
        cpx     cnt
        bne     :-
        ldx     #.loword(q_close)
        jsr     mbdo
        jsr     expect0

; 2. LOAD the same file elsewhere and compare
        ldx     #.loword(q_load)
        jsr     mbdo
        jsr     expect0
        ldx     rsp+12
        cpx     cnt
        bne     load_bad
        ldx     #0
:       lda     f:LOADBUF,x
        cmp     f:RDBUF,x
        bne     load_bad
        inx
        cpx     cnt
        bne     :-
        print   m_loadok
        bra     t_dir
load_bad:
        print   m_loadbad

; 3. READDIR of the root, all entries
t_dir:  jsr     set_root                ; entries are written back over the path
        ldx     #.loword(q_dir)
        jsr     mbdo
        jsr     expect0
        print   m_dir
        lda     rsp+12
        sta     cnt
        jsr     puthex
        jsr     crlf
        lda     #^DIRBUF
        sta     ptr+2
        ldx     #.loword(DIRBUF)
        stx     ptr
dloop:  lda     cnt
        beq     ddone
        print   m_sp
        ldy     #3                      ; size, high byte first
:       lda     [ptr],y
        jsr     puthex
        dey
        bpl     :-
        lda     #' '
        jsr     putc
        ldy     #4
        lda     [ptr],y                 ; attr
        jsr     puthex
        lda     #' '
        jsr     putc
        ldy     #5
        lda     [ptr],y                 ; name length
        sta     cnt+1
        ldy     #6
:       lda     [ptr],y
        jsr     putc
        iny
        dec     cnt+1
        bne     :-
        jsr     crlf
        rep     #$20
        .a16
        tya                             ; next entry = 6 + namelen
        clc
        adc     ptr
        sta     ptr
        sep     #$20
        .a8
        dec     cnt
        bra     dloop
ddone:

; 4. READDIR skipping two entries
        jsr     set_root
        ldx     #.loword(q_dir2)
        jsr     mbdo
        jsr     expect0
        print   m_skip
        lda     rsp+12
        jsr     puthex
        jsr     crlf

; 5. WRITE a new file, STAT it, DELETE it, STAT again
        ldx     #.loword(q_create)
        jsr     mbdo
        jsr     expect0
        ldx     #.loword(q_write)
        jsr     mbdo
        jsr     expect0
        ldx     #.loword(q_close)
        jsr     mbdo
        jsr     expect0
        ldx     #.loword(q_stat)
        jsr     mbdo
        jsr     expect0
        print   m_stat
        rep     #$20
        .a16
        lda     a:statbuf               ; STAT wrote {size, attr, time} over the path
        tax
        sep     #$20
        .a8
        jsr     puthex16
        lda     #' '
        jsr     putc
        lda     a:statbuf+4
        jsr     puthex
        jsr     crlf
        ldx     #.loword(q_del)
        jsr     mbdo
        jsr     expect0
        jsr     restore_path
        ldx     #.loword(q_stat)
        jsr     mbdo
        pha
        print   m_gone
        pla
        jsr     puthex
        jsr     crlf

; 6. error codes
        print   m_errs
        ldx     #.loword(q_badh)        ; READ on a handle that is not open: $80
        jsr     mbdo
        jsr     puthex
        lda     #' '
        jsr     putc
        ldx     #.loword(q_bank10)      ; LOAD into bank $10: $81
        jsr     mbdo
        jsr     puthex
        lda     #' '
        jsr     putc
        ldx     #.loword(q_time)        ; TIME: $82 (not implemented by the firmware)
        jsr     mbdo
        jsr     puthex
        lda     #' '
        jsr     putc
        ldx     #.loword(q_dotdot)      ; "/../x": invalid name
        jsr     mbdo
        jsr     puthex
        lda     #' '
        jsr     putc
        ldx     #.loword(q_nopath)      ; "/NODIR/X": no path
        jsr     mbdo
        jsr     puthex
        lda     #' '
        jsr     putc
        ldx     #.loword(q_rest2)       ; SYS_RESTART with a bad mode: $83 (no restart)
        jsr     mbdo
        jsr     puthex
        lda     #' '
        jsr     putc
        ldx     #.loword(q_sync)        ; SYS_SYNC: OK
        jsr     mbdo
        jsr     puthex
        jsr     crlf

        lda     f:IRQ_STATUS            ; IOP must be clear once the ring is drained
        and     #$40
        bne     :+
        print   m_done
        stp
:       print   m_iopbad
        stp

; ── helpers ──
expect0:                                ; A = result: print it and stop unless 0
        cmp     #0
        bne     :+
        rts
:       pha
        print   m_err
        pla
        jsr     puthex
        jsr     crlf
        stp

set_root:
        lda     #'/'
        sta     f:DIRBUF
        lda     #0
        sta     f:DIRBUF+1
        rts

restore_path:
        ldx     #0
:       lda     p_out,x
        sta     a:statbuf,x
        inx
        cpx     #12
        bne     :-
        rts

; X = 16-byte request template. Send, wait (WAI on the IOP interrupt), copy the answer to
; rsp. Returns A = result low byte.
mbdo:   ldy     #0
:       lda     a:0,x
        sta     msg,y
        inx
        iny
        cpy     #16
        bne     :-
        rep     #$20
        .a16
        lda     f:MB_REQ_HEAD
        and     #$00FF
        asl
        asl
        asl
        asl
        tax
        sep     #$20
        .a8
        ldy     #0
:       lda     msg,y
        sta     f:REQ_RING,x
        inx
        iny
        cpy     #16
        bne     :-
        lda     f:MB_REQ_HEAD
        inc
        sta     f:MB_REQ_HEAD           ; doorbell
        sei
        lda     #$40                    ; IOP interrupt; with I set WAI only waits for it
        sta     f:IRQ_EN
:       lda     f:MB_RSP_HEAD
        cmp     f:MB_RSP_TAIL
        bne     :+
        wai
        bra     :-
:       lda     #$00
        sta     f:IRQ_EN
        rep     #$20
        .a16
        lda     f:MB_RSP_TAIL
        and     #$00FF
        asl
        asl
        asl
        asl
        tax
        sep     #$20
        .a8
        ldy     #0
:       lda     f:RSP_RING,x
        sta     rsp,y
        inx
        iny
        cpy     #16
        bne     :-
        lda     f:MB_RSP_TAIL
        inc
        sta     f:MB_RSP_TAIL
        lda     msg
        ora     #$80
        cmp     rsp
        beq     :+
        print   m_opbad
:       lda     rsp+8
        rts

;                 op   tag len    buf            flags arg0      arg1
q_open:   REQ     $01, 1,  0,     p_hello,       0,    0,        0
q_read:   REQ     $03, 2,  $100,  RDBUF,         0,    0,        0
q_close:  REQ     $02, 3,  0,     0,             0,    0,        0
q_load:   REQ     $10, 4,  0,     p_hello,       0,    LOADBUF,  0
q_dir:    REQ     $07, 5,  $200,  DIRBUF,        0,    0,        0
q_dir2:   REQ     $07, 6,  $200,  DIRBUF,        0,    2,        0
q_create: REQ     $01, 7,  0,     p_out,         2,    0,        0
q_write:  REQ     $04, 8,  37,    RDBUF,         0,    0,        0
q_stat:   REQ     $06, 9,  0,     statbuf,       0,    0,        0
q_del:    REQ     $09, 10, 0,     p_out,         0,    0,        0
q_badh:   REQ     $03, 11, 16,    RDBUF,         0,    3,        0
q_bank10: REQ     $10, 12, 0,     p_hello,       0,    $100000,  0
q_time:   REQ     $30, 13, 0,     0,             0,    0,        0
q_dotdot: REQ     $06, 14, 0,     p_dotdot,      0,    0,        0
q_nopath: REQ     $06, 15, 0,     p_nopath,      0,    0,        0
q_rest2:  REQ     $1B, 16, 0,     0,             0,    2,        0
q_sync:   REQ     $1C, 17, 0,     0,             0,    0,        0

p_hello:  .byte "/hello.txt", 0
p_out:    .byte "/OUT.TMP", 0, 0, 0, 0
statbuf:  .byte "/OUT.TMP", 0, 0, 0, 0
p_dotdot: .byte "/../x", 0
p_nopath: .byte "/NODIR/X", 0
m_hello:  .byte "MBDEMO", 10, 0
m_ready:  .byte "IOP READY", 10, 0
m_read:   .byte "READ ", 0
m_loadok: .byte "LOAD OK", 10, 0
m_loadbad: .byte "LOAD FAIL", 10, 0
m_dir:    .byte "DIR ", 0
m_sp:     .byte "  ", 0
m_skip:   .byte "SKIP2 ", 0
m_stat:   .byte "STAT ", 0
m_gone:   .byte "DELETED ", 0
m_errs:   .byte "ERRORS ", 0
m_err:    .byte "UNEXPECTED RESULT ", 0
m_opbad:  .byte "BAD RESPONSE OP", 10, 0
m_iopbad: .byte "IOP STILL SET", 10, 0
m_done:   .byte "DONE", 10, 0
msg:      .res 16
rsp:      .res 16

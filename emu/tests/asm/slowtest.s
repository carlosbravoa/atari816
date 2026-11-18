; emu816 test of slow transfers (--card-kbps, --pc-kbps) and of the events that keep coming
; while a request is in progress (the I/O processor firmware of Horizon 0.21). A list of
; mailbox requests, one at a time. While it waits for an answer it prints every KEY / MOUSE
; event that arrives ("  KEY uu mm dd", "  MOUSE dx dy wh bb"); then "LABEL RR VVVVVVVV" and
; "T OK" when the answer took as long as the step says (in 256 us units), else "T tttt".
; The run script gives it --card-kbps 64:32 --pc-kbps 100:8 --pc-drop-at 3 and key and
; mouse input during the slow requests, and compares the output with
; tests/expected/slowtest.txt; it also checks the PC folder (a mode 2 file appears only at
; CLOSE; one cut off by the drop leaves no trace and the older file as it was).
        .include "common.inc"

MB_REQ_BASE = $00DD00
MB_REQ_HEAD = $00DD03
MB_RSP_BASE = $00DD05
MB_RSP_HEAD = $00DD08
MB_RSP_TAIL = $00DD09
MB_STATUS   = $00DD0A
KB_ROUTE    = $00DE20
REQ_RING    = $0E0000
RSP_RING    = $0E1000
DATA        = $0C0000           ; 32 KB read from the card, then written to the PC
WORK        = $0D4000           ; the path (and what STAT writes over it)
step        = $16               ; the current step (offset in bank $01)
t0          = $18               ; UPTIME bytes 1-2 when the request was sent
dt          = $1A

; a step: label, path (0: none), min and max time (256 us units), request (16 bytes)
        .macro  STEP label, path, tmin, tmax, op, len, buf, flags, arg0, arg1
        .word   .loword(label), .loword(path), tmin, tmax
        .byte   op, 0
        .word   len
        .faraddr buf
        .byte   flags
        .dword  arg0
        .dword  arg1
        .endmacro
STEPLEN = 24

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
        lda     #$00                    ; the keyboard and mouse are ours
        sta     f:KB_ROUTE
:       lda     f:MB_STATUS
        and     #$01
        beq     :-

        ldx     #.loword(steps)
        stx     step
next:   ldx     step
        lda     a:0,x
        ora     a:1,x
        bne     :+
        lda     #$01
        sta     f:KB_ROUTE
        print   m_done
        stp
:       jsr     do_step
        ldx     step                    ; "LABEL RR VVVVVVVV"
        ldy     a:0,x
        tyx
        jsr     puts
        lda     #' '
        jsr     putc
        lda     rsp+8
        jsr     puthex
        lda     #' '
        jsr     putc
        ldx     rsp+14
        jsr     puthex16
        ldx     rsp+12
        jsr     puthex16
        print   m_t
        rep     #$20
        .a16
        ldx     step
        lda     dt
        cmp     a:4,x
        bcc     @bad
        cmp     a:6,x
        beq     @ok
        bcs     @bad
@ok:    sep     #$20
        .a8
        print   m_ok
        bra     @nx
        .a16
@bad:   sep     #$20
        .a8
        ldx     dt
        jsr     puthex16
@nx:    jsr     crlf
        rep     #$20
        .a16
        lda     step
        clc
        adc     #STEPLEN
        sta     step
        sep     #$20
        .a8
        jmp     next

; the current step: its path to WORK, the request sent, the events printed while it is in
; progress, its answer to rsp and dt = the time it took
do_step:
        ldx     step
        ldy     a:2,x                   ; the path
        beq     :++
        ldx     #0
:       lda     a:0,y
        sta     f:WORK,x
        iny
        inx
        cpx     #128
        bne     :-
:       ldx     step
        ldy     #0
:       lda     a:8,x
        sta     msg,y
        inx
        iny
        cpy     #16
        bne     :-
        ldx     step
        ldy     a:2,x
        beq     :+
        lda     #<WORK                  ; BUF = WORK
        sta     msg+4
        lda     #>WORK
        sta     msg+5
        lda     #^WORK
        sta     msg+6
:       rep     #$20
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
        jsr     now
        stx     t0
        lda     f:MB_REQ_HEAD
        inc
        sta     f:MB_REQ_HEAD           ; doorbell
        sei
        lda     #$40                    ; IOP interrupt; with I set WAI only waits for it
        sta     f:IRQ_EN
@wait:  lda     f:MB_RSP_HEAD
        cmp     f:MB_RSP_TAIL
        bne     :+
        wai
        bra     @wait
:       rep     #$20
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
        lda     rsp
        cmp     #$E0
        beq     @key
        cmp     #$E1
        beq     @mouse
        jsr     now                     ; the answer
        rep     #$20
        .a16
        txa
        sec
        sbc     t0
        sta     dt
        sep     #$20
        .a8
        lda     #$00
        sta     f:IRQ_EN
        rts
@key:   print   m_key
        lda     rsp+8
        jsr     sp_hex
        lda     rsp+12
        jsr     sp_hex
        lda     rsp+13
        jsr     sp_hex
        jsr     crlf
        bra     @wait
@mouse: print   m_mouse
        lda     rsp+8
        jsr     sp_hex
        lda     rsp+9
        jsr     sp_hex
        lda     rsp+10
        jsr     sp_hex
        lda     rsp+12
        jsr     sp_hex
        jsr     crlf
        jmp     @wait

sp_hex: pha
        lda     #' '
        jsr     putc
        pla
        jmp     puthex

; X = UPTIME bytes 1-2 (256 us units)
now:    lda     f:UPTIME                ; latches the upper bytes
        rep     #$20
        .a16
        lda     f:UPTIME+1
        tax
        sep     #$20
        .a8
        rts

; card 64:32 KB/s + 1 ms a request, the PC 100:8 KB/s + 6 ms; 3.9 units a ms
;            label     path        tmin   tmax   op   len    buf    fl arg0  arg1
steps:
        STEP l_openr,  p_big,      3,     6,     $01, 0,     0,     0, 0,    0
        STEP l_read,   0,          1950,  1965,  $03, $8000, DATA,  0, 0,    0
        STEP l_close,  0,          3,     6,     $02, 0,     0,     0, 0,    0
        STEP l_openw,  p_new,      23,    26,    $01, 0,     0,     2, 0,    0
        STEP l_write,  0,          29,    33,    $04, 16,    wdata, 0, 0,    0
        STEP l_statt,  p_new,      23,    26,    $06, 0,     0,     0, 0,    0
        STEP l_close,  0,          23,    26,    $02, 0,     0,     0, 0,    0
        STEP l_statn,  p_new,      23,    26,    $06, 0,     0,     0, 0,    0
        STEP l_openo,  p_old,      23,    26,    $01, 0,     0,     2, 0,    0
        STEP l_wbig,   0,          15600, 15700, $04, $8000, DATA,  0, 0,    0
        STEP l_closeo, 0,          0,     2,     $02, 0,     0,     0, 0,    0
        STEP l_statpc, p_pc,       0,     2,     $06, 0,     0,     0, 0,    0
        .word   0

p_big:    .byte "/BIG.BIN", 0
p_new:    .byte "/PC:/New.bin", 0
p_old:    .byte "/PC:/Old.txt", 0
p_pc:     .byte "/PC:", 0
wdata:    .byte "Sixteen bytes!", 13, 10
l_openr:  .byte "OPENCARD", 0
l_read:   .byte "READ32K", 0
l_close:  .byte "CLOSE", 0
l_openw:  .byte "OPENPC2", 0
l_write:  .byte "WRITE16", 0
l_statt:  .byte "STATBEFORECLOSE", 0
l_statn:  .byte "STATAFTERCLOSE", 0
l_openo:  .byte "OPENOLD2", 0
l_wbig:   .byte "WRITE32KDROP", 0
l_closeo: .byte "CLOSEDEAD", 0
l_statpc: .byte "STATPC", 0
m_hello:  .byte "SLOWTEST", 10, 0
m_key:    .byte "  KEY", 0
m_mouse:  .byte "  MOUSE", 0
m_t:      .byte " T ", 0
m_ok:     .byte "OK", 0
m_done:   .byte "DONE", 10, 0
msg:      .res 16
rsp:      .res 16

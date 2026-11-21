; OTEST - (0.27) a test of opl_write (SYS_OPLW $6D, the OPL2 of REV $0C), run from the text
; shell by tests/otest.keys (make test). It prints what it sees, compared with tests/otest.txt
; (tests/otest-noopl.txt before REV $0C), and emu816 --log-opl logs every OPL2 data write,
; compared with tests/otest.err (the kernel's key-offs at boot first).
;   1. the probe ($FFFE): the idle status $06, nothing written
;   2. a register written ($A0 = $41): in the log, the status returned; the chip is ours now
;   3. refused: $F6 and $FFFC (EINVAL), nothing written
;   4. one owner: a child's write, reset and release get EAGAIN, its probe the status
;   5. timer A through the call: value $00 (20.6 ms), started unmasked: the probe sees the
;      flag ($C6) after 50 ms; the IRQ reset ($04 = $80) clears it, $04 = $60 stops it
;   6. the reset ($FFFF): $01-$F5 = 0 (in the log); the chip stays ours
;   7. a note on ($B0 = $31) and $BD = $E3, then the classic machine shown (classic_show,
;      F12 from tests/otest.keys back): the kernel keys the notes off and nothing else ($B0 = $11,
;      $B1-$B8 their last values, $BD = $E0); the chip stays ours
;   8. the release ($FFFD): every note off ($B0-$B8, $BD = 0), the chip free (a second
;      release: nothing)
;   9. a child keys a note on and exits: its notes are keyed off ($B0-$B8, $BD = 0)
;  10. a child keys a note on and is killed: the same; the parent, which owns nothing then,
;      exits without key-offs
; Before REV $0C: the probe returns ENODEV, and that is all.
        .include "horizon.inc"

        .segment "CODE"
        .a16
        .i16
start:  sta     z:alen
        jsr     args_init
        lda     z:alen
        beq     :+
        jmp     child
:       print   "otest 1: probe: "
        lda     #$FFFE
        ldx     #0
        sys     SYS_OPLW
        bcc     :+
        cmp     #ENODEV
        bne     :+
        print   "no OPL2: ENODEV\n"
        exit    0
:       jsr     res

        print   "otest 2: $A0 = $41: "
        lda     #$A0
        ldx     #$41
        sys     SYS_OPLW
        jsr     res

        print   "otest 3: refused\n"
        print   "  $F6: "
        lda     #$F6
        ldx     #$55
        sys     SYS_OPLW
        jsr     res
        print   "  $FFFC: "
        lda     #$FFFC
        ldx     #$55
        sys     SYS_OPLW
        jsr     res

        print   "otest 4: one owner\n"
        jsr     out_flush
        lda     #.loword(a_busy)
        sta     z:u_arg
        lda     #^a_busy
        sta     z:u_arg+2
        ptr     p_self
        lda     #1
        jsr     spawn
        bcs     :+
        sys     SYS_WAIT
:
        print   "otest 5: timer A\n"
        lda     #$02                    ; value 0: 256 steps of 80.3 us
        ldx     #$00
        sys     SYS_OPLW
        lda     #$04                    ; mask B, start A
        ldx     #$21
        sys     SYS_OPLW
        pha
        print   "  started: "
        pla
        jsr     res2
        lda     #50
        sys     SYS_SLEEP
        print   "  50 ms later: "
        lda     #$FFFE
        sys     SYS_OPLW
        jsr     res
        print   "  IRQ reset: "
        lda     #$04
        ldx     #$80
        sys     SYS_OPLW
        jsr     res
        print   "  stopped: "
        lda     #$04
        ldx     #$60
        sys     SYS_OPLW
        jsr     res

        print   "otest 6: reset: "
        lda     #$FFFF
        sys     SYS_OPLW
        jsr     res

        print   "otest 7: notes on, the classic machine shown: "
        lda     #$B0
        ldx     #$31
        sys     SYS_OPLW
        lda     #$BD
        ldx     #$E3
        sys     SYS_OPLW
        sys     SYS_CLASSIC             ; the classic machine shown until F12 (the keys)
        jsr     res
        print   "  back: "
        lda     #$A0
        ldx     #$42
        sys     SYS_OPLW
        jsr     res

        print   "otest 8: release: "
        lda     #$FFFD
        sys     SYS_OPLW
        jsr     res
        print   "  again: "
        lda     #$FFFD
        sys     SYS_OPLW
        jsr     res

        print   "otest 9: a child plays and exits\n"
        jsr     out_flush
        lda     #.loword(a_exit)
        sta     z:u_arg
        lda     #^a_exit
        sta     z:u_arg+2
        ptr     p_self
        lda     #1
        jsr     spawn
        bcs     :+
        sys     SYS_WAIT
:       print   "  its notes keyed off\n"

        print   "otest 10: a child plays and is killed\n"
        jsr     out_flush
        lda     #.loword(a_kill)
        sta     z:u_arg
        lda     #^a_kill
        sta     z:u_arg+2
        ptr     p_self
        lda     #1
        jsr     spawn
        sta     z:kid
        lda     #100                    ; (its note is on)
        sys     SYS_SLEEP
        lda     z:kid
        sys     SYS_KILL
        lda     z:kid
        sys     SYS_WAIT
        print   "  its notes keyed off\n"
        print   "otest: done\n"
        exit    0

; "status SS" / "error NN" after a call (res2: the status in A, without a call's C)
res:    bcs     res_e
res2:   pha
        print   "status "
        pla
        jsr     put_hex8
        jmp     put_nl
res_e:  pha
        print   "error "
        pla
        jsr     put_hex8
        jmp     put_nl

; the children: "b" tries the chip its parent owns; a note on channel 0 ($A0, $B0 key-on),
; then "x" exits, "k" sleeps
child:  lda     f:0,x
        sta     z:kid
        and     #$00FF
        cmp     #'b'
        jne     @note
        print   "  child: write: "
        lda     #$A0
        ldx     #$43
        sys     SYS_OPLW
        jsr     res
        print   "  child: reset: "
        lda     #$FFFF
        sys     SYS_OPLW
        jsr     res
        print   "  child: release: "
        lda     #$FFFD
        sys     SYS_OPLW
        jsr     res
        print   "  child: probe: "
        lda     #$FFFE
        sys     SYS_OPLW
        jsr     res
        exit    0
@note:  lda     #$A0
        ldx     #$41
        sys     SYS_OPLW
        lda     #$B0
        ldx     #$31
        sys     SYS_OPLW
        lda     z:kid
        and     #$00FF
        cmp     #'k'
        beq     @k
        exit    0
@k:     lda     #10000
        sys     SYS_SLEEP
        exit    0

        .segment "RODATA"
p_self: .byte   "/SYSTEM/TESTS/OTEST.PRG", 0
a_exit: .byte   "x", 0
a_kill: .byte   "k", 0
a_busy: .byte   "b", 0

        .segment "ZEROPAGE"
alen:   .res    2
kid:    .res    2

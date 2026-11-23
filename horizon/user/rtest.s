; RTEST - (0.30) a test of fill_runs ($A4: many runs filled by Ali in one call) and uptime_us
; ($A5), run from the text shell by tests/rtest.keys (make test). It prints what it sees
; (compared with tests/rtest.txt; tests/rtest-r9.txt on REV $09, tests/rtest-r8.txt below).
;   1. uptime_us: microseconds, consistent with a 40 ms sleep
;   2. refused calls: too many runs, flags, a page in the kernel's bank, in a free bank, running
;      out of the caller's bank, runs not readable, a run past the page (EINVAL, X = its index),
;      the edges of a page (its last byte; a page of 65,536 bytes), no runs; ENODEV before
;      REV $09 (then the rest is left out)
;   3. pixels: a list with zero widths, the page's first and last bytes, width 255, runs over
;      each other (in order), into a page in the middle of a bank: the same bank as the CPU
;      gives with the same runs
;   4. a list of 2,688 runs (the most) and nine calls of them: the same as the CPU's
;   5. into the program's full-screen framebuffer
;   6. the music timer (sample_timer, 1 ms) is served while a long list is made: its messages
;      wait in the port when the call returns (8: the queue full); ENODEV without Lau
;   7. another program's page: EFAULT (a child given the bank)
;   8. a child killed while it sends long lists: its list stopped, the next call works
; "rtest m": the measurement: the kernel's time a run (uptime_us), and the whole list's.
        .include "horizon.inc"

FR_N    = 2688                  ; the most runs a call (FR_MAX)

        .segment "CODE"
        .a16
        .i16
start:  sta     z:alen
        jsr     args_init
        stx     z:argp
        lda     z:alen
        jeq     main
        lda     f:0,x
        and     #$00FF
        cmp     #'m'
        jeq     measure
        cmp     #'O'
        jeq     child_o
        cmp     #'K'
        jeq     child_k
        exit    1

main:
; ---------------------------------------------------------------- 1. uptime_us
        print   "rtest 1: uptime_us\n"
        sys     SYS_UPTIMEUS
        sta     z:t0
        stx     z:t1
        lda     #40
        sys     SYS_SLEEP
        sys     SYS_UPTIMEUS
        sec
        sbc     z:t0
        sta     z:t2                    ; (the difference fits 16 bits: about 40,000-50,000)
        txa
        sbc     z:t1
        bne     @ubad
        lda     z:t2
        cmp     #29000
        bcc     @ubad
        cmp     #50000
        bcs     @ubad
        print   "  a sleep of 40 ms (10 ms ticks) later: 29,000 to 50,000 us more: ok\n"
        bra     gt1e
@ubad:  print   "  wrong: "
        lda     z:t2
        jsr     put_dec
        jsr     put_nl
gt1e:

        sys     SYS_WSSTART
        bcc     :+
        print   "rtest: no window system\n"
        exit    1
:       ptr     wb
        sys     SYS_WOPEN
        sta     z:winb
        lda     #0
        ldx     #0
        sys     SYS_WSCONFIG
        stx     z:rev
        sys     SYS_BALLOC              ; the page's bank, the CPU's copy, the runs
        sta     z:bank
        sys     SYS_BALLOC
        sta     z:bank2
        sys     SYS_BALLOC
        sta     z:bank3

; ---------------------------------------------------------------- 2. refused calls
gt2:    print   "rtest 2: fill_runs refused\n"
        lda     z:bank                  ; the runs: 8 of them in the runs' bank
        ldx     #0
        jsr     setpage                 ; page = bank:0000, size 1000
        lda     #1000
        sta     frb+FRB_SIZE
        jsr     runs8
        print   "  one run: "
        lda     #1
        jsr     fr
        jcs     gt2nd
        jsr     resv
        print   "  2689 runs: "
        lda     #FR_N + 1
        jsr     fr
        jsr     res
        print   "  flags 2: "
        lda     #2
        sta     frb+3
        lda     #1
        jsr     fr
        jsr     res
        stz     frb+3                   ; (and the size's low byte: again)
        lda     #1000
        sta     frb+FRB_SIZE
        print   "  a page in the kernel's bank: "
        lda     #1
        ldx     #0
        jsr     setpage
        lda     #1
        jsr     fr
        jsr     res
        print   "  a page in a free bank: "
        sys     SYS_BALLOC
        pha
        sys     SYS_BFREE
        pla
        ldx     #0
        jsr     setpage
        lda     #1
        jsr     fr
        jsr     res
        print   "  a page running out of the bank: "
        lda     z:bank3                 ; (the bank after it: the free one above)
        ldx     #$C000
        jsr     setpage
        lda     #$4001
        sta     frb+FRB_SIZE
        lda     #1
        jsr     fr
        jsr     res
        print   "  runs in the kernel's bank: "
        lda     z:bank
        ldx     #0
        jsr     setpage
        lda     #1000
        sta     frb+FRB_SIZE
        lda     #1
        sta     frb+FRB_RUNS+2
        lda     #1
        jsr     fr
        jsr     res
        print   "  runs past the window: "
        stz     frb+FRB_RUNS+2
        lda     #$7FFE
        sta     frb+FRB_RUNS
        lda     #1
        jsr     fr
        jsr     res
        lda     z:bank3
        sta     frb+FRB_RUNS+2
        stz     frb+FRB_RUNS
        print   "  run 5 past the page: "
        jsr     runs8
        lda     #1000 - 254             ; run 5: offset 746, width 255: ends at 1001
        ldx     #5
        jsr     setofs
        lda     #5
        ldx     #255
        jsr     setw
        lda     #8
        jsr     fr
        jsr     resx
        print   "  run 2 ending at the page's last byte: "
        jsr     runs8
        lda     #1000 - 255             ; offset 745 + 255 = 1000
        ldx     #2
        jsr     setofs
        lda     #2
        ldx     #255
        jsr     setw
        lda     #8
        jsr     fr
        jsr     resv
        print   "  run 7 at offset 1000, width 0: "
        jsr     runs8
        lda     #1000
        ldx     #7
        jsr     setofs
        lda     #7
        ldx     #0
        jsr     setw
        lda     #8
        jsr     fr
        jsr     resv
        print   "  run 7 at offset 1001, width 0: "
        lda     #1001
        ldx     #7
        jsr     setofs
        lda     #8
        jsr     fr
        jsr     resx
        print   "  a page of 65,536 bytes, run at 65,535 width 1: "
        stz     frb+FRB_SIZE
        jsr     runs8
        lda     #$FFFF
        ldx     #3
        jsr     setofs
        lda     #3
        ldx     #1
        jsr     setw
        lda     #8
        jsr     fr
        jsr     resv
        print   "  the same, width 2: "
        lda     #3
        ldx     #2
        jsr     setw
        lda     #8
        jsr     fr
        jsr     resx
        print   "  no runs: "
        lda     #0
        jsr     fr
        jsr     resv
        sys     SYS_LISTWAIT            ; (A = 0: wait)
        jmp     gt3
gt2nd:  cmp     #ENODEV
        beq     :+
        jsr     err
        jmp     done
:       print   "ENODEV (before REV $09, or no blitter): the caller fills by itself\n"
        jmp     done

; ---------------------------------------------------------------- 3. pixels
gt3:    print   "rtest 3: pixels\n"
        lda     z:bank                  ; both banks $5A
        ldx     #$5A5A
        jsr     bfill
        lda     z:bank2
        ldx     #$5A5A
        jsr     bfill
        ldx     #0                      ; the runs (table r3) into the runs' bank
:       lda     r3,x
        sta     z:t0
        txy
        lda     z:bank3
        sta     z:p+2
        stz     z:p
        lda     z:t0
        sta     [p],y
        inx
        inx
        cpx     #R3N * 4
        bcc     :-
        lda     z:bank                  ; page = bank:$3000, 8,000 bytes
        ldx     #$3000
        jsr     setpage
        lda     #8000
        sta     frb+FRB_SIZE
        print   "  14 runs: "
        lda     #R3N
        jsr     fr
        jsr     resv
        lda     #R3N
        jsr     cmpref
        print   "  12 runs of width 1 at the page's first bytes, one at a time: "
        ldx     #0
@one:   phx
        jsr     runs1
        lda     #1
        jsr     fr
        plx
        bcs     @onee
        inx
        cpx     #12
        bcc     @one
        clc
@onee:  jsr     resv0
        lda     #0
        sys     SYS_LISTWAIT
        jsr     ref1
        lda     #0
        jsr     cmpref

; ---------------------------------------------------------------- 4. many runs
        print   "rtest 4: 2,688 runs\n"
        lda     z:bank
        ldx     #0
        jsr     setpage
        stz     frb+FRB_SIZE            ; 65,536 bytes
        lda     #$ACE1
        sta     z:rnd
        print   "  a list: "
        jsr     rruns
        lda     #FR_N
        jsr     fr
        jsr     resv
        lda     #FR_N
        jsr     cmpref
        print   "  nine lists, each made while the one before is drawn: "
        lda     #9
        sta     z:t3
@nine:  jsr     rruns
        lda     #FR_N
        jsr     fr
        bcs     @n9
        lda     #FR_N                   ; the CPU's copy, as Ali draws (no wait)
        jsr     refrun
        dec     z:t3
        bne     @nine
        clc
@n9:    jsr     resv0
        lda     #0
        sys     SYS_LISTWAIT
        lda     #0
        jsr     cmpref

; ---------------------------------------------------------------- 5. full screen
        print   "rtest 5: the full-screen framebuffer: "
        lda     z:bank
        ldx     #$5A5A
        jsr     bfill
        lda     z:bank                  ; 320 x 180 at bank:0000
        sep     #$20
        .a8
        sta     fsb+8
        rep     #$20
        .a16
        lda     z:winb
        ptr     fsb
        sys     SYS_FSENTER
        bcs     @fsb
        lda     z:bank
        ldx     #0
        jsr     setpage
        lda     #320 * 180
        sta     frb+FRB_SIZE
        jsr     rows                    ; row r: colour r, from x = r to x = r + 100
        lda     #180
        jsr     fr
        bcs     @fsb
        lda     #0
        sys     SYS_LISTWAIT
        lda     z:bank                  ; row 100's pixels 99, 100, 199, 200
        sta     z:p+2
        lda     #100 * 320 + 99
        sta     z:p
        lda     [p]
        cmp     #100 << 8 | $5A
        bne     @fsx
        ldy     #100
        lda     [p],y
        cmp     #$5A << 8 | 100
        bne     @fsx
        print   "ok\n"
        bra     @fsl
@fsx:   print   "wrong pixels\n"
        bra     @fsl
@fsb:   jsr     err
@fsl:   lda     z:winb
        sys     SYS_FSLEAVE

; ---------------------------------------------------------------- 6. the music timer
        print   "rtest 6: the music timer during a long list: "
        sys     SYS_PCREATE
        sta     z:port
        lda     z:port
        ldx     #1000                   ; 1 ms
        ldy     #0
        sys     SYS_STIMER
        bcc     :+
        cmp     #ENODEV
        jne     @tbad
        print   "ENODEV (no Lau before REV $0A)\n"
        jmp     gt7
:       lda     z:bank                  ; 2,688 runs of 255 pixels: about 50 ms
        ldx     #0
        jsr     setpage
        stz     frb+FRB_SIZE
        jsr     rlong
        lda     z:port                  ; the port empty first
        ldx     #1000
        ldy     #0
        sys     SYS_STIMER
:       lda     z:port
        ora     #RV_POLL
        ptr     msg
        sys     SYS_RECV
        bcc     :-
        lda     #FR_N
        jsr     fr
        jcs     @tbad
        stz     z:t0                    ; the messages waiting now
:       lda     z:port
        ora     #RV_POLL
        ptr     msg
        sys     SYS_RECV
        bcs     :+
        inc     z:t0
        bra     :-
:       lda     #$FFFF
        sys     SYS_STIMER
        lda     #0
        sys     SYS_LISTWAIT
        lda     z:t0
        cmp     #8
        bcc     @tfew
        print   "8 or more messages waiting (the queue full): ok\n"
        bra     gt7
@tfew:  lda     z:t0
        jsr     put_dec
        print   " messages waiting\n"
        bra     gt7
@tbad:  jsr     err

; ---------------------------------------------------------------- 7. another program's page
gt7:    print   "rtest 7: "
        jsr     out_flush
        lda     z:bank
        sep     #$20
        .a8
        sta     karg+1
        lda     #'O'
        sta     karg
        rep     #$20
        .a16
        jsr     kid

; ---------------------------------------------------------------- 8. killed
        print   "rtest 8: a child killed while its lists run, then a list of ours: "
        jsr     out_flush
        lda     #'K'
        sep     #$20
        .a8
        sta     karg
        stz     karg+1
        rep     #$20
        .a16
        jsr     kidk
        lda     z:bank
        ldx     #$5A5A
        jsr     bfill
        lda     z:bank2
        ldx     #$5A5A
        jsr     bfill
        lda     z:bank
        ldx     #0
        jsr     setpage
        stz     frb+FRB_SIZE
        jsr     rruns
        lda     #FR_N
        jsr     fr
        jsr     resv0
        lda     #FR_N
        jsr     cmpref

; ---------------------------------------------------------------- 9. groups
        print   "rtest 9: groups (FR_GROUPS)\n"
        lda     z:bank
        ldx     #$5A5A
        jsr     bfill
        lda     z:bank2
        ldx     #$5A5A
        jsr     bfill
        jsr     mkelems                 ; bank3: elements at $8000, runs at $C000
        lda     z:bank
        ldx     #0
        jsr     setpage
        stz     frb+FRB_SIZE
        lda     #FR_GROUPS
        sta     frb+3                   ; (and the size's low byte: 0)
        print   "  five groups (left and right sides of 5-byte elements, none, 4-byte runs): "
        ldx     #0
        jsr     ldgrp
        lda     #5
        jsr     fr
        jsr     resv
        lda     #5
        jsr     refgrp
        lda     #0
        jsr     cmpref
        print   "  a group in the window: "
        ldx     #1
        jsr     ldgrp
        stz     grp+FRG_ELEMS+2         ; (bank 0)
        jsr     grpout
        lda     #1
        jsr     fr
        jsr     res
        print   "  a group in the kernel's bank: "
        lda     #1
        sta     grp+FRG_ELEMS+2
        jsr     grpout
        lda     #1
        jsr     fr
        jsr     res
        print   "  group 1 with elements past $FF00: "
        ldx     #0
        jsr     ldgrp
        lda     #$FEFC                  ; (the second element at $FF01)
        sta     grp+8+FRG_ELEMS
        lda     #2
        sta     grp+8+FRG_N
        jsr     grpout
        lda     #2
        jsr     fr
        jsr     resx
        print   "  group 0 with 1025 elements: "
        ldx     #0
        jsr     ldgrp
        lda     #1025
        sta     grp+FRG_N
        jsr     grpout
        lda     #1
        jsr     fr
        jsr     resx
        print   "  group 0 with stride 0: "
        ldx     #0
        jsr     ldgrp
        stz     grp+FRG_STRIDE          ; (and the fields: 0)
        jsr     grpout
        lda     #1
        jsr     fr
        jsr     resx
        print   "  three groups of 1000 (more than 2,688 runs): the call takes "
        ldx     #0
        jsr     ldgrp
        lda     #1000
        sta     grp+FRG_N
        sta     grp+8+FRG_N
        sta     grp+16+FRG_N
        lda     #$0100                  ; (rtest 8's runs, 4 bytes each: all inside the page)
        sta     grp+FRG_ELEMS
        sta     grp+8+FRG_ELEMS
        sta     grp+16+FRG_ELEMS
        lda     #4 | $30 << 8
        sta     grp+FRG_STRIDE
        sta     grp+8+FRG_STRIDE
        sta     grp+16+FRG_STRIDE
        jsr     grpout
        lda     #3
        jsr     fr
        jsr     resv
        stz     frb+3
        lda     #0
        sys     SYS_LISTWAIT

done:   lda     z:winb
        sys     SYS_WCLOSE
        sys     SYS_WSSTOP
        print   "rtest: done\n"
        exit    0

; ---------------------------------------------------------------- children
; 'O' + the bank: a page in the parent's bank
child_o:
        lda     f:1,x
        and     #$00FF
        sta     z:bank
        sys     SYS_BALLOC
        sta     z:bank3
        lda     z:bank
        ldx     #0
        jsr     setpage
        lda     #1000
        sta     frb+FRB_SIZE
        jsr     runs8
        print   "a child's list into the parent's bank: "
        lda     #8
        jsr     fr
        jsr     res
        exit    0

; 'K': long lists into its own bank until it is killed
child_k:
        sys     SYS_BALLOC
        sta     z:bank
        sys     SYS_BALLOC
        sta     z:bank3
        lda     z:bank
        ldx     #0
        jsr     setpage
        stz     frb+FRB_SIZE
        jsr     rlong
:       lda     #FR_N
        jsr     fr
        bra     :-

; ---------------------------------------------------------------- the measurement
; "rtest m": 2,688 runs of 23 pixels (SkyRoads' average): the call's time (the kernel making
; the records) and, with list_wait, the whole list's (Ali); 100 runs for the call's own cost
measure:
        sys     SYS_BALLOC
        sta     z:bank
        sys     SYS_BALLOC
        sta     z:bank3
        lda     z:bank
        ldx     #0
        jsr     setpage
        stz     frb+FRB_SIZE
        lda     #23
        sta     z:t4
        jsr     rfix
        lda     #FR_N
        jsr     timed
        print   "rtest m: 2688 runs of 23 pixels: the call "
        jsr     put_us
        print   " us, done "
        lda     z:t2
        jsr     put_dec
        print   " us\n"
        lda     #100
        jsr     timed
        print   "rtest m: 100 runs: the call "
        jsr     put_us
        print   " us, done "
        lda     z:t2
        jsr     put_dec
        print   " us\n"
        lda     #1
        jsr     timed
        print   "rtest m: 1 run: the call "
        jsr     put_us
        print   " us, done "
        lda     z:t2
        jsr     put_dec
        print   " us\n"
        exit    0
put_us: lda     z:t1
        jmp     put_dec
; A runs: t1 = the call's microseconds, t2 = until the list is done
timed:  sta     z:t3
        lda     #0
        sys     SYS_LISTWAIT
        sys     SYS_UPTIMEUS
        sta     z:t0
        lda     z:t3
        jsr     fr
        sys     SYS_UPTIMEUS
        sec
        sbc     z:t0
        sta     z:t1
        lda     #0
        sys     SYS_LISTWAIT
        sys     SYS_UPTIMEUS
        sec
        sbc     z:t0
        sta     z:t2
        rts

; ---------------------------------------------------------------- groups
; bank3 $8000: 200 elements of 5 bytes {left, right, width}: left 300 k, right 300 k + 150,
; width k mod 61 + 1; $C000: 50 runs {offset 1000 k + 7, colour 99 (not used), width 33}
mkelems:
        lda     z:bank3
        sta     z:p+2
        lda     #$8000
        sta     z:p
        stz     z:t0                    ; k
        stz     z:t1                    ; 300 k
@e:     lda     z:t1
        sta     [p]
        clc
        adc     #150
        ldy     #2
        sta     [p],y
        lda     z:t0                    ; k mod 61 + 1
:       cmp     #61
        bcc     :+
        sbc     #61
        bra     :-
:       inc     a
        ldy     #4
        sep     #$20
        .a8
        sta     [p],y
        rep     #$20
        .a16
        lda     z:p
        clc
        adc     #5
        sta     z:p
        lda     z:t1
        clc
        adc     #300
        sta     z:t1
        inc     z:t0
        lda     z:t0
        cmp     #200
        bcc     @e
        lda     #$C000
        sta     z:p
        stz     z:t0
        lda     #7
        sta     z:t1
:       lda     z:t1
        sta     [p]
        lda     #99 | 33 << 8
        ldy     #2
        sta     [p],y
        lda     z:p
        clc
        adc     #4
        sta     z:p
        lda     z:t1
        clc
        adc     #1000
        sta     z:t1
        inc     z:t0
        lda     z:t0
        cmp     #50
        bcc     :-
        rts
; grp <- the 5 groups of table X (0: g5), the elements' bank bank3; then to bank3:$0000
ldgrp:  ldx     #0
:       lda     g5,x
        sta     grp,x
        inx
        inx
        cpx     #5 * 8
        bcc     :-
        ldx     #0
:       sep     #$20
        .a8
        lda     z:bank3
        sta     grp+FRG_ELEMS+2,x
        rep     #$20
        .a16
        txa
        clc
        adc     #8
        tax
        cpx     #5 * 8
        bcc     :-
grpout: lda     z:bank3                 ; grp -> bank3:$0000 (the runs pointer of frb)
        sta     z:p+2
        stz     z:p
        ldy     #0
:       lda     grp,y
        sta     [p],y
        iny
        iny
        cpy     #5 * 8
        bcc     :-
        rts
; the CPU's copy of A groups (from grp) into bank2 + the page's offset
refgrp: sta     z:t3
        ldx     #0
@g:     phx
        lda     grp+FRG_ELEMS,x
        sta     z:p
        lda     grp+FRG_ELEMS+2,x
        and     #$00FF
        sta     z:p+2
        lda     grp+FRG_C,x
        and     #$00FF
        sta     z:t4
        lda     grp+FRG_N,x
        sta     z:t2
        lda     grp+FRG_STRIDE,x
        and     #$00FF
        sta     z:t1
        lda     grp+FRG_FIELDS,x
        and     #$00FF
        sta     z:t0
        lda     z:t2
        beq     @ng
@el:    lda     z:t0                    ; the offset at fields & 15
        and     #$000F
        tay
        lda     [p],y
        clc
        adc     frb+FRB_PAGE
        sta     z:q
        lda     z:bank2
        adc     #0
        sta     z:q+2
        lda     z:t0                    ; the width at fields >> 4
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        tay
        lda     [p],y
        and     #$00FF
        beq     @nx
        tax
        ldy     #0
        sep     #$20
        .a8
        lda     z:t4
:       sta     [q],y
        iny
        dex
        bne     :-
        rep     #$20
        .a16
@nx:    lda     z:p
        clc
        adc     z:t1
        sta     z:p
        dec     z:t2
        bne     @el
@ng:    pla
        clc
        adc     #8
        tax
        dec     z:t3
        bne     @g
        rts

; ---------------------------------------------------------------- helpers
; fill_runs with A runs and the block frb
fr:     ldx     #.loword(frb)
        ldy     #^frb
        sys     SYS_FILLRUNS
        rts
; the page: bank A, offset X (the size and the runs stay)
setpage:
        stx     frb+FRB_PAGE
        sep     #$20
        .a8
        sta     frb+FRB_PAGE+2
        rep     #$20
        .a16
        lda     z:bank3
        sta     frb+FRB_RUNS+2          ; (and the byte after it: 0)
        stz     frb+FRB_RUNS
        rts
; p -> run X in the runs' bank
runp:   txa
        asl     a
        asl     a
        sta     z:p
        lda     z:bank3
        sta     z:p+2
        rts
; run X's offset = A
setofs: pha
        jsr     runp
        pla
        sta     [p]
        rts
; run A's width = X
setw:   phx
        tax
        jsr     runp
        pla
        sep     #$20
        .a8
        ldy     #FRR_W
        sta     [p],y
        rep     #$20
        .a16
        rts
; 8 runs: offset 100 k, colour k + 1, width 10
runs8:  ldx     #0
:       phx
        jsr     runp
        lda     1,s
        asl     a                       ; 100 k = 64 k + 32 k + 4 k
        asl     a
        sta     z:t0
        asl     a
        asl     a
        asl     a
        sta     z:t1
        asl     a
        clc
        adc     z:t1
        adc     z:t0
        sta     [p]
        lda     1,s
        inc     a
        and     #$00FF
        ora     #10 << 8
        ldy     #FRR_C
        sta     [p],y
        plx
        inx
        cpx     #8
        bcc     :-
        rts
; one run: offset X, colour X + 1, width 1 (run 0)
runs1:  phx
        ldx     #0
        jsr     runp
        plx
        txa
        sta     [p]
        inc     a
        ora     #1 << 8
        ldy     #FRR_C
        sta     [p],y
        rts
; the CPU's copy of the 12 single runs: bank2 $3000 + k = k + 1
ref1:   lda     z:bank2
        sta     z:p+2
        lda     #$3000
        sta     z:p
        ldy     #0
        sep     #$20
        .a8
:       tya
        inc     a
        sta     [p],y
        iny
        cpy     #12
        bcc     :-
        rep     #$20
        .a16
        rts
; 2,688 random runs inside 65,536 bytes: offset < 65,281, width 0-255, colour 0-255
rruns:  ldx     #0
:       phx
        jsr     runp
        jsr     rand
        cmp     #65281
        bcc     :+
        sbc     #65281
:       sta     [p]
        jsr     rand
        ldy     #FRR_C
        sta     [p],y
        plx
        inx
        cpx     #FR_N
        bcc     :--
        rts
; 2,688 runs of t4 pixels, 24 apart, colour 7
rfix:   ldx     #0
        stz     z:t0
:       phx
        jsr     runp
        lda     z:t0
        sta     [p]
        clc
        adc     #24
        sta     z:t0
        lda     z:t4
        xba
        ora     #7
        ldy     #FRR_C
        sta     [p],y
        plx
        inx
        cpx     #FR_N
        bcc     :-
        rts
; 2,688 runs of 255 pixels, 24 apart (they overlap), colour 9
rlong:  lda     #255
        sta     z:t4
        jsr     rfix
        rts
; 180 runs: row r (320 bytes) from x = r, 100 wide, colour r
rows:   ldx     #0
        stz     z:t0
:       phx
        jsr     runp
        lda     1,s
        clc
        adc     z:t0
        sta     [p]
        lda     1,s
        ora     #100 << 8
        ldy     #FRR_C
        sta     [p],y
        lda     z:t0
        clc
        adc     #320
        sta     z:t0
        plx
        inx
        cpx     #180
        bcc     :-
        rts
; xorshift16 -> A
rand:   lda     z:rnd
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        eor     z:rnd
        sta     z:rnd
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        eor     z:rnd
        sta     z:rnd
        xba
        and     #$FF00
        eor     z:rnd
        sta     z:rnd
        rts
; bank A filled with the word X
bfill:  sta     z:p+2
        stz     z:p
        txa
        ldy     #0
:       sta     [p],y
        iny
        iny
        bne     :-
        rts
; the runs (A of them: 0 none) applied by the CPU to bank2 (at the page's offset), then
; bank and bank2 compared: "  the same as the CPU's: ok" or where they differ
cmpref: jsr     refrun
        lda     #0
        sys     SYS_LISTWAIT
        lda     z:bank
        sta     z:p+2
        lda     z:bank2
        sta     z:q+2
        stz     z:p
        stz     z:q
        ldy     #0
:       lda     [p],y
        cmp     [q],y
        bne     @diff
        iny
        iny
        bne     :-
        print   "  the same as the CPU's: ok\n"
        rts
@diff:  phy
        print   "  differs from the CPU's at $"
        lda     1,s
        jsr     put_hex16
        print   ": Ali $"
        ply
        phy
        lda     [p],y
        jsr     put_hex16
        print   ", CPU $"
        ply
        lda     [q],y
        jsr     put_hex16
        jmp     put_nl
; A runs from the runs' bank applied by the CPU to bank2 + the page's offset
refrun: sta     z:t1
        cmp     #0
        beq     @out
        stz     z:t2                    ; the run's offset in the runs' bank
@run:   lda     z:bank3
        sta     z:p+2
        lda     z:t2
        sta     z:p
        lda     [p]                   ; offset
        clc
        adc     frb+FRB_PAGE
        sta     z:q
        lda     z:bank2
        adc     #0
        sta     z:q+2
        ldy     #FRR_C
        lda     [p],y
        sta     z:t0                    ; colour | width << 8
        xba
        and     #$00FF
        beq     @next
        tax
        ldy     #0
        sep     #$20
        .a8
        lda     z:t0
:       sta     [q],y
        iny
        dex
        bne     :-
        rep     #$20
        .a16
@next:  lda     z:t2
        clc
        adc     #4
        sta     z:t2
        dec     z:t1
        bne     @run
@out:   rts

; "ok" / "error NN"
res:    bcs     err
        print   "ok\n"
        rts
; "A" / "error NN"
resv:   bcs     err
        jsr     put_dec
        jmp     put_nl
; "ok" / "error NN" (A not shown)
resv0:  bcs     err
        print   "ok\n"
        rts
; "error NN, run X"
resx:   bcs     :+
        print   "accepted\n"
        rts
:       phx
        jsr     put_err
        print   ", X = "
        pla
        jsr     put_dec
        jmp     put_nl
err:    jsr     put_err
        jmp     put_nl
put_err:
        pha
        print   "error "
        pla
        jmp     put_hex8

; a child with the argument karg, waited for
kid:    lda     #.loword(karg)
        sta     z:u_arg
        lda     #^karg
        sta     z:u_arg+2
        ptr     p_self
        lda     #1
        jsr     spawn
        bcs     :+
        sys     SYS_WAIT
:       rts
; the same, killed after 0.3 s
kidk:   lda     #.loword(karg)
        sta     z:u_arg
        lda     #^karg
        sta     z:u_arg+2
        ptr     p_self
        lda     #1
        jsr     spawn
        bcs     :+
        sta     z:t0
        lda     #300
        sys     SYS_SLEEP
        lda     z:t0
        sys     SYS_KILL
        lda     z:t0
        sys     SYS_WAIT
:       rts

        .segment "DATA"
p_self: .byte   "/SYSTEM/TESTS/RTEST.PRG", 0
t_b:    .byte   "Full screen", 0
wb:     .word   300, 60, 240, 120
        .faraddr t_b
        .byte   0
frb:    .faraddr 0                      ; fill_runs' block: the page, 0, size, the runs, 0
        .byte   0
        .word   0
        .faraddr 0
        .byte   0
fsb:    .byte   FS_320X8, 0             ; fs_enter: 320 x 180 x 8 at bank:0000
        .word   320, 180
        .faraddr 0
        .byte   0
; rtest 3's runs {offset, colour, width} (page offsets; the page is 8,000 bytes)
r3:     .word   0,    1 | 10 << 8       ; the page's first byte
        .word   100,  2 | 0 << 8        ; width 0
        .word   7999, 3 | 1 << 8        ; its last byte
        .word   7745, 4 | 255 << 8      ; width 255 to the end
        .word   200,  5 | 50 << 8       ; three over each other, in order
        .word   220,  6 | 50 << 8
        .word   210,  7 | 5 << 8
        .word   1001, 8 | 1 << 8        ; odd and even starts and widths
        .word   1002, 9 | 2 << 8
        .word   1005, 10 | 3 << 8
        .word   1008, 11 | 4 << 8
        .word   4000, 0 | 200 << 8      ; colour 0
        .word   4300, 255 | 199 << 8    ; colour 255
        .word   8000, 12 | 0 << 8       ; width 0 at the page's end
R3N = (* - r3) / 4
; rtest 9's groups {u24 elements (bank set at run time), u8 colour, u16 count, u8 stride,
; u8 fields}
g5:     .word   $8000                   ; elements 0-99, their left offsets, colour 3
        .byte   0, 3
        .word   100
        .byte   5, $40
        .word   $8000 + 100 * 5         ; elements 100-199, right offsets, colour 4
        .byte   0, 4
        .word   100
        .byte   5, $42
        .word   $8000                   ; elements 0-99 again, right offsets, colour 5
        .byte   0, 5
        .word   100
        .byte   5, $42
        .word   $8000                   ; none
        .byte   0, 6
        .word   0
        .byte   5, $40
        .word   $C000                   ; 50 runs of fill_runs' own layout: colour 7 (theirs: 99)
        .byte   0, 7
        .word   50
        .byte   4, $30
karg:   .byte   0, 0, 0

        .segment "BSS"
msg:    .res    16
grp:    .res    5 * 8

        .segment "ZEROPAGE"
alen:   .res    2
argp:   .res    2
winb:   .res    2
rev:    .res    2
bank:   .res    2
bank2:  .res    2
bank3:  .res    2
port:   .res    2
rnd:    .res    2
t0:     .res    2
t1:     .res    2
t2:     .res    2
t3:     .res    2
t4:     .res    2
p:      .res    4
q:      .res    4

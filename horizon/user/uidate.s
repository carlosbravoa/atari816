; uidate.s - controls library (0.14): the date and time. The kernel keeps a clock in seconds
; since 2000-01-01 00:00 (SYS_TGET / SYS_TSET); these routines turn it into a calendar date
; and back, and keep the last value in /SYSTEM/CLOCK (one line "YYYY-MM-DD HH:MM:SS"), since
; the board has no battery clock. Self-contained (its own zero page): the shell links it too.
; See ui.inc.
        .include "horizon.inc"
        .include "ui.inc"

        .segment "CODE"
        .a16
        .i16

; A = seconds low, X = high -> ui_clk: year, month, day, hour, minute, second, weekday
ui_clksplit:
        sta     z:cd_lo
        stx     z:cd_hi
        lda     #60
        jsr     cd_div
        sta     ui_clk + CK_SEC
        lda     #60
        jsr     cd_div
        sta     ui_clk + CK_MIN
        lda     #24
        jsr     cd_div
        sta     ui_clk + CK_HOUR
        lda     z:cd_lo                 ; days since 2000-01-01 (a Saturday)
        sta     z:cd_n
        clc
        adc     #6
        sta     z:cd_lo
        stz     z:cd_hi
        lda     #7
        jsr     cd_div
        sta     ui_clk + CK_WDAY
        lda     #2000
        sta     ui_clk + CK_YEAR
@y:     jsr     cd_ylen
        cmp     z:cd_n
        beq     :+
        bcs     @m
:       eor     #$FFFF
        sec
        adc     z:cd_n
        sta     z:cd_n
        inc     ui_clk + CK_YEAR
        bra     @y
@m:     lda     #1
        sta     ui_clk + CK_MON
:       lda     ui_clk + CK_MON
        jsr     ui_clkmdays
        cmp     z:cd_n
        beq     :+
        bcs     @d
:       eor     #$FFFF
        sec
        adc     z:cd_n
        sta     z:cd_n
        inc     ui_clk + CK_MON
        bra     :--
@d:     lda     z:cd_n
        inc     a
        sta     ui_clk + CK_DAY
        rts

; ui_clk (year .. second) -> A = seconds low, X = high (the weekday is set too)
ui_clkjoin:
        stz     z:cd_n                  ; days
        lda     #2000
        sta     z:cd_y
@y:     lda     z:cd_y
        cmp     ui_clk + CK_YEAR
        bcs     @m
        jsr     cd_ylen0
        clc
        adc     z:cd_n
        sta     z:cd_n
        inc     z:cd_y
        bra     @y
@m:     lda     #1
        sta     z:cd_y
:       lda     z:cd_y
        cmp     ui_clk + CK_MON
        bcs     :+
        jsr     ui_clkmdays
        clc
        adc     z:cd_n
        sta     z:cd_n
        inc     z:cd_y
        bra     :-
:       lda     ui_clk + CK_DAY
        dec     a
        clc
        adc     z:cd_n
        sta     z:cd_lo
        stz     z:cd_hi
        lda     #24
        ldx     ui_clk + CK_HOUR
        jsr     cd_madd
        lda     #60
        ldx     ui_clk + CK_MIN
        jsr     cd_madd
        lda     #60
        ldx     ui_clk + CK_SEC
        jsr     cd_madd
        lda     z:cd_lo
        ldx     z:cd_hi
        pha
        phx
        jsr     ui_clksplit             ; (the weekday; the rest stays the same)
        plx
        pla
        rts

; A = month (1-12) of the year in ui_clk -> A = its days
ui_clkmdays:
        tax
        lda     cd_mtab - 1,x
        and     #$00FF
        cpx     #2
        bne     :+
        pha
        lda     ui_clk + CK_YEAR
        jsr     cd_leap
        pla
        adc     #0                      ; (C set: a leap year)
:       rts

; the days of year ui_clk (cd_ylen) or cd_y (cd_ylen0) -> A
cd_ylen:
        lda     ui_clk + CK_YEAR
        bra     :+
cd_ylen0:
        lda     z:cd_y
:       jsr     cd_leap
        lda     #365
        adc     #0
        rts

; A = year -> C set if a leap year
cd_leap:
        sta     z:cd_t
        and     #3
        bne     @no
        lda     z:cd_t
        ldx     #100
        jsr     cd_mod
        cmp     #0
        bne     @yes
        lda     z:cd_t
        ldx     #400
        jsr     cd_mod
        cmp     #0
        bne     @no
@yes:   sec
        rts
@no:    clc
        rts

; A mod X (16 bit) -> A
cd_mod: stx     z:cd_d
        sta     z:cd_q
        lda     #0
        ldx     #16
:       asl     z:cd_q
        rol     a
        cmp     z:cd_d
        bcc     :+
        sbc     z:cd_d
:       dex
        bne     :--
        rts

; cd_hi:cd_lo / A -> cd_hi:cd_lo, A = the remainder
cd_div: sta     z:cd_d
        lda     #0
        ldx     #32
:       asl     z:cd_lo
        rol     z:cd_hi
        rol     a
        cmp     z:cd_d
        bcc     :+
        sbc     z:cd_d
        inc     z:cd_lo
:       dex
        bne     :--
        rts

; cd_hi:cd_lo = cd_hi:cd_lo * A + X
cd_madd:
        stx     z:cd_q
        sta     z:cd_d
        lda     z:cd_lo
        sta     z:cd_t
        lda     z:cd_hi
        sta     z:cd_t2
        stz     z:cd_lo
        stz     z:cd_hi
@b:     lsr     z:cd_d
        bcc     :+
        lda     z:cd_lo
        clc
        adc     z:cd_t
        sta     z:cd_lo
        lda     z:cd_hi
        adc     z:cd_t2
        sta     z:cd_hi
:       asl     z:cd_t
        rol     z:cd_t2
        lda     z:cd_d
        bne     @b
        lda     z:cd_lo
        clc
        adc     z:cd_q
        sta     z:cd_lo
        bcc     :+
        inc     z:cd_hi
:       rts

; Y = buffer: ui_clk as "YYYY-MM-DD HH:MM:SS" (zero-terminated) -> A = 19
ui_clkfmt:
        sty     z:cd_p
        lda     ui_clk + CK_YEAR
        ldx     #1000
        jsr     cd_dig
        ldx     #100
        jsr     cd_dig
        ldx     #10
        jsr     cd_dig
        jsr     cd_dig1
        lda     #'-'
        ldy     #CK_MON
        jsr     cd_sep2
        lda     #'-'
        ldy     #CK_DAY
        jsr     cd_sep2
        lda     #' '
        ldy     #CK_HOUR
        jsr     cd_sep2
        lda     #':'
        ldy     #CK_MIN
        jsr     cd_sep2
        lda     #':'
        ldy     #CK_SEC
        jsr     cd_sep2
        lda     #0
        jsr     cd_put
        lda     #19
        rts
; the character A, then field Y as two digits
cd_sep2:
        jsr     cd_put
        lda     ui_clk,y
        ldx     #10
        jsr     cd_dig
cd_dig1:
        clc
        adc     #'0'
        bra     cd_put
; A = value: its digit of weight X out -> A = the rest
cd_dig: stx     z:cd_d
        ldx     #0
:       cmp     z:cd_d
        bcc     :+
        sbc     z:cd_d
        inx
        bra     :-
:       pha
        txa
        clc
        adc     #'0'
        jsr     cd_put
        pla
        rts
cd_put: sep     #$20
        .a8
        sta     (cd_p)
        rep     #$20
        .a16
        inc     z:cd_p
        rts

; Y = buffer: ui_clk as "Tuesday, 17 November 2026" (zero-terminated)
ui_clklong:
        sty     z:cd_p
        lda     ui_clk + CK_WDAY
        asl     a
        tax
        lda     cd_wdays,x
        jsr     cd_puts
        lda     #','
        jsr     cd_put
        lda     #' '
        jsr     cd_put
        lda     ui_clk + CK_DAY
        cmp     #10
        bcc     :+
        ldx     #10
        jsr     cd_dig
:       jsr     cd_dig1
        lda     #' '
        jsr     cd_put
        lda     ui_clk + CK_MON
        asl     a
        tax
        lda     cd_months - 2,x
        jsr     cd_puts
        lda     #' '
        jsr     cd_put
        lda     ui_clk + CK_YEAR
        ldx     #1000
        jsr     cd_dig
        ldx     #100
        jsr     cd_dig
        ldx     #10
        jsr     cd_dig
        jsr     cd_dig1
        lda     #0
        jmp     cd_put
; the string at A (program bank) out
cd_puts:
        sta     z:cd_q
:       lda     (cd_q)
        and     #$00FF
        beq     :+
        jsr     cd_put
        inc     z:cd_q
        bra     :-
:       rts

; X = string "YYYY-MM-DD HH:MM[:SS]" (any non-digits between the numbers) -> ui_clk;
; C set: not a valid date and time (ui_clk then undefined)
ui_clkparse:
        stx     z:cd_p
        ldy     #0                      ; the numbers (6 at most)
@num:   lda     (cd_p)                  ; skip to a digit
        and     #$00FF
        beq     @end
        cmp     #'0'
        bcc     @sk
        cmp     #'9' + 1
        bcc     @dg
@sk:    inc     z:cd_p
        bra     @num
@dg:    cpy     #12
        jcs     cd_bad
        lda     #0
        sta     ui_clk,y
:       lda     (cd_p)
        and     #$00FF
        cmp     #'0'
        bcc     :+
        cmp     #'9' + 1
        bcs     :+
        pha
        lda     ui_clk,y                ; * 10 + digit
        asl     a
        sta     z:cd_t
        asl     a
        asl     a
        clc
        adc     z:cd_t
        sta     z:cd_t
        pla
        sec
        sbc     #'0'
        clc
        adc     z:cd_t
        sta     ui_clk,y
        cmp     #10000
        bcs     cd_bad
        inc     z:cd_p
        bra     :-
:       iny
        iny
        bra     @num
@end:   cpy     #10                     ; 5 or 6 numbers (no seconds: 0)
        bcc     cd_bad
        bne     :+
        lda     #0
        sta     ui_clk + CK_SEC
:       ; fall through
; C set if ui_clk is not a valid date and time (2000-01-01 .. 2135-12-31)
ui_clkcheck:
        lda     ui_clk + CK_YEAR
        cmp     #2000
        bcc     @bad
        cmp     #2136
        bcs     @bad
        lda     ui_clk + CK_MON
        beq     @bad
        cmp     #13
        bcs     @bad
        jsr     ui_clkmdays
        cmp     ui_clk + CK_DAY
        bcc     @bad
        lda     ui_clk + CK_DAY
        beq     @bad
        lda     ui_clk + CK_HOUR
        cmp     #24
        bcs     @bad
        lda     ui_clk + CK_MIN
        cmp     #60
        bcs     @bad
        lda     ui_clk + CK_SEC
        cmp     #60
        bcs     @bad
        clc
        rts
@bad:
cd_bad: sec
        rts

; the clock not set yet: the value saved in /SYSTEM/CLOCK becomes its provisional start
; (CLK_SAVED). C set: nothing loaded (set already, no file, or not a date).
ui_clkload:
        sys     SYS_TGET
        cpy     #CLK_NONE
        bne     @no
        ptr     cd_path
        lda     #O_READ
        sys     SYS_OPEN
        bcs     @no
        sta     z:cd_t
        sta     cd_rw
        lda     #.loword(cd_buf)
        sta     cd_rw+1
        lda     #^cd_buf
        sta     cd_rw+3
        lda     #CD_BUFL - 1
        sta     cd_rw+4
        ptr     cd_rw
        sys     SYS_READ
        php
        pha
        lda     z:cd_t
        sys     SYS_CLOSE
        pla
        plp
        bcs     @no
        tax
        sep     #$20
        .a8
        stz     cd_buf,x
        rep     #$20
        .a16
        ldx     #.loword(cd_buf)
        jsr     ui_clkparse
        bcs     @no
        jsr     ui_clkjoin
        ldy     #CLK_SAVED
        sys     SYS_TSET
        clc
        rts
@no:    sec
        rts

; the clock (if it was ever set or loaded) saved to /SYSTEM/CLOCK. C set: not saved.
ui_clksave:
        sys     SYS_TGET
        cpy     #CLK_NONE
        beq     @no
        jsr     ui_clksplit
        ldy     #.loword(cd_buf)
        jsr     ui_clkfmt
        lda     #10                     ; "...\n"
        sta     cd_buf + 19
        ptr     cd_path
        lda     #O_CREATE
        sys     SYS_OPEN
        bcs     @no
        sta     z:cd_t
        sta     cd_rw
        lda     #.loword(cd_buf)
        sta     cd_rw+1
        lda     #^cd_buf
        sta     cd_rw+3
        lda     #20
        sta     cd_rw+4
        ptr     cd_rw
        sys     SYS_WRITE
        php
        lda     z:cd_t
        sys     SYS_CLOSE
        plp
        rts
@no:    sec
        rts

        .segment "RODATA"
cd_mtab: .byte  31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
cd_path: .byte  "/SYSTEM/CLOCK", 0
cd_wdays: .addr cd_d0, cd_d1, cd_d2, cd_d3, cd_d4, cd_d5, cd_d6
cd_months: .addr cd_m1, cd_m2, cd_m3, cd_m4, cd_m5, cd_m6, cd_m7, cd_m8, cd_m9, cd_m10, cd_m11, cd_m12
cd_d0:  .byte   "Sunday", 0
cd_d1:  .byte   "Monday", 0
cd_d2:  .byte   "Tuesday", 0
cd_d3:  .byte   "Wednesday", 0
cd_d4:  .byte   "Thursday", 0
cd_d5:  .byte   "Friday", 0
cd_d6:  .byte   "Saturday", 0
cd_m1:  .byte   "January", 0
cd_m2:  .byte   "February", 0
cd_m3:  .byte   "March", 0
cd_m4:  .byte   "April", 0
cd_m5:  .byte   "May", 0
cd_m6:  .byte   "June", 0
cd_m7:  .byte   "July", 0
cd_m8:  .byte   "August", 0
cd_m9:  .byte   "September", 0
cd_m10: .byte   "October", 0
cd_m11: .byte   "November", 0
cd_m12: .byte   "December", 0

        .segment "BSS"
CD_BUFL = 32
ui_clk: .res    14                      ; CK_* fields (ui.inc)
cd_buf: .res    CD_BUFL + 2
cd_rw:  .res    6

        .segment "ZEROPAGE"
cd_lo:  .res    2
cd_hi:  .res    2
cd_d:   .res    2
cd_q:   .res    2
cd_t:   .res    2
cd_t2:  .res    2
cd_n:   .res    2
cd_y:   .res    2
cd_p:   .res    2

; APSCAN - (0.29) measures what the Desktop does with /APPS when it reads its Programs menu
; (make test-29, not on the card): the full scan (READDIR of /APPS, each folder's APP.INF
; through ui_appinf, as desk.s's appscan). Prints its time (uptime, ms). (0.31: the quick
; check of 0.29 and 0.30, a READDIR of /APPS and a STAT of /SYSTEM/APPS.NEW each time the
; menu opened, is gone: the menu is kept, read at the start and when the apps change.)
        .include "horizon.inc"
        .include "ui.inc"

        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_UPTIME
        sta     z:t0
        stz     z:napp
        stz     z:skip
@call:  jsr     rd                      ; the full scan
        bcs     @full
        ldx     #0
@ent:   stx     z:dp
        lda     dbuf+4,x
        and     #$0010
        beq     @nx
        ldy     #0                      ; "/APPS/" + the name
:       lda     s_apps,y
        sta     pth,y
        iny
        cpy     #6
        bcc     :-
        lda     dbuf+5,x
        and     #$00FF
        sta     z:n
        ldy     #6
        sep     #$20
        .a8
:       lda     dbuf+6,x
        sta     pth,y
        inx
        iny
        dec     z:n
        bne     :-
        lda     #0
        sta     pth,y
        rep     #$20
        .a16
        ldx     #.loword(pth)
        jsr     ui_appinf
        bcs     @nx
        inc     z:napp
@nx:    ldx     z:dp
        lda     dbuf+5,x
        and     #$00FF
        clc
        adc     #6
        adc     z:dp
        tax
        dec     z:cnt
        bne     @ent
        bra     @call
@full:  sys     SYS_UPTIME
        sec
        sbc     z:t0
        sta     z:t1
        print   "apscan: "
        lda     z:napp
        jsr     put_dec
        print   " apps; full scan "
        lda     z:t1
        jsr     put_dec
        print   " ms\n"
        exit    0

; the next entries of /APPS -> dbuf, cnt; C set: no more
rd:     lda     #.loword(s_apps0)
        sta     rb
        lda     #^s_apps0
        sta     rb+2
        lda     #.loword(dbuf)
        sta     rb+3
        lda     #^dbuf
        sta     rb+5
        lda     #638
        sta     rb+6
        lda     z:skip
        sta     rb+8
        ptr     rb
        sys     SYS_READDIR
        bcs     @no
        cmp     #0
        beq     @no
        sta     z:cnt
        clc
        adc     z:skip
        sta     z:skip
        clc
        rts
@no:    sec
        rts

        .segment "RODATA"
s_apps: .byte   "/APPS/"
s_apps0: .byte  "/APPS", 0

        .segment "BSS"
dbuf:   .res    640
pth:    .res    130
rb:     .res    10

        .segment "ZEROPAGE"
t0:     .res    2
t1:     .res    2
napp:   .res    2
skip:   .res    2
cnt:    .res    2
dp:     .res    2
n:      .res    2

; PROBE - the measurements of docs/reference/performance.md: opens a 400 x 300 window, prints
; its content position (win_info), then times a CPU loop, a null syscall and win_draw ops
; (each N times, then ws_sync) with SYS_UPTIME, and prints the results on the console.
; make -C sdk probe (add REV=7 for a board without the blitter). Not a program to copy:
; it draws garbage on purpose (it blits its own code as pixels).
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_WSSTART
        ptr     wo
        sys     SYS_WOPEN
        sta     z:win
        ptr     info
        lda     z:win
        sys     SYS_WINFO
        print   "content x,y,w,h: "
        lda     info
        jsr     put_dec
        print   " "
        lda     info+2
        jsr     put_dec
        print   " "
        lda     info+4
        jsr     put_dec
        print   " "
        lda     info+6
        jsr     put_dec
        jsr     put_nl
        sys     SYS_WSSYNC
        ; cpu loop: 65536 x (dex, bne) = 5 cycles each, then 10 times
        jsr     t0
        lda     #10
        sta     z:n
@cl:    ldx     #0
:       dex
        bne     :-
        dec     z:n
        bne     @cl
        print   "cpu 3,276,800 cycles: "
        jsr     t1
        ; null syscall
        jsr     t0
        lda     #1000
        sta     z:n
:       sys     SYS_GETPID
        dec     z:n
        bne     :-
        print   "1000 getpid: "
        jsr     t1
        ; 1000 fills 1x1
        lda     #WD_FILL | (C_RED << 8)
        sta     blk
        lda     #1
        sta     blk+8
        sta     blk+10
        lda     #1000
        jsr     many
        print   "1000 fill 1x1: "
        jsr     t1
        ; 1000 fills 16x16
        lda     #16
        sta     blk+8
        sta     blk+10
        lda     #1000
        jsr     many
        print   "1000 fill 16x16: "
        jsr     t1
        ; 100 fills 320x200
        lda     #320
        sta     blk+8
        lda     #200
        sta     blk+10
        lda     #100
        jsr     many
        print   "100 fill 320x200: "
        jsr     t1
        ; 1000 kblit 16x16
        lda     #WD_KBLIT
        sta     blk
        lda     #16
        sta     blk+8
        sta     blk+10
        lda     #.loword(img)
        sta     blk+12
        lda     #^img
        sta     blk+14
        lda     #1000
        jsr     many
        print   "1000 kblit 16x16: "
        jsr     t1
        lda     #WD_BLIT
        sta     blk
        lda     #1000
        jsr     many
        print   "1000 blit 16x16: "
        jsr     t1
        ; 100 blit 320x200 (from the code bank: junk pixels, fine)
        lda     #320
        sta     blk+8
        lda     #200
        sta     blk+10
        lda     #0
        sta     blk+12
        lda     #100
        jsr     many
        print   "100 blit 320x200: "
        jsr     t1
        lda     #WD_KBLIT
        sta     blk
        lda     #100
        jsr     many
        print   "100 kblit 320x200: "
        jsr     t1
        ; 100 copy 320x200
        lda     #WD_COPY
        sta     blk
        lda     #4
        sta     blk+1
        lda     #2
        sta     blk+12
        lda     #100
        jsr     many
        print   "100 copy 320x200: "
        jsr     t1
        ; 100 text 20 chars UI font, paper
        lda     #WD_TEXT | (C_BLACK << 8)
        sta     blk
        lda     #C_BODY
        sta     blk+2
        lda     #.loword(txt)
        sta     blk+12
        lda     #^txt
        sta     blk+14
        lda     #100
        jsr     many
        print   "100 text 20ch ui: "
        jsr     t1
        lda     #C_BODY | $100
        sta     blk+2
        lda     #100
        jsr     many
        print   "100 text 20ch fixed: "
        jsr     t1
        ; full window 640x344 plain? sync
        jsr     t0
        lda     #100
        sta     z:n
:       sys     SYS_WSSYNC
        dec     z:n
        bne     :-
        print   "100 ws_sync idle: "
        jsr     t1
        sys     SYS_WSSTOP
        exit    0

many:   sta     z:n
        jsr     t0
:       lda     z:win
        ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_WDRAW
        bcs     @err
        dec     z:n
        bne     :-
        sys     SYS_WSSYNC
        rts
@err:   print   "draw error "
        jsr     put_dec
        jsr     put_nl
        rts
t0:     sys     SYS_UPTIME
        sta     z:tm
        rts
t1:     sys     SYS_UPTIME
        sec
        sbc     z:tm
        jsr     put_dec
        print   " ms\n"
        rts

        .segment "RODATA"
wo:     .word   10, 20, 400, 300
        .faraddr title
        .byte   0
title:  .byte   "Probe", 0
txt:    .byte   "Twenty chars of text", 0
img:    .res    256, $55
        .segment "BSS"
blk:    .res    16
info:   .res    8
        .segment "ZEROPAGE"
win:    .res    2
n:      .res    2
tm:     .res    2

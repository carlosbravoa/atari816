; ABOUT - the "About Horizon" window (/SYSTEM/ABOUT.PRG): the machine (three lines), then
; Horizon's version, the processor, the custom chips (0.16: Marga, the video chip; Ali, the
; blitter; POKEY 2 and Lau, the sample player, as far as the hardware revision has them),
; the memory, the tasks, the time since start and the date, refreshed once a second, and a
; last small line (not affiliated with Atari). The close box, Esc or Enter close it.
; One instance only: started again, it raises the open one (SYS_SINGLE).
        .include "horizon.inc"
        .include "ui.inc"

W       = 300                           ; content size
H       = 210
YU      = 132                           ; the first line that changes (memory)

        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_SINGLE              ; one About only: the kernel raised the open one
        bcc     :+
        exit    0
:       sys     SYS_WSSTART
        jcs     fail
        sta     z:own
        ptr     wblk
        sys     SYS_WOPEN
        jcs     fail
        sta     z:win
        lda     #0                      ; (default drawing mode; tells if the blitter is used
        sys     SYS_WSCONFIG            ; and, 0.16, X = the hardware revision)
        sta     z:blit
        stx     z:rev
        ldx     #0                      ; the stripes: eight colours of the cube, left
:       phx
        txa
        asl     a
        tax
        lda     stripes,x
        xba
        ora     #WD_FILL
        sta     blk
        lda     #0
        sta     blk+4
        plx
        phx
        txa                             ; y = 8 + 8 i, 18 x 6
        asl     a
        asl     a
        asl     a
        clc
        adc     #8
        sta     blk+6
        lda     #18
        sta     blk+8
        lda     #6
        sta     blk+10
        jsr     draw
        plx
        inx
        cpx     #8
        bne     :-
        lda     #30                     ; the fixed lines: the machine (its name in the
        ldx     #6                      ; heading style), then the system
        ldy     #1
        jsr     textat
        .addr   t_title
        lda     #30
        ldx     #24
        ldy     #0
        jsr     textat
        .addr   t_sys
        lda     #30
        ldx     #38
        ldy     #0
        jsr     textat
        .addr   t_sys2
        lda     #30
        ldx     #58
        ldy     #0
        jsr     textat
        .addr   t_ver
        lda     #30
        ldx     #72
        ldy     #0
        jsr     textat
        .addr   t_cpu
        lda     #30
        ldx     #86
        ldy     #0
        jsr     textat
        .addr   t_gfx
        ldx     #.loword(t_blit_on)     ; the blitter: Ali, or the CPU draws
        lda     z:blit
        bne     :+
        ldx     #.loword(t_blit_off)
:       stx     z:sc
        lda     #30
        ldx     #100
        ldy     #0
        jsr     textat_p
        ldx     #.loword(t_snd_none)    ; the sound: POKEY 2 from REV $07, Lau from $0A
        lda     z:rev
        cmp     #$07
        bcc     :+
        ldx     #.loword(t_snd_p2)
        cmp     #$0A
        bcc     :+
        ldx     #.loword(t_snd_lau)
:       stx     z:sc
        lda     #30
        ldx     #114
        ldy     #0
        jsr     textat_p
        lda     #30                     ; the last line, small and grey
        ldx     #YU + 62
        ldy     #2
        jsr     textat
        .addr   t_note
        jsr     update
        lda     z:win
        ldx     #100
        sys     SYS_WTIMER

loop:   lda     #0
        ptr     ev
        sys     SYS_WEVENT
        bcs     loop
        lda     ev
        and     #$00FF
        cmp     #WE_CLOSE
        beq     done
        cmp     #WE_TICK
        bne     :+
        jsr     update
        bra     loop
:       cmp     #WE_KEY
        bne     loop
        lda     ev+4                    ; Esc or Enter (down)
        and     #$0100
        beq     loop
        lda     ev+2
        cmp     #$29
        beq     done
        cmp     #$28
        bne     loop
done:   lda     z:win
        sys     SYS_WCLOSE
        lda     z:own
        beq     :+
        sys     SYS_WSSTOP
:       exit    0

fail:   print   "about: no window system\n"
        exit    1

; the lines that change: memory, tasks, time
update: ldy     #0                      ; "Memory: F of T KB free"
        jsr     cpys
        .addr   s_mem
        sys     SYS_MINFO               ; A = free banks, X = total
        phx
        jsr     kb
        jsr     cpys
        .addr   s_of
        pla
        jsr     kb
        jsr     cpys
        .addr   s_kb
        lda     #YU
        jsr     line
        ldy     #0                      ; "Tasks: N"
        jsr     cpys
        .addr   s_tasks
        phy                             ; (ptr uses Y)
        stz     z:t
        stz     z:n
:       lda     z:t
        ptr     info
        sys     SYS_TINFO
        bcs     :+
        lda     info
        and     #$00FF
        beq     :+
        inc     z:n
:       inc     z:t
        lda     z:t
        cmp     #16
        bcc     :--
        ply
        lda     z:n
        jsr     num
        lda     #YU + 14
        jsr     line
        ldy     #0                      ; "Up: S s"
        jsr     cpys
        .addr   s_up
        sys     SYS_UPTIME
        sta     z:lo
        stx     z:hi
        jsr     div1000
        lda     z:lo
        jsr     num
        jsr     cpys
        .addr   s_s
        lda     #YU + 28
        jsr     line
        ldy     #0                      ; (0.14) "Date: Tuesday, 17 November 2026, 14:05"
        jsr     cpys
        .addr   s_date
        phy
        sys     SYS_TGET
        cpy     #CLK_SET
        beq     :+
        ply
        jsr     cpys
        .addr   s_noclk
        bra     @dl
:       jsr     ui_clksplit
        lda     1,s
        clc
        adc     #.loword(buf)
        tay
        jsr     ui_clklong
        ldy     #.loword(buf + 40)
        jsr     ui_clkfmt
        ply
:       iny                             ; (to the end)
        lda     buf - 1,y
        and     #$00FF
        bne     :-
        dey
        lda     #','
        jsr     putb
        lda     #' '
        jsr     putb
        ldx     #0
:       lda     buf + 51,x              ; "HH:MM"
        jsr     putb
        inx
        cpx     #5
        bcc     :-
@dl:    lda     #YU + 42
        ; fall through
; the string in buf at x 30, y A, on a body-coloured background as wide as the content
line:   pha
        lda     #0
        jsr     putb
        lda     #WD_FILL | (C_BODY << 8)
        sta     blk
        lda     #30
        sta     blk+4
        pla
        pha
        sta     blk+6
        lda     #W - 34
        sta     blk+8
        lda     #12
        sta     blk+10
        jsr     draw
        pla
        sta     blk+6
        lda     #WD_TEXT | (C_BLACK << 8)
        sta     blk
        lda     #$FF
        sta     blk+2
        lda     #.loword(buf)
        sta     blk+12
        lda     #^buf
        sta     blk+14
        jmp     draw

; A banks -> "N" (KB) at buf + Y
kb:     asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        ; fall through
; A -> decimal at buf + Y
num:    ldx     #0
:       phx                             ; digits from the right into dig
        ldx     #10
        jsr     divmod
        plx
        pha
        lda     z:r
        clc
        adc     #'0'
        sta     z:dig,x
        inx
        pla
        bne     :-
:       dex                             ; then out, left to right
        lda     z:dig,x
        jsr     putb
        cpx     #0
        bne     :-
        rts

; copy the string at the address after the JSR to buf + Y
cpys:   pla
        inc     a
        sta     z:p
        clc
        adc     #1
        pha
        lda     (p)
        sta     z:p
:       lda     (p)
        and     #$00FF
        beq     :+
        jsr     putb
        inc     z:p
        bra     :-
:       rts

putb:   sep     #$20
        .a8
        sta     buf,y
        rep     #$20
        .a16
        iny
        rts

; text: A = x, X = y, Y = 0 the UI font (C_BLACK), 1 the fixed font (dark blue), 2 the UI
; font in grey (C_DARK), the string's address after the JSR
textat: sta     z:t
        pla
        inc     a
        sta     z:p
        clc
        adc     #1
        pha
        lda     (p)
        sta     z:sc
        lda     z:t
textat_p:
        sta     blk+4
        stx     blk+6
        tya
        and     #1
        xba
        ora     #$FF
        sta     blk+2
        lda     #WD_TEXT | (C_BLACK << 8)
        cpy     #1
        bcc     :+
        lda     #WD_TEXT | (C_TITLE << 8)
        cpy     #2
        bcc     :+
        lda     #WD_TEXT | (C_DARK << 8)
:       sta     blk
        lda     z:sc
        sta     blk+12
        lda     #^t_title
        sta     blk+14
        ; fall through
draw:   lda     z:win
        ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_WDRAW
        rts

; A / X -> A = quotient, z:r = remainder (16 bit)
divmod: stx     z:d
        sta     z:q
        lda     #0
        ldx     #16
:       asl     z:q
        rol     a
        cmp     z:d
        bcc     :+
        sbc     z:d
        inc     z:q
:       dex
        bne     :--
        sta     z:r
        lda     z:q
        rts

; hi:lo / 1000
div1000:
        ldx     #32
        lda     #0
:       asl     z:lo
        rol     z:hi
        rol     a
        cmp     #1000
        bcc     :+
        sbc     #1000
        inc     z:lo
:       dex
        bne     :--
        rts

        .segment "RODATA"
t_about: .byte  "About Horizon", 0
t_title: .byte  "Atari816", 0
t_sys:  .byte   "A 16-bit Atari and desktop on the 65C816.", 0
t_sys2: .byte   "With original 8-bit Atari compatibility.", 0
t_ver:  .byte   "Horizon ", HORIZON_VERSION, 0
t_cpu:  .byte   "65C816 at 14.3 MHz", 0
t_gfx:  .byte   "Video: Marga, 640 x 360, 256 colours", 0
t_blit_on:  .byte "Blitter: Ali", 0
t_blit_off: .byte "Blitter: none (the CPU draws)", 0
t_snd_lau:  .byte "Sound: POKEY 2, Lau", 0
t_snd_p2:   .byte "Sound: POKEY 2", 0
t_snd_none: .byte "Sound: none", 0
t_note: .byte   "Not affiliated with or endorsed by Atari.", 0
s_mem:  .byte   "Memory: ", 0
s_of:   .byte   " KB free of ", 0
s_kb:   .byte   " KB", 0
s_tasks: .byte  "Tasks: ", 0
s_up:   .byte   "Up: ", 0
s_s:    .byte   " s", 0
s_date: .byte   "Date: ", 0
s_noclk: .byte  "not set (click the clock to set it)", 0
stripes: .word  16 + 36 * 5, 16 + 36 * 5 + 6 * 2, 16 + 36 * 5 + 6 * 4, 16 + 36 * 3 + 6 * 5
        .word   16 + 6 * 5 + 2, 16 + 6 * 3 + 5, 16 + 36 * 1 + 5, 16 + 36 * 3 + 4

        .segment "DATA"
wblk:   .word   170, 90, W, H
        .faraddr t_about
        .byte   0

        .segment "BSS"
blk:    .res    16
ev:     .res    8
info:   .res    16
buf:    .res    64

        .segment "ZEROPAGE"
own:    .res    2
win:    .res    2
blit:   .res    2
rev:    .res    2
t:      .res    2
n:      .res    2
sc:     .res    2
p:      .res    2
d:      .res    2
q:      .res    2
r:      .res    2
lo:     .res    2
hi:     .res    2
dig:    .res    8

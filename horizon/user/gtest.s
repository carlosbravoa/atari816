; GTEST - (0.18) a test of the games round's syscalls (kernel/k2*.s), run from the text shell
; by tests/gtest.keys (make test). It starts the window system itself, prints what it sees
; (compared with tests/gtest.txt; tests/gtest-r10.txt on REV $09-$0A, tests/gtest-r8.txt below)
; and ends it again.
;   1. frame and vsync
;   2. palette entries: pal_alloc (the spare ranges first, a given place), pal_set, another
;      program's entries refused (EAGAIN), given back at its end and by pal_alloc 0
;   3. sprites (REV $0B): alloc / free, refused images (the kernel's bank, the framebuffer, a bank
;      nobody owns, past the window, out of an own bank: EFAULT; unaligned: EINVAL), sprites of
;      another program (EINVAL), shown without an image, an image's bank freed, a child's sprites
;      freed at its exit and at its kill
;   4. full screen: refused blocks (EINVAL, EFAULT), another program (EAGAIN), the scroll set and
;      the raster table checked against the framebuffer, the framebuffer's bank freed
;   5. draw lists: refused records (EINVAL, EFAULT), 100 keyed blits as one list, list_wait
;   6. WE_VBL; 7. the sound volume setting
; "gtest m": the measurement of 100 16x16 keyed blits a frame, per call and as one list.
; "gtest s": sprites over a window, for the pictures (tests/gtests.keys).
; "gtest f": a full-screen picture: scrolling with a split, sprites, a raster table; it waits
; for events (tests/gtestf.keys leaves it with Alt+Esc, ends it).
        .include "horizon.inc"

        .segment "CODE"
        .a16
        .i16
start:  sta     z:alen
        jsr     args_init
        stx     z:argp
        lda     z:alen
        beq     main
        lda     f:0,x
        and     #$00FF
        cmp     #'m'
        jeq     measure
        cmp     #'s'
        jeq     sprpic
        cmp     #'f'
        jeq     fspic
        jmp     child

main:   sys     SYS_WSSTART
        jcs     fail
        ptr     wa                      ; window A: ours; B for full screen
        sys     SYS_WOPEN
        sta     z:wina
        ptr     wb
        sys     SYS_WOPEN
        sta     z:winb
        lda     #0
        ldx     #0
        sys     SYS_WSCONFIG
        stx     z:rev

; ---------------------------------------------------------------- 1. frame
        print   "gtest 1: frame\n"
        sys     SYS_VSYNC
        sys     SYS_FRAME
        sta     z:t0
        sys     SYS_VSYNC
        sta     z:t1
        sys     SYS_FRAME
        cmp     z:t1
        bne     @fbad
        sec
        sbc     z:t0
        beq     @fbad
        cmp     #3
        bcs     @fbad
        print   "  frame and vsync agree, one frame later: ok\n"
        bra     :+
@fbad:  print   "  frame: wrong\n"
:

; ---------------------------------------------------------------- 2. palette
        print   "gtest 2: palette\n"
        print   "  alloc 4 (any): "
        lda     #4
        ldx     #$FFFF
        sys     SYS_PALALLOC
        jsr     resv
        print   "  set 76-79: "
        lda     #76 | (4 << 8)
        ptr     rgb4
        sys     SYS_PALSET
        jsr     res
        print   "  alloc at 77: "
        lda     #1
        ldx     #77
        sys     SYS_PALALLOC
        jsr     resv
        print   "  set 212-256 (too many): "
        ldx     #.loword(rgb4)
        ldy     #^rgb4
        lda     #212 | (45 << 8)
        sys     SYS_PALSET
        jsr     res
        lda     #'P'
        jsr     kid                     ; the child: 77 refused, 2 of its own, then it ends
        print   "  after the child, alloc 2 (any): "
        lda     #2
        ldx     #$FFFF
        sys     SYS_PALALLOC
        jsr     resv
        print   "  give all back: "
        lda     #0
        sys     SYS_PALALLOC
        jsr     res
        print   "  alloc at 76 again: "
        lda     #1
        ldx     #76
        sys     SYS_PALALLOC
        jsr     resv
        lda     #0
        sys     SYS_PALALLOC

; ---------------------------------------------------------------- 3. sprites
        print   "gtest 3: sprites\n"
        jsr     images
        lda     #4
        ldx     z:wina
        sys     SYS_SPRALLOC
        bcc     @spr
        cmp     #ENODEV
        jne     @spr
        print   "  no sprites before REV $0B: ENODEV\n"
        jmp     gt4
@spr:   lda     #$FFFF
        sys     SYS_SPRFREE             ; (those again below)
        print   "  alloc 0: "
        lda     #0
        ldx     z:wina
        sys     SYS_SPRALLOC
        jsr     resv
        print   "  alloc 17: "
        lda     #17
        ldx     z:wina
        sys     SYS_SPRALLOC
        jsr     resv
        print   "  a window not ours: "
        lda     #1
        ldx     #15
        sys     SYS_SPRALLOC
        jsr     resv
        print   "  alloc 4: "
        lda     #4
        ldx     z:wina
        sys     SYS_SPRALLOC
        jsr     resv
        print   "  alloc 16: "
        lda     #16
        ldx     z:wina
        sys     SYS_SPRALLOC
        jsr     resv
        print   "  image in the kernel's bank: "
        lda     #$0000
        ldx     #$01
        jsr     setimg
        print   "  in the framebuffer: "
        lda     #$0000
        ldx     #$7C
        jsr     setimg
        print   "  in a bank nobody owns: "
        lda     #$0000
        ldx     #$7B
        jsr     setimg
        print   "  past the window: "
        lda     #$7F80
        ldx     #0
        jsr     setimg
        print   "  out of an own bank: "
        lda     #$FF80
        ldx     z:bank
        jsr     setimg
        print   "  unaligned: "
        lda     #$2008
        ldx     #0
        jsr     setimg
        print   "  sprite 5 (not ours): "
        lda     #5
        sta     se_t
        lda     #$2000
        ldx     #0
        jsr     setimg2
        print   "  two (window, own bank): "
        lda     #2
        ptr     se_ok
        sys     SYS_SPRSET
        jsr     res
        print   "  show sprite 3 (no image): "
        lda     #3
        ldx     #1
        sys     SYS_SPRSHOW
        jsr     res
        print   "  move, hide, show: "
        lda     #0
        ldx     #40
        ldy     #30
        sys     SYS_SPRMOVE
        bcs     @mv
        lda     #0
        ldx     #0
        sys     SYS_SPRSHOW
        bcs     @mv
        lda     #0
        ldx     #1
        sys     SYS_SPRSHOW
@mv:    jsr     res
        print   "  its image's bank freed, show 1: "
        lda     z:bank
        sys     SYS_BFREE
        lda     #1
        ldx     #1
        sys     SYS_SPRSHOW
        jsr     res
        sys     SYS_BALLOC
        sta     z:bank
        print   "  free 4 of another's: "
        lda     #4
        ldx     #1
        sys     SYS_SPRFREE
        jsr     res
        lda     #'S'
        jsr     kid
        print   "  after a child's exit, alloc 12: "
        lda     #12
        ldx     z:wina
        sys     SYS_SPRALLOC
        jsr     resv
        lda     #4
        ldx     #12
        sys     SYS_SPRFREE
        lda     #'K'
        jsr     kidk
        print   "  after a child's kill, alloc 12: "
        lda     #12
        ldx     z:wina
        sys     SYS_SPRALLOC
        jsr     resv
        print   "  free all: "
        lda     #$FFFF
        sys     SYS_SPRFREE
        jsr     res

; ---------------------------------------------------------------- 4. full screen
gt4:    print   "gtest 4: full screen\n"
        lda     z:bank                  ; the framebuffer: 320 x 180 in the own bank
        sep     #$20
        .a8
        sta     fsb+8
        sta     fsb_hi+8
        rep     #$20
        .a16
        print   "  a window not ours: "
        lda     #15
        ptr     fsb
        sys     SYS_FSENTER
        jsr     res
        print   "  mode 3: "
        lda     #3
        ldx     #0
        jsr     fsbad
        print   "  stride 328: "
        lda     #328
        ldx     #2
        jsr     fsbad
        print   "  stride 304: "
        lda     #304
        ldx     #2
        jsr     fsbad
        print   "  rows 170: "
        lda     #170
        ldx     #4
        jsr     fsbad
        print   "  base not aligned: "
        lda     #$0010
        ldx     #6
        jsr     fsbad
        print   "  in the kernel's bank: "
        lda     #$0100
        ldx     #7
        jsr     fsbad
        print   "  running out of its bank: "
        lda     z:winb
        ptr     fsb_hi
        sys     SYS_FSENTER
        jsr     res
        print   "  enter: "
        lda     z:winb
        ptr     fsb
        sys     SYS_FSENTER
        jsr     res
        lda     #'F'
        jsr     kid                     ; it tries too: EAGAIN
        lda     z:rev
        cmp     #$0B
        bcs     @scr
        print   "  scroll: "
        ptr     sc_ok
        sys     SYS_FSSCROLL
        jsr     res
        jmp     @ras
@scr:   print   "  scroll past the rows: "
        ptr     sc_low
        sys     SYS_FSSCROLL
        jsr     res
        print   "  vheight above the rows: "
        ptr     sc_vh
        sys     SYS_FSSCROLL
        jsr     res
        print   "  split at line 0: "
        ptr     sc_sp0
        sys     SYS_FSSCROLL
        jsr     res
        print   "  wrap, x at the stride: "
        ptr     sc_wx
        sys     SYS_FSSCROLL
        jsr     res
        print   "  x past the row, no wrap: "
        ptr     sc_nx
        sys     SYS_FSSCROLL
        jsr     res
        print   "  wrap at 180, split at 320: "
        ptr     sc_ok
        sys     SYS_FSSCROLL
        jsr     res
@ras:   print   "  raster, lines not in order: "
        lda     #2
        ptr     rs_bad
        sys     SYS_FSRASTER
        jsr     res
        print   "  raster, line 360: "
        lda     #1
        ptr     rs_360
        sys     SYS_FSRASTER
        jsr     res
        print   "  raster, before the split: "
        lda     #1
        ptr     rs_early
        sys     SYS_FSRASTER
        jsr     res
        print   "  raster: "
        lda     #2
        ptr     rs_ok
        sys     SYS_FSRASTER
        jsr     res
        print   "  its bank freed, scroll: "
        lda     z:bank
        sys     SYS_BFREE
        ptr     sc_ok
        sys     SYS_FSSCROLL
        jsr     res
        sys     SYS_BALLOC
        sta     z:bank
        sep     #$20
        .a8
        sta     fsb+8
        rep     #$20
        .a16
        print   "  enter again, leave: "
        lda     z:winb
        ptr     fsb
        sys     SYS_FSENTER
        bcs     :+
        lda     z:winb
        sys     SYS_FSLEAVE
:       jsr     res
        print   "  leave again: "
        lda     z:winb
        sys     SYS_FSLEAVE
        jsr     res

; ---------------------------------------------------------------- 5. draw lists
        print   "gtest 5: draw lists\n"
        jsr     mklist                  ; 100 keyed 16 x 16 blits of the window's image
        print   "  count 0: "
        lda     z:wina
        ptr     lst
        sys     SYS_DRAWLIST
        jsr     resv
        print   "  op 6: "
        lda     #6
        ldx     #0
        jsr     lsbad
        print   "  source in the kernel's bank: "
        lda     #$0100
        ldx     #13
        jsr     lsbad
        print   "  source in a bank nobody owns: "
        lda     #$7B00
        ldx     #13
        jsr     lsbad
        print   "  a window not ours: "
        lda     #15 | (1 << 8)
        ptr     lst
        sys     SYS_DRAWLIST
        jsr     resv
        print   "  over two screens (13 fills of the content): "
        ldx     #0
:       lda     #LS_FILL
        sta     lst1+LR_OP,x
        lda     #640
        sta     lst1+LR_W,x
        lda     #360
        sta     lst1+LR_H,x
        txa
        clc
        adc     #20
        tax
        cpx     #13 * 20
        bcc     :-
        lda     z:wina
        ora     #13 << 8
        ptr     lst1
        sys     SYS_DRAWLIST
        jsr     resv
        jsr     mklist
        print   "  100 keyed blits: "
        lda     z:wina
        ora     #100 << 8
        ptr     lst
        sys     SYS_DRAWLIST
        jsr     resv
        print   "  list_wait: "
        lda     #0
        sys     SYS_LISTWAIT
        jsr     res
        print   "  asked: "
        lda     #1
        sys     SYS_LISTWAIT
        jsr     resv
        print   "  a fill, a move, an expand: "
        lda     z:wina
        ora     #3 << 8
        ptr     lst3
        sys     SYS_DRAWLIST
        jsr     resv
        lda     #0
        sys     SYS_LISTWAIT
        ldx     #0                      ; swatches of entries 76-81: the system's colours again
:       phx                             ; (given back by both programs)
        txa
        clc
        adc     #76
        sta     wd_sw+1
        txa
        asl     a
        asl     a
        asl     a
        adc     #140
        sta     wd_sw+4
        lda     z:wina
        ptr     wd_sw
        sys     SYS_WDRAW
        plx
        inx
        cpx     #6
        bcc     :-
        lda     #3000                   ; (tests/gtest.keys takes a picture now: the same at every
        sys     SYS_SLEEP               ; revision, the blitter's list, its single blits, the CPU)

; ---------------------------------------------------------------- 6. WE_VBL
        print   "gtest 6: WE_VBL\n"
        lda     z:wina
        ldx     #1
        sys     SYS_WINVBL
        bcc     :+
        print   "  ENODEV before REV $09\n"
        bra     gt7
:       ldx     #0
        stx     z:t0
@ev:    lda     #0
        ptr     ev
        sys     SYS_WEVENT
        lda     ev
        and     #$00FF
        cmp     #WE_VBL
        bne     @ev
        inc     z:t0
        lda     z:t0
        cmp     #3
        bcc     @ev
        lda     z:wina
        ldx     #0
        sys     SYS_WINVBL
        print   "  three WE_VBL: ok\n"

; ---------------------------------------------------------------- 7. sound volume
gt7:    print   "gtest 7: the sound volume (setting 4): "
        lda     #4
        ldx     #$FFFF
        sys     SYS_SETTING
        jsr     put_dec
        jsr     put_nl
        print   "gtest: done\n"
        sys     SYS_WSSTOP
        exit    0

fail:   print   "gtest: no window system\n"
        exit    1

; ---------------------------------------------------------------- helpers
; "ok" / "error NN"
res:    bcs     err
        print   "ok\n"
        rts
; "A" / "error NN"
resv:   bcs     err
        jsr     put_dec
        jmp     put_nl
err:    pha
        print   "error "
        pla
        jsr     put_hex8
        jmp     put_nl

; the sprite image, 8 bpp 16 x 16: in the window at $2000, in the own bank at $0100
images: ldx     #0
:       lda     img,x
        sta     f:$002000,x
        inx
        inx
        cpx     #256
        bcc     :-
        sys     SYS_BALLOC
        sta     z:bank
        sta     z:p+2
        lda     #$0100
        sta     z:p
        ldy     #0
:       lda     img,y
        sta     [p],y
        iny
        iny
        cpy     #256
        bcc     :-
        lda     z:bank
        sep     #$20
        .a8
        sta     se_ok+10+SE_IMAGE+2
        rep     #$20
        .a16
        rts

; spr_set of sprite 0 with the image at A (offset), X (bank)
setimg: stz     se_t
setimg2:
        sta     se_t+SE_IMAGE
        txa
        sep     #$20
        .a8
        sta     se_t+SE_IMAGE+2
        rep     #$20
        .a16
        lda     #1
        ptr     se_t
        sys     SYS_SPRSET
        jmp     res

; fs_enter with the word at fsb + X changed to A (the rest as fsb): the result, fsb kept
fsbad:  pha
        lda     fsb,x
        sta     z:t1
        pla
        phx
        sta     fsb,x
        lda     z:winb
        ptr     fsb
        sys     SYS_FSENTER
        plx
        php
        pha
        lda     z:t1
        sta     fsb,x
        pla
        plp
        jmp     res

; one record: lst1 with the word at + X changed to A
lsbad:  phx
        pha
        ldx     #18
:       lda     lst,x
        sta     lst1,x
        dex
        dex
        bpl     :-
        pla
        plx
        sta     lst1,x
        lda     z:wina
        ora     #1 << 8
        ptr     lst1
        sys     SYS_DRAWLIST
        jmp     resv

; lst: 100 records, keyed 16 x 16 blits of the window's image at $2000 in a 10 x 10 grid
mklist: ldx     #0
        ldy     #0
@r:     lda     #LS_KEY
        sta     lst+LR_OP,x             ; (op, flags)
        lda     #0                      ; key colour 0
        sta     lst+LR_C1,x
        tya
        lda     #0                      ; (a 10-wide grid: (i mod 10) * 18, (i / 10) * 18)
        sta     z:t0
        tya
@div:   cmp     #10
        bcc     :+
        sbc     #10
        inc     z:t0
        bra     @div
:       sta     z:t1
        asl     a
        asl     a
        asl     a
        adc     z:t1
        asl     a
        adc     #4
        sta     lst+LR_X,x
        lda     z:t0
        asl     a
        asl     a
        asl     a
        adc     z:t0
        asl     a
        adc     #4
        sta     lst+LR_Y,x
        lda     #16
        sta     lst+LR_W,x
        sta     lst+LR_H,x
        lda     #$2000
        sta     lst+LR_SRC,x
        lda     #0
        sta     lst+LR_SRC+2,x
        sta     lst+LR_STRIDE,x
        sta     lst+LR_STRIDE+2,x
        txa
        clc
        adc     #20
        tax
        iny
        cpy     #100
        bcc     @r
        rts

; a child with the argument A ("p", "s", "f"): started and waited for
kid:    sep     #$20
        .a8
        sta     karg
        rep     #$20
        .a16
        jsr     out_flush
        lda     #.loword(karg)
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
kidk:   sep     #$20
        .a8
        sta     karg
        rep     #$20
        .a16
        jsr     out_flush
        lda     #.loword(karg)
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

; ---------------------------------------------------------------- the children
child:  cmp     #'P'
        bne     @s
        print   "  child: set 77: "     ; parent's entry: refused
        lda     #77
        ldx     #$1020
        ldy     #$30
        sys     SYS_WSPAL
        jsr     res
        print   "  child: alloc 2 (any): "
        lda     #2
        ldx     #$FFFF
        sys     SYS_PALALLOC
        jsr     resv
        lda     #80 | (2 << 8)          ; red and green: back to the system's at its end
        ptr     rgb4
        sys     SYS_PALSET
        exit    0
@s:     cmp     #'S'
        beq     :+
        cmp     #'K'
        bne     @f
:       ptr     wc                      ; a window and 4 sprites (4-7), then its end
        sys     SYS_WOPEN
        sta     z:wina
        lda     #4
        ldx     z:wina
        sys     SYS_SPRALLOC
        php
        pha
        print   "  child: alloc 4: "
        pla
        plp
        jsr     resv
        ldx     z:argp                  ; (the argument again)
        lda     f:0,x
        and     #$00FF
        cmp     #'K'
        bne     :+
        lda     #10000
        sys     SYS_SLEEP
:       exit    0
@f:     ptr     wc
        sys     SYS_WOPEN
        sta     z:wina
        print   "  child: enter: "
        lda     z:wina
        ptr     fsb
        sys     SYS_FSENTER
        jsr     res
        exit    0

; ---------------------------------------------------------------- gtest m: the measurement
; 100 keyed 16 x 16 blits a frame, 60 frames: per call (win_draw op 6) and as one list (with
; WAIT_VBL on the first record): syscalls and CPU time a frame (the CPU time is the frame's
; time minus the time it waited in vsync: uptime around each part)
measure:
        sys     SYS_WSSTART
        jcs     fail
        ptr     wm
        sys     SYS_WOPEN
        sta     z:wina
        jsr     images
        jsr     mklist
        lda     z:argp                  ; "gtest m4": ws_config 4, no direct drawing
        tax
        lda     f:1,x
        and     #$00FF
        cmp     #'4'
        bne     :+
        lda     #4
        sys     SYS_WSCONFIG
:       lda     #60
        sta     z:t2
        stz     z:busy
        sys     SYS_VSYNC
@pc:    sys     SYS_UPTIME              ; per call: 100 win_draw
        sta     z:t0
        ldx     #0
@b:     phx
        lda     lst+LR_X,x
        sta     wdb+4
        lda     lst+LR_Y,x
        sta     wdb+6
        lda     z:wina
        ptr     wdb
        sys     SYS_WDRAW
        pla
        clc
        adc     #20
        tax
        cpx     #2000
        bcc     @b
        sys     SYS_UPTIME
        sec
        sbc     z:t0
        clc
        adc     z:busy
        sta     z:busy
        sys     SYS_VSYNC
        dec     z:t2
        bne     @pc
        print   "per call: 100 win_draw a frame, CPU "
        lda     z:busy
        jsr     put_us60
        lda     #LS_KEY                 ; one list a frame
        jsr     mlist
        lda     z:t1
        jsr     put_dec
        print   " records; list: 1 draw_list a frame, CPU "
        lda     z:busy
        jsr     put_us60
        lda     #LS_KEY | (LS_VBL << 8)  ; the same, started in the vertical blank
        jsr     mlist
        print   "list with LS_VBL: 1 draw_list a frame, in the call "
        lda     z:busy
        jsr     put_us60
        sys     SYS_WSSTOP
        exit    0
; 60 frames of one list (A: the first record's op and flags): z:busy = ms in draw_list
mlist:  sta     lst+LR_OP
        lda     #60
        sta     z:t2
        stz     z:busy
        sys     SYS_VSYNC
@ls:    lda     #0                      ; (the last one done: only this call is timed)
        sys     SYS_LISTWAIT
        sys     SYS_UPTIME
        sta     z:t0
        lda     z:wina
        ora     #100 << 8
        ptr     lst
        sys     SYS_DRAWLIST
        sta     z:t1
        sys     SYS_UPTIME
        sec
        sbc     z:t0
        clc
        adc     z:busy
        sta     z:busy
        sys     SYS_VSYNC               ; (it waits for the list too)
        dec     z:t2
        bne     @ls
        rts
; A ms in 60 frames -> "N us a frame\n"
put_us60:
        jsr     put_dec                 ; (us a frame: ms * 1000 / 60, done by the reader)
        print   " ms in 60 frames\n"
        rts

; ---------------------------------------------------------------- gtest s: sprites pictures
sprpic: sys     SYS_WSSTART
        jcs     fail
        ptr     wa
        sys     SYS_WOPEN
        sta     z:wina
        lda     z:wina                  ; a checker behind them
        ptr     wd_chk
        sys     SYS_WDRAW
        jsr     images
        lda     #3
        ldx     z:wina
        sys     SYS_SPRALLOC
        bcc     :+
        print   "gtest s: no sprites\n"
        jmp     waitkey
:       lda     #3
        ptr     se_pic
        sys     SYS_SPRSET
        jsr     waitkey                 ; a key: a second window over the first
        ptr     wb
        sys     SYS_WOPEN
        sta     z:winb
        jsr     waitkey                 ; a key: it closes, the sprites come back, moved
        lda     z:winb
        sys     SYS_WCLOSE
        lda     #0
        ldx     #120
        ldy     #60
        sys     SYS_SPRMOVE
        lda     #1                      ; the second one out at the right edge: hidden
        ldx     #300
        ldy     #20
        sys     SYS_SPRMOVE
        jsr     waitkey
        sys     SYS_WSSTOP
        exit    0
waitkey:
:       lda     #0
        ptr     ev
        sys     SYS_WEVENT
        lda     ev
        and     #$00FF
        cmp     #WE_KEY
        bne     :-
        lda     ev+4
        cmp     #$0100
        bcc     :-
        rts

; ---------------------------------------------------------------- gtest f: full-screen picture
; 320 x 180 in an own bank: 204 rows (rows 180-203 a status panel, shown by the split at the
; top), a pattern in the playfield, scrolled; three sprites; a raster table of two entries.
fspic:  sys     SYS_WSSTART
        jcs     fail
        ptr     wb
        sys     SYS_WOPEN
        sta     z:winb
        lda     z:winb
        ptr     wd_txt
        sys     SYS_WDRAW
        jsr     images
        sys     SYS_BALLOC
        sta     z:bank
        sta     z:p+2
        stz     z:p
        ldy     #0                      ; the playfield: diagonal bands of the cube
        stz     z:t0                    ; row
@row:   ldx     #0
@px:    txa
        clc
        adc     z:t0
        lsr     a
        lsr     a
        lsr     a
        and     #$001F
        clc
        adc     #16 + 36 * 1
        sep     #$20
        .a8
        sta     [p],y
        rep     #$20
        .a16
        iny
        inx
        cpx     #320
        bcc     @px
        inc     z:t0
        lda     z:t0
        cmp     #180
        bcc     @row
        lda     #2                      ; the panel: rows 180-203 in colour 2... then a line
:       sep     #$20
        .a8
        lda     #C_TITLE
        sta     [p],y
        rep     #$20
        .a16
        iny
        cpy     #320 * 204
        bcc     :-
        lda     z:bank
        sep     #$20
        .a8
        sta     fsp+8
        rep     #$20
        .a16
        lda     z:winb
        ptr     fsp
        sys     SYS_FSENTER
        jcs     fsfail
        ptr     sc_pic
        sys     SYS_FSSCROLL
        lda     #2
        ptr     rs_pic
        sys     SYS_FSRASTER
        lda     #3
        ldx     z:winb
        sys     SYS_SPRALLOC
        bcs     @loop
        lda     #3
        ptr     se_fs
        sys     SYS_SPRSET
@loop:  lda     #0                      ; events until the end (a key 'q' ends it)
        ptr     ev
        sys     SYS_WEVENT
        lda     ev
        and     #$00FF
        cmp     #WE_CLOSE
        beq     @end
        cmp     #WE_KEY
        bne     @loop
        lda     ev+2
        cmp     #$14                    ; q
        bne     @loop
@end:   sys     SYS_WSSTOP
        exit    0
fsfail: jsr     err
        jmp     waitkey

        .segment "RODATA"
p_self: .byte   "/SYSTEM/TESTS/GTEST.PRG", 0
t_a:    .byte   "GTEST", 0
t_b:    .byte   "Full screen", 0
t_c:    .byte   "Child", 0
wa:     .word   40, 40, 200, 200
        .faraddr t_a
        .byte   0
wb:     .word   300, 60, 240, 120
        .faraddr t_b
        .byte   0
wc:     .word   100, 250, 120, 60
        .faraddr t_c
        .byte   0
wm:     .word   20, 30, 200, 200
        .faraddr t_a
        .byte   0
rgb4:   .byte   255, 0, 0,  0, 255, 0,  0, 0, 255,  255, 255, 0
        .res    150, 0                  ; (pal_set's "too many" reads up to here)
img:    .repeat 256, I                  ; 16 x 16: a ring of colours, 0 outside (transparent)
        .byte   ((I / 16 - 8) * (I / 16 - 8) + (I .mod 16 - 8) * (I .mod 16 - 8) < 50) * (16 + 6 * (I / 32) + (I .mod 16) / 3)
        .endrepeat
wd_chk: .byte   WD_DITHER, C_LIGHT, C_MID, 0
        .word   0, 0, 200, 200
        .faraddr 0
wd_txt: .byte   WD_TEXT, C_BLACK, C_BODY, 0
        .word   8, 8, 0, 0
        .faraddr t_b
se_pic: .byte   0, SPR_EN
        .word   20, 20
        .faraddr $002000
        .byte   0
        .byte   1, SPR_EN | SPR_MAG | SPR_HFLIP
        .word   60, 40
        .faraddr $002000
        .byte   0
        .byte   2, SPR_EN | SPR_BEHIND
        .word   100, 100
        .faraddr $002000
        .byte   0
se_fs:  .byte   0, SPR_EN
        .word   40, 50
        .faraddr $002000
        .byte   0
        .byte   1, SPR_EN | SPR_MAG
        .word   150, 80
        .faraddr $002000
        .byte   0
        .byte   2, SPR_EN | SPR_VFLIP
        .word   300, 170
        .faraddr $002000
        .byte   0
sc_pic: .word   0, 180, 24, 30, 180, 40 ; lines 0-39: the panel (rows 180-199); from 40 the
        .byte   FSC_SPLIT | FSC_HWRAP, 0 ; playfield from row 30, x 24 (rows are rings), wrapping
                                        ; at row 180
rs_pic: .word   100
        .byte   52, 255, 255, 255
        .word   140
        .byte   52, 0, 0, 0
sc_ok:  .word   0, 170, 0, 180, 180, 320 ; the playfield wraps at 180 from row 170; the panel at 180
        .byte   FSC_SPLIT, 0
sc_low: .word   0, 30, 0, 0, 0, 0       ; rows 30 .. 209: past 204
        .byte   0, 0
sc_vh:  .word   0, 0, 0, 0, 205, 0
        .byte   0, 0
sc_sp0: .word   0, 0, 0, 0, 0, 0
        .byte   FSC_SPLIT, 0
sc_wx:  .word   320, 0, 0, 0, 0, 0
        .byte   FSC_HWRAP, 0
sc_nx:  .word   1, 0, 0, 0, 0, 0
        .byte   0, 0
rs_bad: .word   100
        .byte   20, 1, 2, 3
        .word   50
        .byte   20, 1, 2, 3
rs_360: .word   360
        .byte   20, 1, 2, 3
rs_early: .word 100
        .byte   20, 1, 2, 3
rs_ok:  .word   330
        .byte   20, 1, 2, 3
        .word   340
        .byte   20, 4, 5, 6
lst3:   .byte   LS_FILL, 0, C_RED, 0
        .word   10, 190, 40, 6
        .res    8, 0
        .byte   LS_MOVE, 0, 0, 0
        .word   60, 190, 40, 6
        .word   10, 190
        .res    4, 0
        .byte   LS_EXPAND, $20, C_BLACK, C_YELLOW
        .word   110, 186, 14, 8
        .faraddr expd
        .byte   0
        .word   2, 0
expd:   .byte   $3C, $00, $42, $00, $81, $00, $FF, $C0, $81, $40, $81, $40, $42, $80, $3C, $00

        .segment "DATA"
fsb:    .byte   FS_320X8, 0
        .word   320, 204
        .faraddr $000000                ; (bank set at run time)
        .byte   0
fsb_hi: .byte   FS_320X8, 0
        .word   320, 204
        .faraddr $008000
        .byte   0
fsp:    .byte   FS_320X8, 0
        .word   320, 204
        .faraddr $000000
        .byte   0
se_t:   .byte   0, SPR_EN
        .word   10, 10
        .faraddr $002000
        .byte   0
se_ok:  .byte   0, SPR_EN
        .word   10, 10
        .faraddr $002000
        .byte   0
        .byte   1, SPR_EN | SPR_TALL
        .word   40, 10
        .faraddr $000100                ; (the bank at run time; 16 x 32: 512 bytes)
        .byte   0
karg:   .byte   0, 0
wd_sw:  .byte   WD_FILL, 0, 0, 0
        .word   0, 186, 7, 10
        .faraddr 0
wdb:    .byte   WD_KBLIT, 0, 0, 0
        .word   0, 0, 16, 16
        .faraddr $002000

        .segment "BSS"
ev:     .res    8
lst:    .res    100 * 20
lst1:   .res    20 * 13

        .segment "ZEROPAGE"
alen:   .res    2
argp:   .res    2
wina:   .res    2
winb:   .res    2
rev:    .res    2
bank:   .res    2
busy:   .res    2
t0:     .res    2
t1:     .res    2
t2:     .res    2
p:      .res    4

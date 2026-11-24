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
;   8. (0.19) sheets: refused sheets (sizes EINVAL; the kernel's bank, the framebuffer, a bank
;      nobody owns, past the window, out of an own bank: EFAULT), refused records (past the
;      sheet, overflowing, no such sheet, a bad op, records not ours, the area limit), another
;      program's sheet (EINVAL), the table full (EAGAIN: 32 sheets, 4096 rows), a child's sheets
;      freed at its exit and kill, a bank freed (its sheet gone, the running list stopped), and
;      a picture: fast records, clipped ones, fills, a bitmap target, rows moved by a free
;      (tests/gtest.keys takes it: gtest2, the same at every revision)
; "gtest m": the measurement of 100 16x16 keyed blits a frame, per call, as one list and (0.19)
; as one sheet_draw (and of one record, for the cost of a record).
; "gtest t": sheet_draw's cost a record by kind, in a window and in full screen, each kind
; against a limit there, and the area limit on fast records (tests/gtestt.keys, make test).
; "gtest s": sprites over a window, for the pictures (tests/gtests.keys).
; "gtest v": (0.25) draw lists with LS_VBL while a child draws (the REV $08 one-by-one path).
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
        cmp     #'v'
        jeq     vbltest
        cmp     #'t'
        jeq     tcost
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
        jsr     gt8
        print   "gtest: done\n"
        sys     SYS_WSSTOP
        exit    0

; ---------------------------------------------------------------- 8. sheets (0.19)
gt8:    print   "gtest 8: sheets\n"
        jsr     mksheet                 ; 32 x 32 at $3000 of the window, 16 x 16 at bank:$0100
        print   "  new (32 x 32 in the window): "
        ptr     shn_ok
        sys     SYS_SHEETNEW
        sta     z:sh1
        jsr     resv
        print   "  width 0: "
        lda     #0
        ldx     #SHN_W
        jsr     shbad
        print   "  width 4097: "
        lda     #4097
        ldx     #SHN_W
        jsr     shbad
        print   "  height 1025: "
        lda     #1025
        ldx     #SHN_H
        jsr     shbad
        print   "  stride below the width: "
        lda     #31
        ldx     #SHN_STRIDE
        jsr     shbad
        print   "  in the kernel's bank: "
        lda     #$0100
        ldx     #1
        jsr     shbad
        print   "  in the framebuffer: "
        lda     #$7C00
        ldx     #1
        jsr     shbad
        print   "  in a bank nobody owns: "
        lda     #$7B00
        ldx     #1
        jsr     shbad
        print   "  past the window: "
        lda     #$7C40
        ldx     #0
        jsr     shbad
        print   "  out of an own bank: "
        lda     z:bank
        xba
        ora     #$00FD
        ldx     #1
        jsr     shbad
        print   "  16 x 16 in an own bank: "
        lda     z:bank
        sep     #$20
        .a8
        sta     shn_bk+2
        rep     #$20
        .a16
        ptr     shn_bk
        sys     SYS_SHEETNEW
        sta     z:sh2
        jsr     resv
        jsr     mkslist                 ; 100 keyed copies of sheet 1's first quarter
        print   "  draw 100 keyed copies: "
        lda     z:wina
        ora     #100 << 8
        ptr     slst
        sys     SYS_SHEETDRAW
        jsr     resv
        lda     #0
        sys     SYS_LISTWAIT
        print   "  sx + w past the sheet: "
        ldx     #0
        jsr     sdbad
        print   "  sy + h past the sheet: "
        ldx     #16
        jsr     sdbad
        print   "  sx + w overflowing: "
        ldx     #32
        jsr     sdbad
        print   "  sheet 0 for a copy: "
        ldx     #48
        jsr     sdbad
        print   "  sheet 33: "
        ldx     #64
        jsr     sdbad
        print   "  op 4: "
        ldx     #80
        jsr     sdbad
        print   "  a window not ours: "
        lda     #15 | (1 << 8)
        ptr     slst
        sys     SYS_SHEETDRAW
        jsr     resv
        print   "  count 0: "
        lda     z:wina
        ptr     slst
        sys     SYS_SHEETDRAW
        jsr     resv
        print   "  records past the window: "
        lda     z:wina
        ora     #1 << 8
        ldx     #$7FF8
        ldy     #0
        sys     SYS_SHEETDRAW
        jsr     resv
        print   "  all clipped away or empty: "
        lda     z:wina
        ora     #2 << 8
        ptr     sd_out
        sys     SYS_SHEETDRAW
        jsr     resv
        print   "  over two screens (12 fills of the content): "
        lda     z:wina
        ora     #12 << 8
        ptr     sd_fills
        sys     SYS_SHEETDRAW
        jsr     resv
        print   "  free sheet 3 (none): "
        lda     #3
        sys     SYS_SHEETFREE
        jsr     res
        lda     #'H'                    ; the child: our sheet refused, then the table full
        jsr     kid
        print   "  after the child's exit, new: "
        ptr     shn_ok
        sys     SYS_SHEETNEW
        jsr     resv
        lda     #3
        sys     SYS_SHEETFREE
        lda     #'J'                    ; the same, killed while it waits
        jsr     kidk
        print   "  after the child's kill, new: "
        ptr     shn_ok
        sys     SYS_SHEETNEW
        jsr     resv
        lda     #3
        sys     SYS_SHEETFREE
        print   "  1 x 1024 sheets until the rows run out: "
        stz     z:t0
:       ptr     shn_tall
        sys     SYS_SHEETNEW
        bcs     :+
        inc     z:t0
        bra     :-
:       pha
        lda     z:t0
        jsr     put_dec
        print   ", then "
        pla
        jsr     err
        lda     #3                      ; (they are 3-5)
:       pha
        sys     SYS_SHEETFREE
        pla
        inc     a
        cmp     #6
        bcc     :-
        sys     SYS_BALLOC              ; a sheet in a new bank, a list from it running
        sta     z:bank2
        sep     #$20
        .a8
        sta     shn_b2+2
        rep     #$20
        .a16
        print   "  16 x 16 in a new bank: "
        ptr     shn_b2
        sys     SYS_SHEETNEW
        sta     z:t1
        jsr     resv
        ldx     #0                      ; slst from it, the first waiting for the vertical blank
:       sep     #$20
        .a8
        lda     z:t1
        sta     slst+SD_SHEET,x
        rep     #$20
        .a16
        txa
        clc
        adc     #16
        tax
        cpx     #100 * 16
        bcc     :-
        lda     #SH_KEY | SH_VBL
        sep     #$20
        .a8
        sta     slst+SD_OP
        rep     #$20
        .a16
        lda     z:wina
        ora     #100 << 8
        ptr     slst
        sys     SYS_SHEETDRAW
        lda     z:bank2
        sys     SYS_BFREE
        print   "  its bank freed: the list asked: "
        lda     #1
        sys     SYS_LISTWAIT
        jsr     resv
        print   "  its sheet: "
        lda     z:wina
        ora     #1 << 8
        ptr     slst
        sys     SYS_SHEETDRAW
        jsr     resv
        print   "  free it: "
        lda     z:t1
        sys     SYS_SHEETFREE
        jsr     res
        print   "  the picture, on the screen: "
        lda     z:wina
        ora     #PIC1N << 8
        ptr     sd_pic1
        sys     SYS_SHEETDRAW
        jsr     resv
        lda     #4                      ; (no direct drawing: into the window's bitmap)
        sys     SYS_WSCONFIG
        print   "  in the bitmap: "
        lda     z:wina
        ora     #PIC2N << 8
        ptr     sd_pic2
        sys     SYS_SHEETDRAW
        jsr     resv
        lda     #0
        sys     SYS_LISTWAIT
        lda     #0
        sys     SYS_WSCONFIG
        print   "  free sheet 1: "
        lda     z:sh1
        sys     SYS_SHEETFREE
        jsr     res
        print   "  sheet 2 again (its rows moved): "
        lda     z:wina
        ora     #PIC3N << 8
        ptr     sd_pic3
        sys     SYS_SHEETDRAW
        jsr     resv
        print   "  sheet 1 again: "
        lda     z:wina
        ora     #1 << 8
        ptr     sd_pic1c
        sys     SYS_SHEETDRAW
        jsr     resv
        print   "  free all: "
        lda     #$FFFF
        sys     SYS_SHEETFREE
        jsr     res
        print   "  sheet 2 then: "
        lda     z:wina
        ora     #1 << 8
        ptr     sd_pic3
        sys     SYS_SHEETDRAW
        jsr     resv
        lda     #0
        sys     SYS_LISTWAIT
        lda     #3000                   ; (tests/gtest.keys takes the second picture now)
        sys     SYS_SLEEP
        rts

; the art: 32 x 32 at $3000 of the window (img in four quarters, each in other colours), img
; at $0100 of the own bank
mksheet:
        ldy     #0                      ; y * 32 + x
@p:     tya
        and     #$000F                  ; img[(y & 15) * 16 + (x & 15)]
        sta     z:t0
        tya
        lsr     a
        and     #$00F0
        ora     z:t0
        tax
        lda     img,x
        and     #$00FF
        beq     @put
        sta     z:t0
        tya                             ; + 24 * (x / 16 + 2 * (y / 16))
        and     #$0010
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     z:t1
        tya
        and     #$0200
        xba
        asl     a
        ora     z:t1
        sta     z:t1
        asl     a
        adc     z:t1
        asl     a
        asl     a
        asl     a
        adc     z:t0
@put:   tyx
        sep     #$20
        .a8
        sta     f:$003000,x             ; (the window: DBR is the code bank)
        rep     #$20
        .a16
        iny
        cpy     #32 * 32
        bcc     @p
        lda     z:bank
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
        rts

; sheet_new with shn_ok's word at + X changed to A: the result (a sheet made is freed)
shbad:  phx
        pha
        ldx     #8
:       lda     shn_ok,x
        sta     shn_t,x
        dex
        dex
        bpl     :-
        pla
        plx
        sta     shn_t,x
        ptr     shn_t
        sys     SYS_SHEETNEW
        bcs     :+
        pha
        sys     SYS_SHEETFREE
        pla
        clc
:       jmp     resv

; one record of sd_bad (+ X): the result
sdbad:  txa
        clc
        adc     #.loword(sd_bad)
        tax
        ldy     #^sd_bad
        lda     z:wina
        ora     #1 << 8
        sys     SYS_SHEETDRAW
        jmp     resv

; slst: 100 records, keyed copies of sheet 1's top left 16 x 16 in a 10 x 10 grid (as mklist)
mkslist:
        ldx     #0
        ldy     #0
@r:     lda     #1 | (SH_KEY << 8)
        sta     slst+SD_SHEET,x
        stz     slst+SD_C,x
        stz     slst+SD_SX,x
        stz     slst+SD_SY,x
        lda     #16
        sta     slst+SD_W,x
        sta     slst+SD_H,x
        lda     lst+LR_X,y
        sta     slst+SD_X,x
        lda     lst+LR_Y,y
        sta     slst+SD_Y,x
        tya
        clc
        adc     #20
        tay
        txa
        clc
        adc     #16
        tax
        cpx     #100 * 16
        bcc     @r
        rts

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
child:  cmp     #'B'                    ; (0.25) gtest v's child: draws until it is killed
        bne     @p
        ptr     wvb
        sys     SYS_WOPEN
        sta     z:wina
:       sep     #$20                    ; its whole window filled, the colour changed each time
        .a8
        inc     wd_big+1
        rep     #$20
        .a16
        lda     z:wina
        ptr     wd_big
        sys     SYS_WDRAW
        sys     SYS_YIELD               ; (the fill left running)
        bra     :-
@p:     cmp     #'P'
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
@f:     cmp     #'H'
        beq     @h
        cmp     #'J'
        jne     @fs
@h:     ptr     wc                      ; (0.19) sheets: the parent's refused, then the table
        sys     SYS_WOPEN               ; filled; 'J' then waits to be killed
        sta     z:wina
        print   "  child: the parent's sheet 1: "
        lda     z:wina
        ora     #1 << 8
        ptr     sd_good
        sys     SYS_SHEETDRAW
        jsr     resv
        print   "  child: free it: "
        lda     #1
        sys     SYS_SHEETFREE
        jsr     res
        print   "  child: new until the table is full: "
        stz     z:t0
:       ptr     shn_ok
        sys     SYS_SHEETNEW
        bcs     :+
        inc     z:t0
        bra     :-
:       pha
        lda     z:t0
        jsr     put_dec
        print   ", then "
        pla
        jsr     err
        ldx     z:argp
        lda     f:0,x
        and     #$00FF
        cmp     #'J'
        bne     :+
        lda     #10000
        sys     SYS_SLEEP
:       exit    0
@fs:    ptr     wc
        sys     SYS_WOPEN
        sta     z:wina
        print   "  child: enter: "
        lda     z:wina
        ptr     fsb
        sys     SYS_FSENTER
        jsr     res
        exit    0

; ---------------------------------------------------------------- gtest v (0.25)
; Draw lists whose first record waits for the vertical blank (LS_VBL) while a child keeps the
; blitter busy with large fills. On REV $08 the kernel starts the records one by one: it must
; wait for the blitter again after the vertical blank (the child may have started a fill
; meanwhile); emu816 reports "register written while BUSY" if it does not (make test-25).
vbltest:
        sys     SYS_WSSTART
        jcs     fail
        ptr     wm
        sys     SYS_WOPEN
        sta     z:wina
        lda     #'B'
        sep     #$20
        .a8
        sta     karg
        rep     #$20
        .a16
        lda     #.loword(karg)
        sta     z:u_arg
        lda     #^karg
        sta     z:u_arg+2
        ptr     p_self
        lda     #2                      ; (the priority of a program started by the shell)
        jsr     spawn
        jcs     fail
        sta     z:t0
        lda     #20                     ; (its window open, drawing)
        sys     SYS_SLEEP
        lda     #120
        sta     z:t2
@l:     sep     #$20                    ; two fills, the first in the vertical blank
        .a8
        inc     vl_list+LR_C1
        rep     #$20
        .a16
        lda     z:wina
        ora     #2 << 8
        ptr     vl_list
        sys     SYS_DRAWLIST
        dec     z:t2
        bne     @l
        lda     #0
        sys     SYS_LISTWAIT
        lda     z:t0
        sys     SYS_KILL
        lda     z:t0
        sys     SYS_WAIT
        print   "gtest v: 120 lists with LS_VBL while another program draws: done\n"
        jsr     out_flush
        sys     SYS_WSSTOP
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
        ptr     shn_m                   ; (0.19) the same as sheet_draw records (sheet 1: the
        sys     SYS_SHEETNEW            ; image at $2000)
        jsr     mkslist
        lda     #1 | (SH_KEY << 8)
        ldx     #100
        jsr     msheet
        print   "sheets: 1 sheet_draw a frame, CPU "
        lda     z:busy
        jsr     put_us60
        lda     #1 | ((SH_KEY | SH_VBL) << 8)
        ldx     #100
        jsr     msheet
        print   "sheets with SH_VBL: 1 sheet_draw a frame, in the call "
        lda     z:busy
        jsr     put_us60
        lda     #1 | (SH_KEY << 8)      ; one record a call: a call's own cost (the difference
        ldx     #1                      ; to 100 is 99 records')
        jsr     msheet
        print   "sheets, 1 record: 1 sheet_draw a frame, CPU "
        lda     z:busy
        jsr     put_us60
        lda     #LS_KEY
        sta     lst+LR_OP
        lda     #1
        jsr     mlistn
        print   "list, 1 record: 1 draw_list a frame, CPU "
        lda     z:busy
        jsr     put_us60
        ldx     #0                      ; (0.19) the CPU's part exactly (uptime counts in 10 ms
:       lda     #1                      ; steps): 1 x 1 records (Ali's part next to nothing),
        sta     lst+LR_W,x              ; 500 calls, each followed by a loop of 0.5 ms (Ali
        sta     lst+LR_H,x              ; done meanwhile), less 500 loops alone
        txa
        clc
        adc     #20
        tax
        cpx     #100 * 20
        bcc     :-
        ldx     #0
:       lda     #1
        sta     slst+SD_W,x
        sta     slst+SD_H,x
        txa
        clc
        adc     #16
        tax
        cpx     #100 * 16
        bcc     :-
        lda     #1 | (SH_KEY << 8)
        sta     slst+SD_SHEET
        print   "500 calls of 100 records 1 x 1: draw_list "
        lda     #100
        ldx     #0
        jsr     mexact
        print   " us a call, sheet_draw "
        lda     #100
        ldx     #1
        jsr     mexact
        print   " us a call\n2000 calls of 1 record: draw_list "
        lda     #1
        ldx     #$8000
        jsr     mexact
        print   " us a call, sheet_draw "
        lda     #1
        ldx     #$8001
        jsr     mexact
        print   " us a call\n"
        sys     SYS_WSSTOP
        exit    0
; 500 calls (X bit 15: 2000) of A records (X bit 0 = 0: draw_list of lst, 1: sheet_draw of
; slst), each followed by the loop: the microseconds a call takes (printed): (time - the
; loops' time) * 1000 / calls
mexact: xba
        ora     z:wina
        sta     z:t1
        stx     z:t3
        lda     #500
        cpx     #$8000
        bcc     :+
        lda     #2000
:       sta     z:t4
        lda     #0
        sys     SYS_LISTWAIT
        jsr     mloops                  ; the loops alone
        sta     z:busy
        sys     SYS_UPTIME
        sta     z:t0
        lda     z:t4
        sta     z:t2
@c:     lda     z:t3
        and     #1
        bne     @s
        lda     z:t1
        ptr     lst
        sys     SYS_DRAWLIST
        bra     @w
@s:     lda     z:t1
        ptr     slst
        sys     SYS_SHEETDRAW
@w:     jsr     mloop
        dec     z:t2
        bne     @c
        sys     SYS_UPTIME
        sec
        sbc     z:t0
        sec
        sbc     z:busy
        ldx     z:t3                    ; us a call: * 2 (500 calls), / 2 (2000)
        bmi     :+
        asl     a
        jmp     put_dec
:       lsr     a
        jmp     put_dec
; z:t4 loops -> A = ms
mloops: sys     SYS_UPTIME
        sta     z:t0
        lda     z:t4
        sta     z:t2
:       jsr     mloop
        dec     z:t2
        bne     :-
        sys     SYS_UPTIME
        sec
        sbc     z:t0
        rts
mloop:  ldx     #1435                   ; about 0.5 ms (5 cycles a turn)
:       dex
        bne     :-
        rts
; 60 frames of one sheet_draw of X records (A: the first record's sheet | op << 8): z:busy = ms
; in sheet_draw
msheet: sta     slst+SD_SHEET
        txa
        xba
        ora     z:wina
        sta     z:t1
        lda     #60
        sta     z:t2
        stz     z:busy
        sys     SYS_VSYNC
@ls:    lda     #0
        sys     SYS_LISTWAIT
        sys     SYS_UPTIME
        sta     z:t0
        lda     z:t1
        ptr     slst
        sys     SYS_SHEETDRAW
        sys     SYS_UPTIME
        sec
        sbc     z:t0
        clc
        adc     z:busy
        sta     z:busy
        sys     SYS_VSYNC
        dec     z:t2
        bne     @ls
        rts
; 60 frames of one draw_list of A records: z:busy = ms in draw_list
mlistn: xba
        ora     z:wina
        sta     z:t1
        lda     #60
        sta     z:t2
        stz     z:busy
        sys     SYS_VSYNC
@ls:    lda     #0
        sys     SYS_LISTWAIT
        sys     SYS_UPTIME
        sta     z:t0
        lda     z:t1
        ptr     lst
        sys     SYS_DRAWLIST
        sys     SYS_UPTIME
        sec
        sbc     z:t0
        clc
        adc     z:busy
        sta     z:busy
        sys     SYS_VSYNC
        dec     z:t2
        bne     @ls
        rts
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


; ---------------------------------------------------------------- gtest t: sheet_draw's cost
; The kernel's time a record, by kind (uptime_us around a call of 128 records and one of 1,
; Ali idle before each: (t128 - t1) / 127, the fastest of 8 each), in a window and in full
; screen. Small
; records (1 x 1) are the kernel's cost alone (Ali starts at the call's end); bigger ones show
; that Ali's time is not in it. In full screen each kind has a limit (tc_tab; emu816's board
; timing, not --ideal-timing), checked from REV $09 (Ali's lists: before, the call draws):
; "the limits: kept" or "N over" (make test: tests/gtestt.keys).
tcost:  sys     SYS_WSSTART
        jcs     fail
        ptr     wm
        sys     SYS_WOPEN
        sta     z:wina
        lda     #0
        ldx     #0
        sys     SYS_WSCONFIG
        stx     z:rev
        sys     SYS_BALLOC              ; the art: 256 x 64 at bank:0, tables 256 x 16 at $4000
        jcs     fail
        sta     z:bank
        sta     z:p+2
        stz     z:p
        ldy     #0
:       tya
        sta     [p],y
        iny
        iny
        cpy     #256 * 80
        bcc     :-
        stz     tshn
        lda     z:bank
        and     #$00FF
        sta     tshn+2
        lda     #256
        sta     tshn+4
        sta     tshn+6
        lda     #64
        sta     tshn+8
        ptr     tshn
        sys     SYS_SHEETNEW
        jcs     fail
        sta     z:sh1
        lda     #$4000
        sta     tshn
        lda     #16
        sta     tshn+8
        ptr     tshn
        sys     SYS_SHEETNEW
        jcs     fail
        sta     z:sh2
        print   "gtest t: sheet_draw, us a record (in a window)\n"
        stz     z:t4
        stz     z:tov
        jsr     tc_all
        sys     SYS_BALLOC              ; full screen: 320 x 204 in a bank of its own
        jcs     fail
        sep     #$20
        .a8
        sta     fsp+8
        rep     #$20
        .a16
        lda     z:wina
        ptr     fsp
        sys     SYS_FSENTER
        jcs     fail
        print   "gtest t: in full screen (us a record, the limit)\n"
        lda     z:rev
        cmp     #$09
        rol     z:t4                    ; (1: check)
        jsr     tc_all
        jsr     tc_area
        lda     z:wina
        sys     SYS_FSLEAVE
        lda     z:t4
        bne     :+
        print   "gtest t: the limits: not checked (REV below $09)\n"
        bra     @e
:       lda     z:tov
        bne     :+
        print   "gtest t: the limits: kept\n"
        bra     @e
:       print   "gtest t: the limits: "
        lda     z:tov
        jsr     put_dec
        print   " over\n"
@e:     print   "gtest t: done\n"
        sys     SYS_WSSTOP
        exit    0
; every kind (tc_tab); z:t4 set: each against its limit (z:tov + 1 for every one over)
tc_all: ldx     #0
@k:     stx     z:t3
        lda     tc_tab+14,x             ; REV needed
        cmp     z:rev
        beq     :+
        bcs     @n
:       lda     tc_tab,x                ; the name
        tax
        ldy     #^tc_tab
        jsr     out_str
        ldx     z:t3
        jsr     tc_mk
        jsr     tc_run
        ldx     z:t3
        ldy     z:t4
        beq     @nl
        cmp     tc_tab+16,x
        beq     :+
        bcc     :+
        inc     z:tov
        print   " over"
:       print   " ("
        ldx     z:t3
        lda     tc_tab+16,x
        jsr     put_tenth
        lda     #')'
        jsr     out_char
@nl:    jsr     put_nl
@n:     lda     z:t3
        clc
        adc     #18
        tax
        lda     tc_tab,x
        bne     @k
        print   "  a call of 1 copy:  "
        lda     z:tcall
        jsr     put_dec
        print   " us\n"
        rts
; the area limit (460,800 pixels a call) on fast records beyond 16 x 16: 112 copies of 64 x 64
; (458,752) drawn, 113 (462,848) EINVAL (z:tov + 1 if not)
tc_area:
        ldy     #0
:       lda     z:sh1
        ora     #SH_COPY << 8
        sta     tlst+SD_SHEET,y
        lda     #0
        sta     tlst+SD_C,y
        sta     tlst+SD_SX,y
        sta     tlst+SD_SY,y
        sta     tlst+SD_X,y
        sta     tlst+SD_Y,y
        lda     #64
        sta     tlst+SD_W,y
        sta     tlst+SD_H,y
        tya
        clc
        adc     #16
        tay
        cpy     #128 * 16
        bcc     :-
        print   "  112 copies of 64x64: "
        lda     #112
        jsr     tc_ar
        bcc     :+
        inc     z:tov
:       print   "  113 copies of 64x64: "
        lda     #113
        jsr     tc_ar
        bcs     :+
        inc     z:tov
:       lda     #0
        sys     SYS_LISTWAIT
        rts
; A records of tlst -> printed: the result; C as sheet_draw's
tc_ar:  xba
        ora     z:wina
        pha
        lda     #0
        sys     SYS_LISTWAIT
        pla
        ptr     tlst
        sys     SYS_SHEETDRAW
        php
        jsr     resv
        plp
        rts
; A = tenths: "N.N"
put_tenth:
        ldx     #0
:       cmp     #10
        bcc     :+
        sbc     #10
        inx
        bra     :-
:       pha
        txa
        jsr     put_dec
        lda     #'.'
        jsr     out_char
        pla
        jmp     put_dec
; tlst: 128 records of the kind at tc_tab + X: {name, op A, op B, period (op A every period
; records, else op B), w, h, x0, x step, REV}
tc_mk:  lda     tc_tab+2,x
        sta     z:t0                    ; op A << 8
        lda     tc_tab+4,x
        sta     z:t1                    ; op B << 8
        ldy     #0                      ; record offset
        stz     z:t2                    ; i
@r:     lda     z:t2
        ldx     z:t3
@m:     cmp     tc_tab+6,x
        bcc     :+
        sbc     tc_tab+6,x
        bra     @m
:       tax
        lda     z:t1
        cpx     #0
        bne     :+
        lda     z:t0
:       pha
        and     #$3F00
        cmp     #SH_TABLE << 8
        beq     @tab
        pla
        ora     z:sh1
        sta     tlst+SD_SHEET,y
        lda     #0
        sta     tlst+SD_C,y
        sta     tlst+SD_SX,y
        sta     tlst+SD_SY,y
        ldx     z:t3
        lda     tc_tab+8,x
        sta     tlst+SD_W,y
        lda     tc_tab+10,x
        sta     tlst+SD_H,y
        lda     tc_tab+12,x             ; x = x0 + (i & 7) * step, y = (i / 8) * 11
        and     #$00FF                  ; (x0: a signed byte)
        cmp     #$80
        bcc     :+
        ora     #$FF00
:       sta     z:t5
        lda     tc_tab+13,x
        and     #$00FF
        sta     z:t6
        lda     z:t2
        and     #7
        tax
        lda     z:t5
:       dex
        bmi     :+
        clc
        adc     z:t6
        bra     :-
:       sta     tlst+SD_X,y
        lda     z:t2
        lsr     a
        lsr     a
        lsr     a
        sta     z:t5
        asl     a
        asl     a
        adc     z:t5
        asl     a
        adc     z:t5
        sta     tlst+SD_Y,y
        bra     @nx
@tab:   pla                             ; a table: 16 entries from row i & 15 of sheet 2
        ora     z:sh2
        sta     tlst+SD_SHEET,y
        lda     #0
        sta     tlst+SD_C,y
        sta     tlst+SD_SX,y
        sta     tlst+SD_Y,y
        lda     #16
        sta     tlst+SD_W,y
        lda     #1
        sta     tlst+SD_H,y
        lda     z:t2
        and     #15
        sta     tlst+SD_SY,y
        asl     a
        asl     a
        asl     a
        asl     a
        sta     tlst+SD_X,y
@nx:    tya
        clc
        adc     #16
        tay
        inc     z:t2
        lda     z:t2
        cmp     #128
        jcc     @r
        rts
; 8 times: a call of 1 record and one of 128, the fastest of each (an interrupt may fall in a
; call) -> prints "N.N", A = tenths of us a record
tc_run: lda     #$FFFF
        sta     z:busy                  ; the fastest of 128
        sta     z:t6                    ; of 1
        lda     #8
        sta     z:t2
@c:     lda     #1
        jsr     tc_one
        cmp     z:t6
        bcs     :+
        sta     z:t6
:       lda     #128
        jsr     tc_one
        cmp     z:busy
        bcs     :+
        sta     z:busy
:       dec     z:t2
        bne     @c
        lda     z:t3                    ; (the first kind: its call of 1 record kept)
        bne     :+
        lda     z:t6
        sta     z:tcall
:       lda     z:busy
        sec
        sbc     z:t6
        sta     z:busy
        lda     z:busy                  ; / 127: us and tenths
        ldx     #0
:       cmp     #127
        bcc     :+
        sbc     #127
        inx
        bra     :-
:       sta     z:t5                    ; remainder * 10 / 127
        asl     a
        asl     a
        adc     z:t5
        asl     a
        ldy     #0
:       cmp     #127
        bcc     :+
        sbc     #127
        iny
        bra     :-
:       sty     z:t5
        txa
        asl     a
        sta     z:t0
        asl     a
        asl     a
        adc     z:t0
        adc     z:t5
        sta     z:t0                    ; tenths
        jsr     put_tenth
        lda     z:t0
        rts
; A records of tlst in one call (Ali idle first) -> A = its us
tc_one: xba
        ora     z:wina
        pha
        lda     #0
        sys     SYS_LISTWAIT
        sys     SYS_UPTIMEUS
        sta     z:t0
        pla
        ptr     tlst
        sys     SYS_SHEETDRAW
        bcc     :+
        pha
        print   " (error) "
        pla
        jsr     put_dec
:       sys     SYS_UPTIMEUS
        sec
        sbc     z:t0
        rts

        .segment "RODATA"
        .macro  tck name, opa, opb, per, w, h, x0, xs, rv, lim
        .local  n
        .pushseg
        .segment "DATA"
n:      .byte   name, 0
        .popseg
        .word   .loword(n), (opa) << 8, (opb) << 8, per, w, h
        .byte   x0, xs
        .word   rv, lim
        .endmacro
tc_tab: tck     "  copy 1x1:          ", SH_COPY, SH_COPY, 1, 1, 1, 0, 20, 0, 320
        tck     "  keyed copy 1x1:    ", SH_KEY, SH_KEY, 1, 1, 1, 0, 20, 0, 320
        tck     "  fill 1x1:          ", SH_FILL, SH_FILL, 1, 1, 1, 0, 20, 0, 280
        tck     "  copy 16x16:        ", SH_COPY, SH_COPY, 1, 16, 16, 0, 20, 0, 330
        tck     "  copy 32x10:        ", SH_COPY, SH_COPY, 1, 32, 10, 0, 20, 0, 380
        tck     "  copy, clipped:     ", SH_COPY, SH_COPY, 1, 8, 8, $FC, 0, 0, 560
        tck     "  copy/key alt.:     ", SH_COPY, SH_KEY, 2, 1, 1, 0, 20, 0, 420
        tck     "  remap copy 1x1:    ", SH_COPY | SH_REMAP, SH_COPY | SH_REMAP, 1, 1, 1, 0, 20, $0D, 320
        tck     "  table 16:          ", SH_TABLE, SH_TABLE, 1, 16, 1, 0, 0, $0D, 270
        tck     "  table + 7 remap:   ", SH_TABLE, SH_COPY | SH_REMAP, 8, 16, 10, 0, 20, $0D, 370
        tck     "  table + 7 copies:  ", SH_TABLE, SH_COPY, 8, 16, 10, 0, 20, $0D, 370
        .word   0

        .segment "CODE"
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
wvb:    .word   250, 30, 360, 300       ; (0.25) gtest v's child
        .faraddr t_c
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

; (0.19) sheets: sheet_new blocks; sheet_draw records
.macro  srec    p_sh, p_op, p_c, p_sx, p_sy, p_w, p_h, p_x, p_y
        .byte   p_sh, p_op, p_c, 0
        .word   p_sx, p_sy, p_w, p_h, (p_x) & $FFFF, (p_y) & $FFFF
.endmacro
shn_ok: .faraddr $003000                ; 32 x 32 in the window
        .byte   0
        .word   32, 32, 32
shn_tall: .faraddr $003000              ; 1 x 1024 (rows: 4096 for all sheets)
        .byte   0
        .word   1, 1, 1024
sd_bad: srec    1, SH_COPY, 0, 20, 0, 16, 16, 0, 0          ; sx + w past
        srec    1, SH_COPY, 0, 0, 17, 16, 16, 0, 0          ; sy + h past
        srec    1, SH_COPY, 0, $FFF8, 0, 16, 16, 0, 0       ; overflowing
        srec    0, SH_KEY, 0, 0, 0, 16, 16, 0, 0            ; sheet 0
        srec    33, SH_COPY, 0, 0, 0, 16, 16, 0, 0          ; sheet 33
        srec    1, 4, 0, 0, 0, 16, 16, 0, 0                 ; op 4 (3 is SH_TABLE since 0.31)
sd_good: srec   1, SH_COPY, 0, 0, 0, 16, 16, 0, 0           ; (a good one: the child's)
sd_out: srec    1, SH_COPY | SH_VBL, 0, 0, 0, 16, 16, 300, 0 ; right of the content
        srec    1, SH_COPY, 0, 0, 0, 16, 0, 0, 0            ; empty
sd_fills: .repeat 12
        srec    0, SH_FILL, 21, 0, 0, 640, 360, -50, -50    ; (clipped: 40,000 pixels each)
        .endrepeat
; the picture: the background (it waits for the vertical blank), 16 copies and keyed copies of
; the quarters (the fast path), a 32 x 32 one, three cut at the edges, a fill, the own bank's
; sheet, an empty one
sd_pic1: srec   0, SH_FILL | SH_VBL, 20, 0, 0, 200, 200, 0, 0
sd_pic1c:
        .repeat 16, I
        srec    1, 1 + (I / 4) .mod 2, 0, (I .mod 2) * 16, ((I / 2) .mod 2) * 16, 16, 16, 8 + (I .mod 4) * 20, 8 + (I / 4) * 20
        .endrepeat
        srec    1, SH_COPY, 0, 0, 0, 32, 32, 100, 8
        srec    1, SH_KEY, 0, 0, 0, 32, 32, -10, 100
        srec    1, SH_KEY, 0, 8, 8, 24, 24, 185, 100
        srec    1, SH_COPY, 0, 16, 16, 16, 16, 60, 192
        srec    0, SH_FILL, 40, 0, 0, 30, 6, 140, 60
        srec    2, SH_KEY, 0, 0, 0, 16, 16, 140, 70
        srec    1, SH_COPY, 0, 0, 0, 0, 16, 10, 10
PIC1N = (* - sd_pic1) / 16
; into the bitmap (no direct drawing): a row of keyed copies, one cut, a fill
sd_pic2: .repeat 8, I
        srec    1, SH_KEY, 0, (I .mod 2) * 16, ((I / 2) .mod 2) * 16, 16, 16, 8 + I * 24, 130
        .endrepeat
        srec    1, SH_KEY, 0, 0, 16, 16, 16, -4, 150
        srec    0, SH_FILL, 50, 0, 0, 40, 4, 100, 155
PIC2N = (* - sd_pic2) / 16
; after sheet 1 was freed: sheet 2's rows moved down in the kernel's table
sd_pic3: srec   2, SH_KEY, 0, 0, 0, 16, 16, 20, 170
        srec    2, SH_COPY, 0, 4, 4, 8, 8, 44, 174
        srec    2, SH_KEY, 0, 0, 8, 16, 8, 60, 178
PIC3N = (* - sd_pic3) / 16

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
wd_big: .byte   WD_FILL, 0, 0, 0        ; (0.25) gtest v's child: its whole window
        .word   0, 0, 360, 300
        .faraddr 0
vl_list: .byte  LS_FILL, LS_VBL, 0, 0   ; (0.25) gtest v: two fills, the first after the blank
        .word   0, 0, 200, 180
        .faraddr 0
        .res    5
        .byte   LS_FILL, 0, 7, 0
        .word   10, 10, 60, 40
        .faraddr 0
        .res    5
wd_sw:  .byte   WD_FILL, 0, 0, 0
        .word   0, 186, 7, 10
        .faraddr 0
wdb:    .byte   WD_KBLIT, 0, 0, 0
        .word   0, 0, 16, 16
        .faraddr $002000
shn_t:  .res    10                      ; (0.19) a sheet_new block being changed
shn_bk: .faraddr $000100                ; 16 x 16 in the own bank (its bank at run time)
        .byte   0
        .word   16, 16, 16
shn_b2: .faraddr $000100                ; the same in a second bank
        .byte   0
        .word   16, 16, 16
shn_m:  .faraddr $002000                ; gtest m: the image, 16 x 16
        .byte   0
        .word   16, 16, 16

        .segment "BSS"
ev:     .res    8
lst:    .res    100 * 20
lst1:   .res    20 * 13
slst:   .res    100 * 16                ; (0.19) sheet_draw records
tlst:   .res    128 * 16                ; gtest t's
tshn:   .res    10

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
t3:     .res    2
t4:     .res    2
p:      .res    4
sh1:    .res    2                       ; (0.19) sheets
sh2:    .res    2
bank2:  .res    2
t5:     .res    2
t6:     .res    2
tov:    .res    2
tcall:  .res    2

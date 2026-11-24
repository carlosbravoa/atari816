; k2pal.s - (0.18) palette entries of programs.
;
; The system palette (ws_palette: 0-15 the UI colours, 16-231 the cube, 232-255 the greys) is
; the same for everyone. A program takes entries 16-255 for colours of its own: with pal_alloc
; (free entries, chosen by the kernel) or by setting one (ws_palette, pal_set) that nobody holds.
; An entry held by a program shows the program's colour while one of its windows has the
; keyboard focus (pal_act), and the system colour otherwise; it goes back to the system when the
; program ends (exit, kill, crash) or gives it back (pal_alloc 0). So the program in front looks
; as it means to, and a program's own colours never change what another program shows while
; that one is in front. (0.31) Except in the spare ranges (76-113, 136-175: no UI colour or
; desktop icon uses them, and pal_alloc gives them out first): there an entry always shows its
; holder's colour, so a game in the background (FreeCell, Quabricks) keeps its colours instead
; of turning into the cube's greens when another window comes in front. Entries 0-15 stay
; global (Settings' desktop colour). A program in full screen mode (k2fs.s) has a whole palette
; of its own (fs_pal) while its screen is shown.

        .segment "BSS"
pal_act:    .res    2           ; the holder (slot*2 + 1) whose entries are shown, 0 none

        .segment "K0BSS": far
pal_own:    .res    256         ; the holder of each entry: slot*2 + 1, 0 = the system
pal_prg:    .res    768         ; the holders' colours (R, G, B)
fs_pal:     .res    768         ; the full-screen program's palette (k2fs.s)

        .segment "K2CODE"

; Marga's entry A <- X = red | green << 8, Y = blue, with the video-state copy (any context,
; the interrupt handlers too: it uses only ki0-ki2)
pal_hw: and     #$00FF
        sta     ki0
        stx     ki1
        sty     ki2
        a8
        sta     f:PAL_IDX
        a16
        asl     a
        clc
        adc     ki0
        tax
        a8
        lda     ki1
        sta     f:PAL_R
        sta     vs_pal,x
        lda     ki1+1
        sta     f:PAL_R+1
        sta     vs_pal+1,x
        lda     ki2
        sta     f:PAL_R+2               ; (commits the entry)
        sta     vs_pal+2,x
        a16
        inc     vs_seq
        rts

; C set while the desktop (or a full-screen program) is on the screen: Marga's palette is
; the window system's
pal_live:
        lda     ws_on
        beq     @no
        lda     cls_on
        bne     @no
        sec
        rts
@no:    clc
        rts

; entry A (0-255) on the screen as it should be now: the full-screen palette, the holder's
; colour (holder in front), or the system's. Only while pal_live. Keeps nothing.
pal_show:
        and     #$00FF
        sta     kx6
        asl     a
        clc
        adc     kx6
        tax                             ; index * 3
        lda     fs_act
        beq     :+
        lda     fs_pal,x
        pha
        lda     fs_pal+2,x
        bra     @put
:       phx
        ldx     kx6
        lda     pal_own,x
        plx
        and     #$00FF
        beq     @sys
        cmp     pal_act
        beq     @prg
        lda     kx6                     ; (0.31) not in front: its colour in the spare
        jsr     pal_spare               ; ranges, the system's elsewhere
        bcc     @sys
@prg:   lda     pal_prg,x
        pha
        lda     pal_prg+2,x
        bra     @put
@sys:   lda     ws_palette,x
        pha
        lda     ws_palette+2,x
@put:   and     #$00FF
        tay
        plx
        lda     kx6
        jmp     pal_hw

; (0.31) C set if entry A lies in the spare ranges 76-113, 136-175 (keeps A)
pal_spare:
        cmp     #76
        bcc     @no
        cmp     #114
        bcc     @yes
        cmp     #136
        bcc     @no
        cmp     #176
        bcs     @no
@yes:   sec
        rts
@no:    clc
        rts

; every entry 16-255 held by holder A or kx7 shown again (after pal_act changed)
pal_redo:
        sta     kx5
        lda     #16
        sta     kx4
@e:     ldx     kx4
        lda     pal_own,x
        and     #$00FF
        beq     @n
        cmp     kx5
        beq     @s
        cmp     kx7
        bne     @n
@s:     lda     kx4
        jsr     pal_show
@n:     inc     kx4
        lda     kx4
        cmp     #256
        bcc     @e
        rts

; (ws_focus: the focus changed) the new front program's entries are shown, the old one's
; go back to the system colours; the sprites and the full screen follow soon after
        .export k2_focus: far
k2_focus:
        jsr     pal_front
        lda     #1                      ; the full screen and the sprites: the window-system
        sta     k2_pend                 ; thread does them (k2_service), where nothing it is
        jsl     f_ws_paint_req          ; in the middle of uses the clip variables
        rtl

; pal_act <- the holder of the focused window (fo_w), the entries redrawn if it changed
pal_front:
        lda     #0
        ldx     fo_w
        bmi     :+
        lda     w_owner,x
        inc     a
:       cmp     pal_act
        beq     @out
        ldx     pal_act
        stx     kx7
        sta     pal_act
        jsr     pal_live
        bcc     @out
        lda     pal_act
        jmp     pal_redo
@out:   rts

; (ws_desk_mode, after the system palette was loaded) the held entries again: the front
; program's, (0.31) the others' in the spare ranges
        .export k2_pal_apply: far
k2_pal_apply:
        jsr     pal_live
        bcc     @out
        stz     kx7
        lda     pal_act
        beq     @out
        jsr     pal_redo
        lda     #76                     ; (0.31) the others' entries in the spare ranges
        sta     kx4
@e:     ldx     kx4
        lda     pal_own,x
        and     #$00FF
        beq     :+
        cmp     pal_act
        beq     :+
        txa
        jsr     pal_show
:       inc     kx4
        lda     kx4
        cmp     #114
        bne     :+
        lda     #136
        sta     kx4
:       cmp     #176
        bcc     @e
@out:   rtl

; the current task's entries back to the system (its end; pal_alloc 0)
pal_drop:
        lda     cur
        inc     a
        sta     kx5
        cmp     pal_act                 ; (its slot may soon be another task's)
        bne     :+
        stz     pal_act
:        lda     #16
        sta     kx4
@e:     ldx     kx4
        lda     pal_own,x
        and     #$00FF
        cmp     kx5
        bne     @n
        a8
        lda     #0
        sta     pal_own,x
        a16
        jsr     pal_live
        bcc     @n
        lda     kx4
        jsr     pal_show
@n:     inc     kx4
        lda     kx4
        cmp     #256
        bcc     @e
        rts

; one entry from the current task: A = index, kx0 = red | green << 8, kx1 = blue. C set: an
; entry another program holds (EAGAIN). The full-screen program sets its own palette, the
; others: 0-15 the system's, 16-255 their own (taken if free).
pal_one:
        and     #$00FF
        sta     kx2
        asl     a
        clc
        adc     kx2
        sta     kx3                     ; index * 3
        jsr     fs_mine                 ; the full-screen program: its palette
        bcc     @prg
        ldx     kx3
        lda     kx0
        sta     fs_pal,x
        a8
        lda     kx1
        sta     fs_pal+2,x
        a16
        lda     fs_act
        beq     @ok
        bra     @hw
@prg:   lda     kx2
        cmp     #16
        bcs     @own
        ldx     kx3                     ; 0-15: the system's (Settings' desktop colours)
        lda     kx0
        sta     ws_palette,x
        a8
        lda     kx1
        sta     ws_palette+2,x
        a16
        lda     fs_act
        bne     @ok
        bra     @live
@own:   ldx     kx2
        lda     pal_own,x
        and     #$00FF
        beq     @take
        dec     a
        cmp     cur
        beq     @set
        sec
        rts
@take:  lda     cur
        inc     a
        a8
        sta     pal_own,x
        a16
@set:   ldx     kx3
        lda     kx0
        sta     pal_prg,x
        a8
        lda     kx1
        sta     pal_prg+2,x
        a16
        lda     fs_act
        bne     @ok
        lda     cur
        inc     a
        cmp     pal_act
        beq     @live
        lda     kx2                     ; (0.31) not in front: shown in the spare ranges
        jsr     pal_spare
        bcc     @ok
@live:  jsr     pal_live
        bcc     @ok
@hw:    lda     kx2
        ldx     kx0
        ldy     kx1
        jsr     pal_hw
@ok:    clc
        rts

; ---- $86 ws_palette(A = index, X = red | green << 8, Y = blue) (wsx.s comes here) ----
        .export k2_wspal: far
k2_wspal:
        ldx     cur
        lda     t_x,x
        sta     kx0
        lda     t_y,x
        sta     kx1
        lda     t_a,x
        jsr     pal_one
        bcc     :+
        lda     #EAGAIN
        jsl     f_set_err
        rtl
:       lda     #0
        jsl     f_set_ok
        rtl

; ---- $9A pal_set(A = first | count << 8 (count 0: 256), X, Y = count * 3 bytes R, G, B) ----
; Several entries in one call; the same rules as ws_palette for each. EAGAIN (and nothing
; set) when one of them is held by another program; EFAULT: the table is not readable.
k2_palset:
        ldx     cur
        lda     t_a,x
        and     #$00FF
        sta     kx4                     ; the first
        lda     t_a+1,x
        and     #$00FF
        bne     :+
        lda     #256
:       sta     kx5                     ; the count
        clc
        adc     kx4
        cmp     #257
        bcc     :+
        jmp     k2_inval
:       lda     kx5                     ; the table: count * 3 bytes
        asl     a
        adc     kx5
        sta     kt2
        stz     kt3
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        jsl     f_uaccess
        bcc     :+
        jmp     k2_fault
:       lda     kphys
        sta     kp2
        lda     kphys+2
        sta     kp2+2
        jsr     fs_mine                 ; first: none of them another program's
        bcs     @go
        ldx     kx4
        ldy     kx5
@chk:   cpx     #16
        bcc     @cn
        lda     pal_own,x
        and     #$00FF
        beq     @cn
        dec     a
        cmp     cur
        beq     @cn
        lda     #EAGAIN
        jmp     k2_err
@cn:    inx
        dey
        bne     @chk
@go:    ldy     #0
@e:     lda     [kp2],y
        sta     kx0
        iny
        iny
        lda     [kp2],y
        and     #$00FF
        sta     kx1
        iny
        phy
        lda     kx4
        jsr     pal_one
        ply
        inc     kx4
        dec     kx5
        bne     @e
        jmp     k2_ok0

; ---- $9B pal_alloc(A = count 1-240, X = the first entry wanted, $FFFF any) -> A = the first ----
; count entries in a row that nobody holds become the caller's, with their system colours (so
; nothing changes on the screen until it sets them). With X = $FFFF the kernel chooses: first
; among the entries no desktop icon or UI uses (76-113, 136-175), then from 16 up. A = 0 gives
; every entry of the caller back (the system colours return). EAGAIN: no such run is free.
k2_palalloc:
        ldx     cur
        lda     t_a,x
        bne     :+
        jsr     pal_drop
        jmp     k2_ok0
:       cmp     #241
        bcc     :+
        jmp     k2_inval
:       sta     kx5
        lda     t_x,x
        cmp     #$FFFF
        beq     @any
        cmp     #16                     ; a given place: 16 .. 256 - count
        bcc     @inv
        jsr     pal_free_at
        bcc     @got
        lda     #EAGAIN
        jmp     k2_err
@inv:   jmp     k2_inval
@any:   lda     #76                     ; the spare ranges first
        ldy     #114
        jsr     pal_scan
        bcc     @got
        lda     #136
        ldy     #176
        jsr     pal_scan
        bcc     @got
        lda     #16
        ldy     #256
        jsr     pal_scan
        bcc     @got
        lda     #EAGAIN
        jmp     k2_err
@got:   sta     kx4                     ; take them, with their system colours
        sta     kx6
        lda     kx5
        sta     kx2
@t:     ldx     kx6
        lda     cur
        inc     a
        a8
        sta     pal_own,x
        a16
        lda     kx6
        asl     a
        adc     kx6
        tax
        lda     ws_palette,x
        sta     pal_prg,x
        a8
        lda     ws_palette+2,x
        sta     pal_prg+2,x
        a16
        inc     kx6
        dec     kx2
        bne     @t
        lda     kx4
        jsl     f_set_ok
        rtl

; C clear if kx5 entries from A on are free and below 256 (keeps A)
pal_free_at:
        sta     kx3
        clc
        adc     kx5
        cmp     #257
        bcs     @no
        ldx     kx3
        ldy     kx5
:       lda     pal_own,x
        and     #$00FF
        bne     @no
        inx
        dey
        bne     :-
        lda     kx3
        clc
        rts
@no:    lda     kx3
        sec
        rts

; the first run of kx5 free entries from A up to (not including) Y -> A, C clear; C set none
pal_scan:
        sty     kx1
@s:     pha
        clc
        adc     kx5
        cmp     kx1
        beq     :+
        bcs     @none
:       pla
        jsr     pal_free_at
        bcs     :+
        rts
:       inc     a
        bra     @s
@none:  pla
        sec
        rts

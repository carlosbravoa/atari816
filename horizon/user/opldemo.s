; OPLDEMO - OPL2 (YM3812) FM Synth demo & live keyboard (/BIN/OPLDEMO.PRG, REV $0C).
; Uses SYS_OPLW ($6D) for YM3812 registers and SYS_SPLAY / SYS_SSET / SYS_SSTOP for Lau.
;   Buttons: Chords, Bass+Lead, Waves (WS 0..3), OPL2+Lau (FM + Lau PCM pan),
;            E-Piano / Brass / Bass (live patch), Stop.
;   Live FM keyboard: keys A S D F G H J K (8-voice polyphonic C4..C5), or click keys.
;   Close box or Esc exits and silences OPL2 & Lau.
        .include "horizon.inc"
        .include "ui.inc"

W       = 324                           ; window content size
H       = 180
KX0     = 12                            ; piano keys origin and spacing
KY0     = 118
KW      = 34
KH      = 50
KSTEP   = 38

; Note F-numbers (10-bit) for YM3812 49.7 kHz sample rate
FN_C    = $159
FN_D    = $183
FN_E    = $1B2
FN_F    = $1CC
FN_G    = $205
FN_A    = $244
FN_B    = $28B

MODE_IDLE   = 0
MODE_CHORDS = 1
MODE_MELODY = 2
MODE_WAVES  = 3
MODE_MIX    = 4

        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_SINGLE              ; one instance only
        bcc     :+
        exit    0
:       sys     SYS_WSSTART
        bcc     :+
        print   "opldemo: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        ptr     wblk
        sys     SYS_WOPEN
        bcc     :+
        jsr     stopws
        print   "opldemo: no window\n"
        exit    1
:       sta     win

        ; Attach every control to our window
        ldy     #0
:       ldx     allc,y
        beq     :+
        sep     #$20
        .a8
        lda     win
        sta     a:CT_WIN,x
        rep     #$20
        .a16
        iny
        iny
        bra     :-
:
        ; Check hardware revision & probe OPL2 via SYS_OPLW ($FFFE)
        lda     #0
        sys     SYS_WSCONFIG
        stx     hwrev
        stz     has_opl
        stz     mode
        stz     patch
        lda     #$FFFF
        sta     lau_v
        sta     mkey
        ldx     #0
:       stz     kdown,x
        inx
        inx
        cpx     #16
        bne     :-

        lda     #$FFFE                  ; probe OPL2 status
        ldx     #0
        sys     SYS_OPLW
        bcs     @no_opl
        sta     opl_st
        lda     #1
        sta     has_opl
        ; Reset OPL2 and enable OPL2 waveform select ($01 = $20)
        lda     #$FFFF
        ldx     #0
        sys     SYS_OPLW
        lda     #$0001
        ldx     #$0020
        sys     SYS_OPLW
        jsr     init_live_patches
        lda     #.loword(s_hw_ok)
        sta     l_hw + LB_TEXT
        lda     #.loword(s_ready)
        sta     l_stat + LB_TEXT
        bra     @draw

@no_opl:
        lda     #.loword(s_hw_no)
        sta     l_hw + LB_TEXT
        lda     #.loword(s_need)
        sta     l_stat + LB_TEXT

@draw:  ; Initialise Lau sample block (24-bit pointer to sine256 in our code bank)
        lda     #.loword(sine256)
        sta     spb + SPB_ADDR
        sep     #$20
        .a8
        lda     #^sine256
        sta     spb + SPB_ADDR + 2
        lda     #0
        sta     spb + SPB_LEN + 2
        sta     spb + SPB_LOOP + 2
        lda     #$FF
        sta     spb + SPB_VOLL
        lda     #$00
        sta     spb + SPB_VOLR
        lda     #SPF_LOOP
        sta     spb + SPB_FLAGS
        lda     #SP_ANY
        sta     spb + SPB_VOICE
        lda     #0
        sta     spb + 15
        rep     #$20
        .a16
        lda     #256
        sta     spb + SPB_LEN
        stz     spb + SPB_LOOP
        lda     #$B2F6                  ; ~523 Hz (C5) for 256-sample sine
        sta     spb + SPB_PITCH

        ldx     #.loword(allc)
        jsr     ui_drawall
        jsr     draw_keys

        ; 20 ms timer for non-blocking sequencer
        lda     win
        ldx     #2
        sys     SYS_WTIMER

; ── Main event loop ──────────────────────────────────────────────────────────
loop:   lda     #0
        jsr     ui_getev
        bcs     loop
        ldx     #.loword(allc)
        jsr     ui_event
        cmp     #UA_CLICK
        beq     on_click
        cmp     #UA_NONE
        bne     loop

        lda     ui_ev
        and     #$00FF
        cmp     #WE_CLOSE
        beq     quit
        cmp     #WE_TICK
        bne     :+
        jsr     on_tick
        bra     loop
:       cmp     #WE_KEY
        bne     :+
        jsr     on_key
        bra     loop
:       cmp     #WE_BUTTON
        bne     loop
        jsr     on_mouse
        bra     loop

quit:   jsr     stop_all
        lda     win
        sys     SYS_WCLOSE
        jsr     stopws
        exit    0

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

; ── Button clicks (X = control pointer) ──────────────────────────────────────
on_click:
        cpx     #.loword(b_stop)
        bne     :+
        jsr     stop_all
        lda     #.loword(s_stopped)
        jsr     set_stat
        jmp     loop
:       lda     has_opl
        bne     :+
        jmp     loop
:       cpx     #.loword(b_chords)
        bne     :+
        jsr     start_chords
        jmp     loop
:       cpx     #.loword(b_melody)
        bne     :+
        jsr     start_melody
        jmp     loop
:       cpx     #.loword(b_waves)
        bne     :+
        jsr     start_waves
        jmp     loop
:       cpx     #.loword(b_mix)
        bne     :+
        jsr     start_mix
        jmp     loop
:       cpx     #.loword(b_p0)
        bne     :+
        lda     #0
        jsr     select_patch
        jmp     loop
:       cpx     #.loword(b_p1)
        bne     :+
        lda     #1
        jsr     select_patch
        jmp     loop
:       cpx     #.loword(b_p2)
        bne     :+
        lda     #2
        jsr     select_patch
:       jmp     loop

; ── Keyboard handler (Esc quits, A-K play live FM notes) ─────────────────────
on_key:
        lda     ui_ev + 2               ; HID usage
        cmp     #$0029                  ; Esc?
        bne     :+
        lda     ui_ev + 4
        and     #$0100                  ; down
        beq     @done
        pla                             ; pop return address and quit
        jmp     quit
:       lda     has_opl
        beq     @done
        ; Check HID usage against A S D F G H J K table
        lda     ui_ev + 2
        ldx     #0
@fk:    cmp     hid_keys,x
        beq     @hit
        inx
        inx
        cpx     #16
        bne     @fk
@done:  rts
@hit:   ; X = key_idx * 2 (0..14)
        stx     ktmp
        lda     mode
        beq     :+
        jsr     stop_all                ; switch out of demo mode to live play
:       ldx     ktmp
        lda     ui_ev + 4
        and     #$0100                  ; bit 8 = key down
        beq     @up
        lda     kdown,x
        bne     @done                   ; ignore auto-repeat
        lda     #1
        sta     kdown,x
        txa
        lsr     a
        jsr     live_note_on
        ldx     ktmp
        txa
        lsr     a
        jsr     draw_one_key
        lda     #.loword(s_live)
        jmp     set_stat
@up:    lda     kdown,x
        beq     @done
        stz     kdown,x
        txa
        lsr     a
        jsr     live_note_off
        ldx     ktmp
        txa
        lsr     a
        jmp     draw_one_key

; ── Mouse clicks on drawn piano keys ─────────────────────────────────────────
on_mouse:
        lda     has_opl
        beq     @done
        lda     ui_ev + 6               ; buttons
        and     #$0001
        beq     @rel
        ; Press inside piano strip?
        lda     ui_ev + 4               ; y
        cmp     #KY0
        bcc     @done
        cmp     #KY0 + KH
        bcs     @done
        lda     ui_ev + 2               ; x
        cmp     #KX0
        bcc     @done
        sec
        sbc     #KX0
        ; Find key i where i*KSTEP <= dx < i*KSTEP + KW
        ldx     #0
@mk:    cmp     #KW
        bcc     @mhit
        cmp     #KSTEP
        bcc     @done
        sec
        sbc     #KSTEP
        inx
        cpx     #8
        bcc     @mk
@done:  rts
@mhit:  stx     ktmp
        lda     mode
        beq     :+
        jsr     stop_all
:       jsr     rel_mkey
        lda     ktmp
        sta     mkey
        asl     a
        tax
        lda     #1
        sta     kdown,x
        lda     ktmp
        jsr     live_note_on
        lda     ktmp
        jsr     draw_one_key
        lda     #.loword(s_live)
        jmp     set_stat
@rel:   jmp     rel_mkey

rel_mkey:
        lda     mkey
        bmi     @out
        pha
        asl     a
        tax
        stz     kdown,x
        lda     #$FFFF
        sta     mkey
        pla
        pha
        jsr     live_note_off
        pla
        jmp     draw_one_key
@out:   rts

; ── Stop & reset everything cleanly ──────────────────────────────────────────
stop_all:
        stz     mode
        lda     lau_v
        bmi     :+
        lda     #$FFFF
        sys     SYS_SSTOP
        lda     #$FFFF
        sta     lau_v
:       lda     has_opl
        beq     :+
        lda     #$FFFF                  ; reset OPL2
        ldx     #0
        sys     SYS_OPLW
        lda     #$0001
        ldx     #$0020                  ; re-enable OPL2 waveforms
        sys     SYS_OPLW
        jsr     init_live_patches
:       ; Clear any visual held keys
        ldx     #0
@ck:    lda     kdown,x
        beq     @cn
        stz     kdown,x
        phx
        txa
        lsr     a
        jsr     draw_one_key
        plx
@cn:    inx
        inx
        cpx     #16
        bne     @ck
        lda     #$FFFF
        sta     mkey
        rts

; ── Demo starters ────────────────────────────────────────────────────────────
start_chords:
        jsr     stop_all
        ldx     #0
:       phx
        txa
        jsr     patch_epiano
        plx
        inx
        cpx     #4
        bne     :-
        lda     #MODE_CHORDS
        sta     mode
        stz     step
        stz     tickc
        lda     #.loword(s_chords)
        jmp     set_stat

start_melody:
        jsr     stop_all
        jsr     patch_bass              ; ch 0
        jsr     patch_brass             ; ch 1
        lda     #MODE_MELODY
        sta     mode
        stz     step
        stz     tickc
        lda     #.loword(s_melody)
        jmp     set_stat

start_waves:
        jsr     stop_all
        jsr     patch_pure              ; ch 0
        lda     #MODE_WAVES
        sta     mode
        stz     step
        stz     tickc
        lda     #.loword(s_ws0)
        jmp     set_stat

start_mix:
        jsr     stop_all
        lda     #0
        jsr     patch_epiano
        lda     #1
        jsr     patch_epiano
        lda     #2
        jsr     patch_epiano
        ; C4 - E4 - G4 on OPL2 ch 0..2
        lda     #FN_C
        ldx     #$30 | (FN_C >> 8)
        ldy     #0
        jsr     opl_note_on
        lda     #FN_E
        ldx     #$30 | (FN_E >> 8)
        ldy     #1
        jsr     opl_note_on
        lda     #FN_G
        ldx     #$30 | (FN_G >> 8)
        ldy     #2
        jsr     opl_note_on
        ; Start Lau voice 0
        ptr     spb
        sys     SYS_SPLAY
        bcs     :+
        sta     lau_v
:       lda     #MODE_MIX
        sta     mode
        stz     step
        stz     tickc
        lda     #.loword(s_mix)
        jmp     set_stat

; ── 20 ms Sequencer tick ─────────────────────────────────────────────────────
on_tick:
        lda     mode
        beq     @done
        cmp     #MODE_CHORDS
        bne     :+
        jmp     tick_chords
:       cmp     #MODE_MELODY
        bne     :+
        jmp     tick_melody
:       cmp     #MODE_WAVES
        bne     :+
        jmp     tick_waves
:       cmp     #MODE_MIX
        bne     @done
        jmp     tick_mix
@done:  rts

; Chords: 4 chords, each 52 ticks (1.04 s):
;   tick 0,4,8,12 = arpeggiate notes 0..3; tick 44 = key-off all; tick 52 = next chord
tick_chords:
        lda     tickc
        cmp     #0
        beq     @n0
        cmp     #4
        beq     @n1
        cmp     #8
        beq     @n2
        cmp     #12
        beq     @n3
        cmp     #44
        beq     @off
        cmp     #52
        beq     @next
        inc     tickc
        rts
@n0:    lda     #0
        bra     @play
@n1:    lda     #1
        bra     @play
@n2:    lda     #2
        bra     @play
@n3:    lda     #3
@play:  pha                             ; ch = 0..3
        lda     step                    ; chord 0..3 -> idx = chord*4 + note
        asl     a
        asl     a
        clc
        adc     1,s
        tax
        lda     chords_lo,x
        and     #$00FF
        pha
        lda     chords_hi,x
        and     #$00FF
        tax
        pla                             ; A = lo, X = hi
        ply                             ; Y = ch
        jsr     opl_note_on
        inc     tickc
        rts
@off:   ldy     #0
:       phy
        tya
        jsr     opl_note_off
        ply
        iny
        cpy     #4
        bne     :-
        inc     tickc
        rts
@next:  stz     tickc
        inc     step
        lda     step
        cmp     #4
        bcc     @out
        jsr     stop_all
        lda     #.loword(s_ready)
        jmp     set_stat
@out:   rts

; Melody: 16 steps x 13 ticks (260 ms): tick 0 = note on, tick 10 = note off, tick 13 = next
tick_melody:
        lda     tickc
        beq     @on
        cmp     #10
        beq     @off
        cmp     #13
        beq     @next
        inc     tickc
        rts
@on:    ldx     step
        lda     bass_lo,x
        and     #$00FF
        pha
        lda     bass_hi,x
        and     #$00FF
        tax
        pla
        ldy     #0
        jsr     opl_note_on
        ldx     step
        lda     lead_lo,x
        and     #$00FF
        pha
        lda     lead_hi,x
        and     #$00FF
        tax
        pla
        ldy     #1
        jsr     opl_note_on
        inc     tickc
        rts
@off:   lda     #0
        jsr     opl_note_off
        lda     #1
        jsr     opl_note_off
        inc     tickc
        rts
@next:  stz     tickc
        inc     step
        lda     step
        cmp     #16
        bcc     @out
        jsr     stop_all
        lda     #.loword(s_ready)
        jmp     set_stat
@out:   rts

; Waves: 4 waveforms x 32 ticks (640 ms): tick 0 = set WS + A4 on, tick 25 = off, tick 32 = next
tick_waves:
        lda     tickc
        beq     @on
        cmp     #25
        beq     @off
        cmp     #32
        beq     @next
        inc     tickc
        rts
@on:    lda     step
        asl     a
        tax
        lda     ws_labels,x
        jsr     set_stat
        lda     #$00E3                  ; ch 0 carrier waveform select
        ldx     step
        sys     SYS_OPLW
        lda     #FN_A & $FF
        ldx     #$30 | (FN_A >> 8)
        ldy     #0
        jsr     opl_note_on
        inc     tickc
        rts
@off:   lda     #0
        jsr     opl_note_off
        inc     tickc
        rts
@next:  stz     tickc
        inc     step
        lda     step
        cmp     #4
        bcc     @out
        jsr     stop_all
        lda     #.loword(s_ready)
        jmp     set_stat
@out:   rts

; Mix: pan Lau L->R over 128 ticks (~2.56 s) while OPL2 chord sustains
tick_mix:
        lda     tickc
        cmp     #128
        bcs     @end
        lda     lau_v
        bmi     @nx
        ; vr = tickc * 2 (0..254), vl = 255 - vr
        lda     tickc
        asl     a
        and     #$00FF
        sta     ktmp                    ; vr
        lda     #255
        sec
        sbc     ktmp                    ; vl
        and     #$00FF
        ora     #0
        sta     ktmp + 2                ; vl
        lda     ktmp
        xba                             ; vr << 8
        ora     ktmp + 2                ; vl | (vr << 8)
        tay
        ldx     #$B2F6
        lda     lau_v
        sys     SYS_SSET
@nx:    inc     tickc
        rts
@end:   jsr     stop_all
        lda     #.loword(s_ready)
        jmp     set_stat

; ── Live keyboard patch management (channels 0..7) ───────────────────────────
select_patch:
        sta     patch
        jsr     stop_all
        lda     patch
        asl     a
        tax
        lda     patch_labels,x
        jmp     set_stat

init_live_patches:
        ldx     #0
@lp:    phx
        lda     patch
        beq     @ep
        cmp     #1
        beq     @br
        ; Bass on channel X
        txa
        jsr     patch_bass_ch
        bra     @nx
@ep:    txa
        jsr     patch_epiano
        bra     @nx
@br:    txa
        jsr     patch_brass_ch
@nx:    plx
        inx
        cpx     #8
        bne     @lp
        rts

; Play live key A (0..7) on channel A
live_note_on:
        tay                             ; Y = channel 0..7
        phy
        tax
        lda     live_lo,x
        and     #$00FF
        pha
        lda     live_hi,x
        and     #$00FF
        tax
        pla                             ; A = lo, X = hi
        ply                             ; Y = ch
        jmp     opl_note_on

live_note_off:
        jmp     opl_note_off

; ── OPL2 register helpers (via SYS_OPLW) ─────────────────────────────────────
; A = F-num low, X = block/keyon/F-num hi, Y = channel (0..8)
opl_note_on:
        phy
        phx
        tax                             ; X = F-num low
        tya
        clc
        adc     #$00A0
        sys     SYS_OPLW
        plx                             ; X = hi byte
        pla                             ; A = channel
        clc
        adc     #$00B0
        sys     SYS_OPLW
        rts

; A = channel (0..8)
opl_note_off:
        clc
        adc     #$00B0
        ldx     #0
        sys     SYS_OPLW
        rts

; Write channel A (0..7) with patch table at Y (11 bytes:
;   mod 20/40/60/80/E0, car 20/40/60/80/E0, ch C0)
apply_patch:
        sta     pch
        sty     z:pptr
        tax
        lda     op_mod,x
        and     #$00FF
        sta     pmod
        lda     op_car,x
        and     #$00FF
        sta     pcar

        ldy     #0
@m:     lda     (pptr),y
        and     #$00FF
        tax
        tya
        asl     a
        phx
        tax
        lda     op_base,x
        plx
        clc
        adc     pmod
        phy
        sys     SYS_OPLW
        ply
        iny
        cpy     #5
        bne     @m

        ldy     #0
@c:     tya
        clc
        adc     #5
        tay
        lda     (pptr),y
        and     #$00FF
        tax
        tya
        sec
        sbc     #5
        tay
        asl     a
        phx
        tax
        lda     op_base,x
        plx
        clc
        adc     pcar
        phy
        sys     SYS_OPLW
        ply
        iny
        cpy     #5
        bne     @c

        ldy     #10
        lda     (pptr),y
        and     #$00FF
        tax
        lda     #$00C0
        clc
        adc     pch
        sys     SYS_OPLW
        rts

patch_epiano:
        ldy     #.loword(pt_epiano)
        jmp     apply_patch

patch_bass:
        lda     #0
patch_bass_ch:
        ldy     #.loword(pt_bass)
        jmp     apply_patch

patch_brass:
        lda     #1
patch_brass_ch:
        ldy     #.loword(pt_brass)
        jmp     apply_patch

patch_pure:
        lda     #0
        ldy     #.loword(pt_pure)
        jmp     apply_patch

; ── UI drawing helpers ───────────────────────────────────────────────────────
set_stat:
        sta     l_stat + LB_TEXT
        ldx     #.loword(l_stat)
        jmp     ui_draw

draw_keys:
        ldx     #0
@dk:    phx
        txa
        jsr     draw_one_key
        plx
        inx
        cpx     #8
        bne     @dk
        rts

; Draw piano key A (0..7)
draw_one_key:
        sta     kidx
        ; x = KX0 + kidx * KSTEP
        asl     a                       ; *2
        sta     kx
        asl     a                       ; *4
        asl     a                       ; *8
        asl     a                       ; *16
        asl     a                       ; *32
        clc
        adc     kx                      ; *34
        adc     kx                      ; *36
        adc     kx                      ; *38
        clc
        adc     #KX0
        sta     kx

        ; Fill white (up) or C_SELECT (down)
        lda     kidx
        asl     a
        tax
        lda     kdown,x
        bne     @sel
        lda     #WD_FILL | (C_WHITE << 8)
        bra     @f
@sel:   lda     #WD_FILL | (C_SELECT << 8)
@f:     sta     dblk
        stz     dblk + 2
        lda     kx
        sta     dblk + 4
        lda     #KY0
        sta     dblk + 6
        lda     #KW
        sta     dblk + 8
        lda     #KH
        sta     dblk + 10
        jsr     wdraw

        ; Dark border frame
        lda     #WD_FRAME | (C_DARK << 8)
        sta     dblk
        jsr     wdraw

        ; Note name (C4..C5) near top of key
        lda     kidx
        asl     a
        tax
        lda     kdown,x
        bne     @inv1
        lda     #WD_TEXT | (C_BLACK << 8)
        bra     @t1
@inv1:  lda     #WD_TEXT | (C_WHITE << 8)
@t1:    sta     dblk
        lda     #$00FF                  ; paper = transparent, font 0 (UI)
        sta     dblk + 2
        lda     kx
        clc
        adc     #8
        sta     dblk + 4
        lda     #KY0 + 8
        sta     dblk + 6
        lda     kidx
        asl     a
        tax
        lda     note_lbls,x
        sta     dblk + 12
        lda     #^note_lbls
        sta     dblk + 14
        jsr     wdraw

        ; Keyboard letter (A..K) near bottom of key
        lda     kx
        clc
        adc     #13
        sta     dblk + 4
        lda     #KY0 + 30
        sta     dblk + 6
        lda     kidx
        asl     a
        tax
        lda     key_lbls,x
        sta     dblk + 12
        lda     #^key_lbls
        sta     dblk + 14
        jmp     wdraw

wdraw:  lda     win
        ptr     dblk
        sys     SYS_WDRAW
        rts

; ── Read-only tables & strings ───────────────────────────────────────────────
        .segment "RODATA"
t_title:   .byte "OPL2 FM Synth", 0
s_hw_ok:   .byte "YM3812 OPL2 ready (REV $0C)", 0
s_hw_no:   .byte "No OPL2 hardware (needs REV $0C+)", 0
s_ready:   .byte "Ready - click a demo or press A-K", 0
s_need:    .byte "Flash the REV $0C bitstream to use OPL2.", 0
s_stopped: .byte "Stopped - ready", 0
s_chords:  .byte "Playing: FM Electric Piano chords (C Am F G)", 0
s_melody:  .byte "Playing: AdLib FM synth bass + brass lead", 0
s_ws0:     .byte "Playing: OPL2 Waveform 0 (sine)", 0
s_ws1:     .byte "Playing: OPL2 Waveform 1 (half-sine)", 0
s_ws2:     .byte "Playing: OPL2 Waveform 2 (abs-sine)", 0
s_ws3:     .byte "Playing: OPL2 Waveform 3 (quarter-sine)", 0
s_mix:     .byte "Playing: OPL2 FM chord + Lau PCM pan", 0
s_live:    .byte "Live FM keyboard (A-K / mouse)", 0
s_p0:      .byte "Live patch: FM Electric Piano", 0
s_p1:      .byte "Live patch: AdLib FM Brass", 0
s_p2:      .byte "Live patch: FM Synth Bass", 0
s_kbd:     .byte "Live FM keys: A S D F G H J K (or click keys)", 0

sb_chords: .byte "Chords", 0
sb_melody: .byte "Bass+Lead", 0
sb_waves:  .byte "Waves", 0
sb_mix:    .byte "OPL2+Lau", 0
sb_p0:     .byte "E-Piano", 0
sb_p1:     .byte "Brass", 0
sb_p2:     .byte "Bass", 0
sb_stop:   .byte "Stop", 0

kn0: .byte "C4", 0
kn1: .byte "D4", 0
kn2: .byte "E4", 0
kn3: .byte "F4", 0
kn4: .byte "G4", 0
kn5: .byte "A4", 0
kn6: .byte "B4", 0
kn7: .byte "C5", 0

kl0: .byte "A", 0
kl1: .byte "S", 0
kl2: .byte "D", 0
kl3: .byte "F", 0
kl4: .byte "G", 0
kl5: .byte "H", 0
kl6: .byte "J", 0
kl7: .byte "K", 0

note_lbls: .addr kn0, kn1, kn2, kn3, kn4, kn5, kn6, kn7
key_lbls:  .addr kl0, kl1, kl2, kl3, kl4, kl5, kl6, kl7
ws_labels: .addr s_ws0, s_ws1, s_ws2, s_ws3
patch_labels: .addr s_p0, s_p1, s_p2

; HID usages for A S D F G H J K
hid_keys: .word $04, $16, $07, $09, $0A, $0B, $0D, $0E

; Live keyboard notes C4..C5
live_lo:  .byte .lobyte(FN_C), .lobyte(FN_D), .lobyte(FN_E), .lobyte(FN_F)
          .byte .lobyte(FN_G), .lobyte(FN_A), .lobyte(FN_B), .lobyte(FN_C)
live_hi:  .byte $30|.hibyte(FN_C), $30|.hibyte(FN_D), $30|.hibyte(FN_E), $30|.hibyte(FN_F)
          .byte $30|.hibyte(FN_G), $30|.hibyte(FN_A), $30|.hibyte(FN_B), $34|.hibyte(FN_C)

; OPL2 operator register bases and per-channel offsets (ch 0..8)
op_base:  .word $0020, $0040, $0060, $0080, $00E0
op_mod:   .byte $00, $01, $02, $08, $09, $0A, $10, $11, $12
op_car:   .byte $03, $04, $05, $0B, $0C, $0D, $13, $14, $15

; Patches: {mod 20,40,60,80,E0, car 20,40,60,80,E0, ch C0}
pt_epiano: .byte $0E, $5C, $F7, $55, $00,  $01, $06, $F3, $45, $00,  $06
pt_bass:   .byte $01, $10, $F8, $56, $01,  $01, $04, $F4, $37, $00,  $0A
pt_brass:  .byte $61, $14, $B4, $26, $00,  $61, $06, $D2, $16, $01,  $08
pt_pure:   .byte $01, $3F, $F0, $0F, $00,  $21, $08, $F0, $07, $00,  $00

; Chords: C (C4 E4 G4 C5), Am (A3 E4 A4 C5), F (F3 C4 F4 A4), G (G3 D4 G4 B4)
chords_lo:
        .byte .lobyte(FN_C), .lobyte(FN_E), .lobyte(FN_G), .lobyte(FN_C)
        .byte .lobyte(FN_A), .lobyte(FN_E), .lobyte(FN_A), .lobyte(FN_C)
        .byte .lobyte(FN_F), .lobyte(FN_C), .lobyte(FN_F), .lobyte(FN_A)
        .byte .lobyte(FN_G), .lobyte(FN_D), .lobyte(FN_G), .lobyte(FN_B)
chords_hi:
        .byte $30|.hibyte(FN_C), $30|.hibyte(FN_E), $30|.hibyte(FN_G), $34|.hibyte(FN_C)
        .byte $2C|.hibyte(FN_A), $30|.hibyte(FN_E), $30|.hibyte(FN_A), $34|.hibyte(FN_C)
        .byte $2C|.hibyte(FN_F), $30|.hibyte(FN_C), $30|.hibyte(FN_F), $30|.hibyte(FN_A)
        .byte $2C|.hibyte(FN_G), $30|.hibyte(FN_D), $30|.hibyte(FN_G), $30|.hibyte(FN_B)

; 16-step synth bass (block 2) + brass lead (block 4/5)
bass_lo:
        .byte .lobyte(FN_C), .lobyte(FN_C), .lobyte(FN_G), .lobyte(FN_C)
        .byte .lobyte(FN_A), .lobyte(FN_A), .lobyte(FN_E), .lobyte(FN_A)
        .byte .lobyte(FN_F), .lobyte(FN_F), .lobyte(FN_C), .lobyte(FN_F)
        .byte .lobyte(FN_G), .lobyte(FN_G), .lobyte(FN_D), .lobyte(FN_G)
bass_hi:
        .byte $28|.hibyte(FN_C), $28|.hibyte(FN_C), $28|.hibyte(FN_G), $28|.hibyte(FN_C)
        .byte $28|.hibyte(FN_A), $28|.hibyte(FN_A), $28|.hibyte(FN_E), $28|.hibyte(FN_A)
        .byte $28|.hibyte(FN_F), $28|.hibyte(FN_F), $28|.hibyte(FN_C), $28|.hibyte(FN_F)
        .byte $28|.hibyte(FN_G), $28|.hibyte(FN_G), $28|.hibyte(FN_D), $28|.hibyte(FN_G)

lead_lo:
        .byte .lobyte(FN_C), .lobyte(FN_E), .lobyte(FN_G), .lobyte(FN_C)
        .byte .lobyte(FN_A), .lobyte(FN_G), .lobyte(FN_E), .lobyte(FN_C)
        .byte .lobyte(FN_F), .lobyte(FN_A), .lobyte(FN_C), .lobyte(FN_A)
        .byte .lobyte(FN_G), .lobyte(FN_B), .lobyte(FN_D), .lobyte(FN_C)
lead_hi:
        .byte $30|.hibyte(FN_C), $30|.hibyte(FN_E), $30|.hibyte(FN_G), $34|.hibyte(FN_C)
        .byte $30|.hibyte(FN_A), $30|.hibyte(FN_G), $30|.hibyte(FN_E), $30|.hibyte(FN_C)
        .byte $30|.hibyte(FN_F), $30|.hibyte(FN_A), $34|.hibyte(FN_C), $30|.hibyte(FN_A)
        .byte $30|.hibyte(FN_G), $30|.hibyte(FN_B), $34|.hibyte(FN_D), $34|.hibyte(FN_C)

; 256-byte signed 8-bit sine wave for Lau (1 full cycle)
sine256:
        .byte $00,$03,$06,$09,$0C,$0F,$12,$15,$18,$1C,$1F,$22,$25,$28,$2B,$2E
        .byte $30,$33,$36,$39,$3C,$3F,$41,$44,$47,$49,$4C,$4E,$51,$53,$55,$58
        .byte $5A,$5C,$5E,$60,$62,$64,$66,$68,$6A,$6C,$6D,$6F,$70,$72,$73,$75
        .byte $76,$77,$78,$79,$7A,$7B,$7C,$7C,$7D,$7E,$7E,$7F,$7F,$7F,$7F,$7F
        .byte $7F,$7F,$7F,$7F,$7F,$7F,$7E,$7E,$7D,$7C,$7C,$7B,$7A,$79,$78,$77
        .byte $76,$75,$73,$72,$70,$6F,$6D,$6C,$6A,$68,$66,$64,$62,$60,$5E,$5C
        .byte $5A,$58,$55,$53,$51,$4E,$4C,$49,$47,$44,$41,$3F,$3C,$39,$36,$33
        .byte $30,$2E,$2B,$28,$25,$22,$1F,$1C,$18,$15,$12,$0F,$0C,$09,$06,$03
        .byte $00,$FD,$FA,$F7,$F4,$F1,$EE,$EB,$E8,$E4,$E1,$DE,$DB,$D8,$D5,$D2
        .byte $D0,$CD,$CA,$C7,$C4,$C1,$BF,$BC,$B9,$B7,$B4,$B2,$AF,$AD,$AB,$A8
        .byte $A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$93,$91,$90,$8E,$8D,$8B
        .byte $8A,$89,$88,$87,$86,$85,$84,$84,$83,$82,$82,$81,$81,$81,$81,$81
        .byte $81,$81,$81,$81,$81,$81,$82,$82,$83,$84,$84,$85,$86,$87,$88,$89
        .byte $8A,$8B,$8D,$8E,$90,$91,$93,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4
        .byte $A6,$A8,$AB,$AD,$AF,$B2,$B4,$B7,$B9,$BC,$BF,$C1,$C4,$C7,$CA,$CD
        .byte $D0,$D2,$D5,$D8,$DB,$DE,$E1,$E4,$E8,$EB,$EE,$F1,$F4,$F7,$FA,$FD

; ── Window & UI controls ─────────────────────────────────────────────────────
        .segment "DATA"
wblk:   .word   158, 90, W, H
        .faraddr t_title
        .byte   0

allc:   .addr   l_hw, l_stat, b_chords, b_melody, b_waves, b_mix
        .addr   b_p0, b_p1, b_p2, b_stop, l_kbd, 0

l_hw:     .byte UT_LABEL, 0
          .word 10, 8, W - 20, UI_LINE, 0
          .addr s_hw_ok
l_stat:   .byte UT_LABEL, 0
          .word 10, 24, W - 20, UI_LINE, 0
          .addr s_ready
b_chords: .byte UT_BUTTON, 0
          .word 10, 44, 68, UI_BTNH, UF_FOCUS | UF_DEFAULT
          .addr sb_chords
b_melody: .byte UT_BUTTON, 0
          .word 84, 44, 80, UI_BTNH, 0
          .addr sb_melody
b_waves:  .byte UT_BUTTON, 0
          .word 170, 44, 64, UI_BTNH, 0
          .addr sb_waves
b_mix:    .byte UT_BUTTON, 0
          .word 240, 44, 74, UI_BTNH, 0
          .addr sb_mix
b_p0:     .byte UT_BUTTON, 0
          .word 10, 72, 68, UI_BTNH, 0
          .addr sb_p0
b_p1:     .byte UT_BUTTON, 0
          .word 84, 72, 62, UI_BTNH, 0
          .addr sb_p1
b_p2:     .byte UT_BUTTON, 0
          .word 152, 72, 58, UI_BTNH, 0
          .addr sb_p2
b_stop:   .byte UT_BUTTON, 0
          .word 240, 72, 74, UI_BTNH, 0
          .addr sb_stop
l_kbd:    .byte UT_LABEL, 0
          .word 10, 102, W - 20, UI_LINE, 0
          .addr s_kbd

; ── BSS / ZEROPAGE ───────────────────────────────────────────────────────────
        .segment "BSS"
wsown:  .res    2
win:    .res    2
hwrev:  .res    2
has_opl:.res    2
opl_st: .res    2
mode:   .res    2
step:   .res    2
tickc:  .res    2
patch:  .res    2
lau_v:  .res    2
mkey:   .res    2
kidx:   .res    2
kx:     .res    2
ktmp:   .res    4
pch:    .res    2
pmod:   .res    2
pcar:   .res    2
kdown:  .res    16
spb:    .res    16
dblk:   .res    16

        .segment "ZEROPAGE"
pptr:   .res    2

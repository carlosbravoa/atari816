; mu_eng.s - Music: the engine (/SYSTEM/MUSICD.PRG). Its start, the commands, the statuses,
; the module's data read from it, the next song. Included by music.s.
;
; The phases of a song (phase): MC_LOAD sent -> PH_WAIT until the load's first status
; (MST_LOADING or MST_ERROR: the statuses before it are the old song's and are left alone)
; -> PH_LOAD (the percent shown) -> PH_READY at the first loaded state (stopped, playing,
; paused), when the info block, the title and the sample names are read (one MC_READ at a
; time: the answers carry no offset, so the next is asked when one came; one not answered
; within RDT frames or ticks is asked again) -> PH_FAIL on MST_ERROR (lerr: the code).

        .segment "CODE"

; ---------------------------------------------------------------- the start
; a port of ours, the engine spawned with "-p PORT" at priority 0, its hello awaited (2 s at
; most) -> C clear: eport is its port; C set: it did not start (an alert said why)
eng_start:
        sys     SYS_PCREATE
        bcc     :+
        ldx     #.loword(al_noport)
        jsr     ui_alert
        sec
        rts
:       sta     myport
        jsr     dec16p                  ; "-p N"
        ldx     #0
:       lda     numbuf,x
        sta     eargs+3,x
        inx
        cpx     #4
        bcc     :-
        lda     #.loword(p_engine)      ; {u24 path, u24 args, u8 priority 0}
        sta     spblk
        lda     #.loword(eargs)
        sta     spblk+3
        sep     #$20
        .a8
        lda     pbank
        sta     spblk+2
        sta     spblk+5
        stz     spblk+6
        rep     #$20
        .a16
        ptr     spblk
        sys     SYS_SPAWN
        bcc     @wait
        ldx     #.loword(al_noeng)      ; not there, no memory, ...
        cmp     #$44
        beq     :+
        cmp     #$45
        beq     :+
        sta     z:t0
        ldx     #.loword(al_engerr)
        lda     z:t0
        jsr     hex8a                   ; (the code in its message)
:       jsr     ui_alert
        sec
        rts
@wait:  sta     etask
        lda     #HELLOT
        sta     z:t5
@l:     lda     myport
        ora     #RV_POLL
        ptr     rmsg
        sys     SYS_RECV
        bcs     @none
        lda     rmsg
        and     #$00FF
        cmp     #MS_HELLO
        bne     @l
        lda     rmsg+1
        and     #$00FF
        sta     eport
        clc
        rts
@none:  lda     #10
        sys     SYS_SLEEP
        dec     z:t5
        bne     @l
        lda     etask                   ; (no hello: it is ended)
        sys     SYS_KILL
        ldx     #.loword(al_nohello)
        jsr     ui_alert
        sec
        rts

; A = an error code -> its two hex digits into the engine error alert's text ("$##")
hex8a:  pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        and     #$000F
        tax
        lda     hexd,x
        sep     #$20
        .a8
        sta     m_engerr_h
        rep     #$20
        .a16
        pla
        and     #$000F
        tax
        lda     hexd,x
        sep     #$20
        .a8
        sta     m_engerr_h+1
        rep     #$20
        .a16
        rts

; MC_QUIT: the music stops, the engine ends
eng_quit:
        lda     #MC_QUIT
        ldx     #0
        jmp     eng_cmd

; ---------------------------------------------------------------- commands
; A = command, X = its byte 1 (the rest 0): sent
eng_cmd:
        pha
        phx
        jsr     msgclr
        plx
        pla
        sep     #$20
        .a8
        sta     msg
        txa
        sta     msg+1
        rep     #$20
        .a16
; msg to the engine; a full queue is tried again (10 ms apart, 1 s at most) -> C set: not sent
eng_send:
        lda     #100
        sta     z:t7
@try:   lda     eport
        ptr     msg
        sys     SYS_SEND
        bcc     @ok
        cmp     #EAGAIN
        bne     @gone
        lda     #10
        sys     SYS_SLEEP
        dec     z:t7
        bne     @try
        sec
        rts
@ok:    clc
        rts
@gone:  lda     dead                    ; the engine is not there any more: said once
        bne     :+
        inc     dead
        ldx     #.loword(al_dead)
        jsr     ui_alert
:       sec
        rts

msgclr: ldx     #14
:       stz     msg,x
        dex
        dex
        bpl     :-
        rts

; the settings to the engine: the volume, the separation, the loop
eng_settings:
        jsr     eng_vol
        jsr     eng_sep
eng_loop:
        ldx     #0                      ; Repeat one: the engine starts the song again itself
        lda     mrep
        cmp     #RP_ONE
        bne     :+
        inx
:       lda     #MC_LOOP
        jmp     eng_cmd
eng_vol:
        lda     #MC_VOL
        ldx     vol
        jmp     eng_cmd
eng_sep:
        lda     #MC_SEP
        ldx     msep
        jmp     eng_cmd

; A = a playlist row: that song loaded and played
play_entry:
        sta     cur
        sta     lst_pl+LS_SEL
        inc     dirty
        jsr     pl_get                  ; its path -> pbuf
        jsr     eng_path
        lda     #MC_LOAD
        ldx     #MCL_PLAY
        jsr     eng_cmd
        lda     #PH_WAIT
        sta     phase
        stz     pct
        stz     lerr
        stz     rd_ph                   ; (no read wanted)
        stz     info+MI_KIND
        stz     info+MI_NSMP
        stz     nsmp
        lda     #MST_EMPTY
        sta     estate
        lda     #C_BLACK | (C_BODY << 8)
        sta     tink
        jsr     namepb                  ; the title: the file's name until the module's
        ldx     #.loword(nbuf)
        ldy     #.loword(tstr)
        jsr     ui_strcpy
        ldx     #.loword(m_loading)
        ldy     #.loword(fstr)
        jsr     ui_strcpy
        lda     #C_DARK
        sta     fink
        stz     pstr
        stz     tmstr
        lda     #4                      ; the meters: four channels until the module says
        jsr     setnch
        jsr     draw_info
        lda     view                    ; the lists: the mark, no samples yet
        bne     :+
        lda     cur                     ; (all rows: the mark moved)
        ldx     #.loword(lst_pl)
        jsr     ui_lssel
        ldx     #.loword(lst_pl)
        jsr     ui_draw
        bra     :++
:       stz     lst_sm+LS_COUNT
        stz     lst_sm+LS_TOP
        lda     #$FFFF
        sta     lst_sm+LS_SEL
        ldx     #.loword(lst_sm)
        jsr     ui_draw
:       jsr     draw_tabs
        jsr     draw_status
        jsr     draw_btns
        jmp     menustate

; the path in pbuf to the engine: MC_PATH pieces of 14 characters (the 0 in the last one)
eng_path:
        stz     z:t5                    ; the offset
@piece: jsr     msgclr
        lda     #MC_PATH
        sep     #$20
        .a8
        sta     msg
        lda     z:t5
        sta     msg+1
        rep     #$20
        .a16
        ldx     z:t5
        ldy     #0
        stz     z:t6                    ; the 0 sent
:       lda     pbuf,x
        and     #$00FF
        sep     #$20
        .a8
        sta     msg+2,y
        rep     #$20
        .a16
        cmp     #0
        bne     :+
        inc     z:t6
        bra     :++
:       inx
        iny
        cpy     #14
        bcc     :--
:       jsr     eng_send
        bcs     @out
        lda     z:t6
        bne     @out
        lda     z:t5
        clc
        adc     #14
        sta     z:t5
        cmp     #PATHMAX
        bcc     @piece
@out:   rts

; ---------------------------------------------------------------- statuses
; every message waiting: statuses (each one's state looked at, the last one shown) and
; data; then the song's end (the next one) and the display
poll:   stz     gotst
@l:     lda     myport
        ora     #RV_POLL
        ptr     rmsg
        sys     SYS_RECV
        bcs     @done
        lda     rmsg
        and     #$00FF
        cmp     #MS_STATUS
        bne     :+
        jsr     st_one
        bra     @l
:       cmp     #MS_DATA
        bne     @l
        jsr     rd_data
        bra     @l
@done:  lda     ended
        beq     :+
        stz     ended
        jsr     auto_next
:       lda     gotst
        beq     :+
        jsr     st_show
:       rts

; one status (rmsg): the phase moves on; it becomes the status shown
st_one: lda     rmsg+1
        and     #$00FF
        sta     z:t0
        lda     phase
        cmp     #PH_WAIT
        bne     @load
        lda     z:t0                    ; the load's first status?
        cmp     #MST_LOADING
        beq     :+
        cmp     #MST_ERROR
        beq     :+
        rts                             ; (the old song's)
:       lda     #PH_LOAD
        sta     phase
@load:  lda     phase
        cmp     #PH_LOAD
        bne     @ready
        lda     z:t0
        cmp     #MST_LOADING
        bne     :+
        lda     rmsg+5
        and     #$00FF
        sta     pct
        inc     infodirty
        bra     @take
:       cmp     #MST_ERROR
        bne     :+
        lda     #PH_FAIL
        sta     phase
        lda     rmsg+5
        and     #$00FF
        sta     lerr
        inc     infodirty
        bra     @take
:       cmp     #MST_STOPPED            ; loaded
        bcc     @take
        cmp     #MST_ERROR
        bcs     @take
        lda     #PH_READY
        sta     phase
        inc     infodirty
        jsr     rd_begin
        bra     @take
@ready: cmp     #PH_READY
        bne     @take
        lda     z:t0
        cmp     #MST_ENDED              ; the end (once)
        bne     :+
        cmp     lstate
        beq     @take
        inc     ended
        bra     @take
:       cmp     #MST_ERROR
        bne     @take
        lda     #PH_FAIL
        sta     phase
        lda     rmsg+5
        and     #$00FF
        sta     lerr
        inc     infodirty
@take:  lda     z:t0
        sta     lstate
        ldx     #14
:       lda     rmsg,x
        sta     st,x
        dex
        dex
        bpl     :-
        inc     gotst
        rts

; the last status shown: the state (buttons, meters on or off), the position, the time, the
; bar, the levels the meters go to
st_show:
        lda     st+1
        and     #$00FF
        ldx     phase
        cpx     #PH_READY
        beq     :+
        lda     #MST_EMPTY              ; (loading or failed: nothing plays)
        cpx     #PH_LOAD
        bne     :+
        lda     #MST_LOADING
:       cmp     estate
        beq     :+
        sta     estate
        jsr     draw_btns
        inc     infodirty
:       lda     infodirty               ; the format line (loading, an error, paused...)
        beq     :+
        stz     infodirty
        jsr     mkfmt
        jsr     draw_fmt
:       lda     phase
        cmp     #PH_READY
        bne     @bar
        jsr     mkpos                   ; position and time: drawn when they changed
        jsr     draw_pos
@bar:   jsr     barpx
        jsr     draw_bar
        ldx     #0                      ; the levels (playing only)
        lda     estate
        cmp     #MST_PLAYING
        bne     @zero
        ldy     #0
:       lda     st+8,y
        and     #$00FF
        cmp     #65
        bcc     :+
        lda     #64
:       sta     lv_t,x
        iny
        inx
        inx
        cpx     #16
        bcc     :--
        bra     @vbl
@zero:  stz     lv_t,x
        inx
        inx
        cpx     #16
        bcc     @zero
@vbl:   lda     estate                  ; the frames on while playing (and until the bars fell)
        cmp     #MST_PLAYING
        bne     :+
        lda     #1
        jmp     setvbl
:       rts

; WE_VBL on (A = 1) or off
setvbl: cmp     vblon
        beq     :+
        sta     vblon
        tax
        lda     win
        sys     SYS_WINVBL
:       rts

; the song ended (MST_ENDED, the loop off): the next one by the modes, or nothing
auto_next:
        lda     pl_n
        beq     @out
        lda     mrep
        cmp     #RP_ONE
        bne     :+
        lda     #MC_PLAY                ; (the engine should have looped: again from the start)
        ldx     #0
        jmp     eng_cmd
:       jsr     pick_next
        bcc     @end
        jmp     play_entry
@end:   lda     mrep                     ; the end of the playlist: Repeat all goes round
        cmp     #RP_ALL
        bne     @out
        lda     #0
        jmp     play_entry
@out:   rts

; the song after cur -> C set, A = its row; C clear: the playlist ended (shuffle: another
; one at random, never the same when there are two or more)
pick_next:
        lda     pl_n
        beq     @no
        lda     shuf
        beq     @seq
        lda     pl_n
        cmp     #2
        bcc     @seq
:       jsr     rand16                  ; a row other than cur
        ldx     pl_n
        jsr     umod16
        cmp     cur
        beq     :-
        sec
        rts
@seq:   lda     cur
        cmp     pl_n
        bcc     :+
        lda     lst_pl+LS_SEL           ; (nothing loaded: the selected one)
        cmp     pl_n
        bcc     @yes
        lda     #0
        bra     @yes
:       inc     a
        cmp     pl_n
        bcs     @no
@yes:   sec
        rts
@no:    clc
        rts

; xorshift -> A (never 0)
rand16: lda     rng
        bne     :+
        sys     SYS_UPTIME
        ora     #1
:       sta     z:t0
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        eor     z:t0
        sta     z:t0
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        eor     z:t0
        sta     z:t0
        xba
        and     #$FF00
        eor     z:t0
        sta     rng
        rts

; ---------------------------------------------------------------- the module's data
; rd_ph: 0 nothing, 1 the info block, 2 the title, 3 the sample headers. One MC_READ at a
; time: rd_off (in the area), rd_left bytes still wanted, rd_dst (in our bank)
rd_begin:
        lda     #1                      ; the info block: 24 bytes of area 1
        sta     rd_ph
        stz     rd_off
        lda     #MI_SIZEOF
        sta     rd_left
        lda     #.loword(info)
        sta     rd_dst
        lda     #1
        sta     rd_area
        jmp     rd_ask

; the next piece asked (at most 14 bytes)
rd_ask: jsr     msgclr
        lda     rd_left
        cmp     #15
        bcc     :+
        lda     #14
:       sep     #$20
        .a8
        sta     msg+1
        lda     #MC_READ
        sta     msg
        lda     rd_area
        sta     msg+5
        rep     #$20
        .a16
        lda     rd_off
        sta     msg+2
        stz     rd_wait
        jmp     eng_send

; a piece not answered in time: asked again
rd_tick:
        lda     rd_ph
        beq     :+
        inc     rd_wait
        lda     rd_wait
        cmp     #RDT
        bcc     :+
        jmp     rd_ask
:       rts

; MS_DATA: the bytes kept, the next piece or the next part
rd_data:
        lda     rd_ph
        beq     @out                    ; (not asked: an old answer)
        lda     rmsg+1
        and     #$00FF
        beq     @end                    ; nothing there: this part ends
        cmp     #15
        bcs     @end
        sta     z:t0
        ldx     #0
        ldy     rd_dst
:       lda     rmsg+2,x
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        inx
        iny
        cpx     z:t0
        bcc     :-
        sty     rd_dst
        lda     rd_off
        clc
        adc     z:t0
        sta     rd_off
        lda     rd_left
        sec
        sbc     z:t0
        sta     rd_left
        beq     @end
        bcc     @end
        jmp     rd_ask
@end:   lda     rd_ph
        stz     rd_ph
        cmp     #1
        beq     rd_info
        cmp     #2
        jeq     rd_title
        jmp     rd_smp
@out:   rts

; the info block came: the meters' channels, the format line; a MOD: its title next
rd_info:
        lda     info+MI_KIND
        and     #$00FF
        cmp     #2
        bne     :+
        lda     #2                      ; a WAV: left and right
        bra     :++
:       lda     info+MI_NCHAN
        and     #$00FF
:       jsr     setnch
        inc     infodirty
        lda     info+MI_KIND
        and     #$00FF
        cmp     #1
        bne     @out
        lda     info+MI_NSMP
        and     #$00FF
        sta     nsmp
        lda     #2                      ; the title: 20 bytes of area 0 at 0
        sta     rd_ph
        stz     rd_off
        stz     rd_area
        lda     #20
        sta     rd_left
        lda     #.loword(mtitle)
        sta     rd_dst
        ldx     #22
:       stz     mtitle,x
        dex
        dex
        bpl     :-
        jmp     rd_ask
@out:   rts

; the title came: shown (an empty one: the file name stays); the sample headers next
rd_title:
        ldx     #.loword(mtitle)        ; printable, without blanks at its end
        ldy     #20
        jsr     clean
        lda     mtitle
        and     #$00FF
        beq     :+
        ldx     #.loword(mtitle)
        ldy     #.loword(tstr)
        jsr     ui_strcpy
        jsr     draw_title
:       lda     #3                      ; 31 x 30 bytes of area 0 from 20
        sta     rd_ph
        lda     #20
        sta     rd_off
        stz     rd_area
        lda     #NSMPB
        sta     rd_left
        lda     #.loword(smp)
        sta     rd_dst
        ldx     #0
:       stz     smp,x
        inx
        inx
        cpx     #NSMPB + 2
        bcc     :-
        jmp     rd_ask

; the sample headers came: the samples' list
rd_smp: lda     nsmp
        sta     lst_sm+LS_COUNT
        stz     lst_sm+LS_TOP
        lda     #$FFFF
        sta     lst_sm+LS_SEL
        lda     view
        beq     :+
        ldx     #.loword(lst_sm)
        jsr     ui_draw
:       jmp     draw_tabs

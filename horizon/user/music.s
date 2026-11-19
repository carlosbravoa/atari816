; MUSIC - the music player (/BIN/MUSIC.PRG, Horizon 0.26): the window "Music".
;   music               the player with the playlist of the last session
;   music PATH          PATH (a MOD or WAV file, a folder, or a URL) added to the playlist and
;                       played at once (Files and the Desktop open .MOD and .WAV files so)
;   music -t            the self test (no window): text, compared by make test
;
; The playing itself is done by the engine, /SYSTEM/MUSICD.PRG (protocol: user/music.inc):
; Music starts it at priority 0 with "-p PORT" (a port of Music's own), waits for its
; MS_HELLO and from then on sends it commands; the engine runs on its own (it keeps playing
; while Music is minimised or behind other windows) and sends MS_STATUS messages. Music reads
; them without waiting (recv | RV_POLL until EAGAIN, the last one kept) at every vertical
; blank while the music plays (WE_VBL) and ten times a second otherwise (WE_TICK). Closing the
; window sends MC_QUIT: the music stops.
;
; Without Lau (REV $0A, the sample player) Music says so and ends. One instance only
; (SYS_SINGLE). A file opened in Files or on the Desktop while Music runs reaches it through
; /SYSTEM/OPEN.REQ (the controls library's ui_launch writes it when the kernel answers
; ERUNNING; mu_list.s, "requests"); a file dropped on the window is added too.
;
; The window: the song's title, its format, the position and the time, the level meters
; (one bar a channel, drawn once a frame with one sheet_draw of fills), the position bar
; (click: seek), the buttons Previous, Play, Pause, Stop, Next, the volume and the stereo
; separation, then the playlist or the module's samples (two tabs, View menu), and a
; status line. The playlist and the settings are kept in /SYSTEM/MUSIC.CFG.
;
; One assembly unit:
;   music.s     start, the engine's start, events, keys, the mouse, menus, the actions
;   mu_eng.s    the engine: commands, statuses, reading the module's data, the next song
;   mu_draw.s   drawing: the texts, the meters, the bar, the buttons, the tabs, the lists
;   mu_list.s   the playlist, folders, names, the settings file, requests, error texts
;   mu_test.s   the self test
;   mu_data.s   tables, texts, variables
        .include "horizon.inc"
        .include "ui.inc"
        .include "music.inc"

; ---- the layout (the window's content) ----
WW      = 400
WH      = 288
M       = 8                             ; margins
MTW     = 112                           ; the meters' box (top right)
MTH     = 46
MTX     = WW - M - MTW
MTY     = 8
MBH     = MTH - 8                       ; a bar's height at most
MBY     = MTY + MTH - 4                 ; the bars' bottom (exclusive)
TXW     = MTX - 2 * M                   ; the texts left of the meters
TY1     = 8                             ; the title, the format, the position and time
TY2     = 23
TY3     = 38
TIMEW   = 64                            ; the time: right-aligned in the last TIMEW pixels
PBX     = M                             ; the position bar
PBY     = 60
PBW     = WW - 2 * M
PBH     = 12
BTY     = 78                            ; the buttons
BTW     = 30
BTH     = 22
BTG     = 4
NBTN    = 5
VLX     = 184                           ; "Volume" and its bar
VBX     = 226
VBW     = 58
VBY     = BTY + 5
VBH     = 12
SLX     = 293                           ; "Stereo" and its bar
SBX     = 338
SBW     = WW - M - SBX
TABY    = 106                           ; the tabs (Playlist, Samples)
TABH    = 18
LSY     = TABY + TABH                   ; the lists
LSROWS  = 10
LSH     = 2 + LSROWS * UI_ROWH
STATY     = LSY + LSH + 6                 ; the status line
MKW     = 12                            ; the playlist's indent (the playing mark)
SNW     = 22                            ; the samples' indent (the number)

; ---- the rest ----
MAXPL   = 256                           ; songs in the playlist at most (128 bytes each, a bank)
PATHMAX = 128                           ; a path with its 0
NSMPB   = 31 * 30                       ; the sample headers (MOD, the 31-sample layout)
TICK    = 10                            ; the timer: 0.1 s
REQT    = 10                            ; requests looked for every REQT ticks
HELLOT  = 200                           ; the engine's hello: 200 x 10 ms at most
RDT     = 30                            ; a read not answered: asked again after 30 frames / ticks
PH_NONE = 0                             ; phase: nothing asked
PH_WAIT = 1                             ;   MC_LOAD sent: waiting for its first status
PH_LOAD = 2                             ;   loading
PH_READY = 3                            ;   loaded (stopped, playing, paused, ended)
PH_FAIL = 4                             ;   the load failed (lerr)
RP_OFF  = 0                             ; repeat
RP_ALL  = 1
RP_ONE  = 2
B_PREV  = 0                             ; the buttons
B_PLAY  = 1
B_PAUSE = 2
B_STOP  = 3
B_NEXT  = 4
DR_VOL  = 1                             ; a drag on a bar
DR_SEP  = 2
C_DIMG  = 16 + 6                        ; the meters' unlit parts: dark green, yellow, red
C_DIMY  = 16 + 36 + 6
C_DIMR  = 16 + 36

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        sep     #$20                    ; the program's bank
        .a8
        phb
        pla
        rep     #$20
        .a16
        and     #$00FF
        sta     pbank
        jsr     getargs
        sys     SYS_BALLOC              ; the playlist's bank
        bcc     :+
        print   "music: not enough memory\n"
        exit    1
:       sta     plbank
        jsr     pl_init
        lda     tmode
        beq     :+
        jmp     test_run
:       sys     SYS_SINGLE              ; one Music only: the kernel raised the open one
        bcc     :+
        exit    0
:       sys     SYS_WSSTART
        bcc     :+
        print   "music: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        sys     SYS_SSTAT               ; Lau?
        bcc     :+
        cmp     #ENODEV
        bne     :+
        ldx     #.loword(al_nolau)
        jsr     ui_alert
        jmp     bye
:       jsr     eng_start               ; the engine (C set: it did not start, an alert said so)
        bcc     :+
        jmp     bye
:       lda     #4                      ; the meters: four bars until a module says
        jsr     setnch
        jsr     cfg_load                ; the playlist and settings of the last session
        jsr     req_clear               ; (an old request is no longer wanted)
        ptr     wopen
        sys     SYS_WOPEN
        bcc     :+
        jsr     eng_quit
        jsr     stopws
        print   "music: no window\n"
        exit    1
:       sta     win
        inc     winok
        sep     #$20
        .a8
        sta     lst_pl+CT_WIN
        sta     lst_sm+CT_WIN
        rep     #$20
        .a16
        lda     #0
        ptr     t_title
        sys     SYS_TNAME
        lda     win
        ptr     menus
        sys     SYS_WMENU
        jsr     menustate
        lda     win
        ldx     #TICK
        sys     SYS_WTIMER
        jsr     sysvol
        jsr     eng_settings            ; volume, separation, loop
        lda     pl_n                    ; the playlist shown, the last song selected
        sta     lst_pl+LS_COUNT
        lda     cur
        cmp     pl_n
        bcc     :+
        lda     #$FFFF
        sta     cur
:       sta     lst_pl+LS_SEL
        sec                             ; (shown in the middle; ui_draw keeps the top in range)
        sbc     #LSROWS / 2
        bcs     :+
        lda     #0
:       sta     lst_pl+LS_TOP
        lda     #$FFFF
        sta     cur                     ; (nothing loaded yet: no mark)
        jsr     idletext
        jsr     draw_all
        lda     abuf                    ; the argument: added and played
        and     #$00FF
        beq     loop
        jsr     open_arg

; ---------------------------------------------------------------- events
loop:   lda     #0
        jsr     ui_getev
        bcs     loop
        lda     ui_ev
        and     #$00FF
        cmp     #WE_VBL
        jeq     onframe
        cmp     #WE_TICK
        jeq     ontick
        cmp     #WE_KEY
        bne     :+
        jsr     onkey                   ; C set: used
        bcs     loop
:       lda     ui_ev
        and     #$00FF
        cmp     #WE_BUTTON
        beq     @mouse
        cmp     #WE_MOTION
        bne     @ctl
@mouse: lda     drag                    ; a drag of our own, or a button of ours held
        jne     onmouse
        lda     btnp
        cmp     #$FFFF
        jne     onmouse
@ctl:   jsr     ctls
        jsr     ui_event
        cmp     #UA_OPEN
        bne     :+
        jsr     onopen
        bra     loop
:       cmp     #UA_NONE
        bne     loop
        lda     ui_ev
        and     #$00FF
        cmp     #WE_BUTTON
        jeq     onmouse
        cmp     #WE_MOTION
        jeq     onmouse
        cmp     #WE_MENU
        jeq     onmenu
        cmp     #WE_CLOSE
        jeq     quit
        cmp     #WE_FOCUS
        bne     :+
        jsr     sysvol
        jsr     req_check
        jmp     loop
:       cmp     #WE_UNFOCUS
        bne     :+
        jsr     cfg_maybe               ; (the settings saved when they changed)
        jmp     loop
:       cmp     #WE_DROP
        jeq     ondrop
        jmp     loop

; X = the control list of the view shown
ctls:   ldx     #.loword(ctl_pl)
        lda     view
        beq     :+
        ldx     #.loword(ctl_sm)
:       rts

; a vertical blank: the statuses, the meters
onframe:
        jsr     poll
        jsr     meters
        jmp     loop
; the timer: the statuses (the engine's answers also while nothing plays), requests
ontick: jsr     poll
        jsr     rd_tick
        inc     reqt
        lda     reqt
        cmp     #REQT
        jcc     loop
        stz     reqt
        jsr     req_check
        jmp     loop

; ---------------------------------------------------------------- the end
quit:   jsr     eng_quit
        jsr     cfg_maybe
        lda     win
        sys     SYS_WCLOSE
bye:    lda     myport
        cmp     #$FFFF
        beq     :+
        sys     SYS_PCLOSE
:       jsr     stopws
        exit    0

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

; the arguments (bank 0): "-t", else a path or URL (quotes taken off) -> abuf
getargs:
        stz     tmode
        stz     abuf
        lda     argl
        jeq     @out
        ldx     argx
@sp:    lda     f:0,x
        and     #$00FF
        jeq     @out
        cmp     #' '
        bne     :+
        inx
        bra     @sp
:       cmp     #'-'
        bne     @path
        lda     f:1,x
        and     #$00DF
        cmp     #'T'
        bne     @path
        inc     tmode
        rts
@path:  ldy     #0                      ; the rest of the line
:       lda     f:0,x
        and     #$00FF
        beq     :+
        cpy     #PATHMAX - 1
        bcs     :+
        sep     #$20
        .a8
        sta     abuf,y
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       lda     #0
        sep     #$20
        .a8
        sta     abuf,y
        rep     #$20
        .a16
        ldx     #.loword(abuf)
        jsr     unquote
@out:   rts

; ---------------------------------------------------------------- keys
; the keys of the player (before the list's): C set when used
onkey:  lda     ui_ev+4
        cmp     #$0100                  ; presses only
        bcs     :+
        clc
        rts
:       and     #$0044                  ; (not with Alt)
        beq     :+
        clc
        rts
:       lda     ui_ev+4
        and     #$0011
        sta     kctrl
        lda     ui_ev+4
        and     #$0022
        sta     kshift
        lda     ui_ev+2
        ldx     kctrl
        beq     @plain
        cmp     #$12                    ; ctrl+O, L, Q, P, I
        jeq     k_open
        cmp     #$0F
        jeq     k_url
        cmp     #$14
        jeq     quit
        cmp     #$13
        jeq     k_vpl
        cmp     #$0C
        jeq     k_vsm
        cmp     #$50                    ; ctrl+Left / Right: the previous / next song
        jeq     k_prev
        cmp     #$4F
        jeq     k_next
        clc
        rts
@plain: cmp     #$2C                    ; Space
        jeq     k_toggle
        cmp     #$29                    ; Esc
        jeq     k_stop
        cmp     #$50                    ; Left / Right: seek
        jeq     k_back
        cmp     #$4F
        jeq     k_fwd
        cmp     #$4B                    ; PgUp / PgDn: the previous / next song
        jeq     k_prev
        cmp     #$4E
        jeq     k_next
        cmp     #$4C                    ; Delete
        jeq     k_del
        cmp     #$57                    ; keypad +, keypad -
        jeq     k_up
        cmp     #$56
        jeq     k_down
        cmp     #$2E                    ; = and +
        jeq     k_up
        cmp     #$2D                    ; - (not _)
        bne     :+
        ldx     kshift
        jeq     k_down
:       clc
        rts

k_open: jsr     a_open
        sec
        rts
k_url:  jsr     a_url
        sec
        rts
k_vpl:  lda     #0
        jsr     setview
        sec
        rts
k_vsm:  lda     #1
        jsr     setview
        sec
        rts
k_prev: jsr     a_prev
        sec
        rts
k_next: jsr     a_next
        sec
        rts
k_toggle:
        jsr     a_toggle
        sec
        rts
k_stop: jsr     a_stop
        sec
        rts
k_back: lda     #$FFFF
        jsr     a_seekby
        sec
        rts
k_fwd:  lda     #1
        jsr     a_seekby
        sec
        rts
k_del:  lda     view
        bne     :+
        jsr     a_remove
:       sec
        rts
k_up:   lda     #4
        jsr     a_volby
        sec
        rts
k_down: lda     #$FFFC
        jsr     a_volby
        sec
        rts

; Enter or a double click in a list: the playlist's song played
onopen: lda     view
        bne     @out
        lda     lst_pl+LS_SEL
        cmp     pl_n
        bcs     @out
        jsr     play_entry
@out:   rts

; ---------------------------------------------------------------- the mouse
; presses, motion and releases outside the lists: the buttons, the bars, the tabs
onmouse:
        lda     ui_ev+2
        sta     z:ex
        lda     ui_ev+4
        sta     z:ey
        lda     ui_ev
        and     #$00FF
        cmp     #WE_MOTION
        jeq     @motion
        lda     ui_ev+6                 ; a left press or release?
        and     #1
        jeq     @release
        lda     ui_ev+6                 ; (the right button alone: nothing)
        and     #6
        jne     loop
        jsr     hit_btn                 ; a button: pressed
        bcc     :+
        sta     btnp
        ldx     #1
        stx     btnin
        jsr     draw_btn
        jmp     loop
:       jsr     hit_vbar                ; the volume or stereo bar
        bcc     :+
        sta     drag
        jsr     dragbar
        jmp     loop
:       jsr     hit_pbar                ; the position bar: seek there
        bcc     :+
        jsr     a_seekx
        jmp     loop
:       jsr     hit_tab                 ; a tab
        bcc     :+
        jsr     setview
:       jmp     loop
@motion:
        lda     drag
        beq     :+
        jsr     dragbar
        jmp     loop
:       lda     btnp                    ; a button held: pressed while the pointer is on it
        cmp     #$FFFF
        jeq     loop
        jsr     hit_btn
        ldx     #0
        bcc     :+
        cmp     btnp
        bne     :+
        inx
:       cpx     btnin
        jeq     loop
        stx     btnin
        lda     btnp
        jsr     draw_btn
        jmp     loop
@release:
        lda     drag
        beq     :+
        stz     drag
        jmp     loop
:       lda     btnp
        cmp     #$FFFF
        jeq     loop
        sta     z:t5
        lda     #$FFFF
        sta     btnp
        jsr     hit_btn                 ; released on the button pressed: its action
        php
        pha
        lda     z:t5
        jsr     draw_btn
        pla
        plp
        jcc     loop
        cmp     z:t5
        jne     loop
        asl     a
        tax
        jsr     (btnact,x)
        jmp     loop

; the pointer (ex, ey) on a button? -> C set, A = the button
hit_btn:
        lda     z:ey
        cmp     #BTY
        bmi     @no
        cmp     #BTY + BTH
        bpl     @no
        lda     z:ex
        sec
        sbc     #M
        bmi     @no
        ldx     #0
:       cmp     #BTW
        bcc     @yes
        sbc     #BTW + BTG
        bcc     @no
        inx
        cpx     #NBTN
        bcc     :-
@no:    clc
        rts
@yes:   txa
        sec
        rts

; on the volume bar or the stereo bar (or their labels)? -> C set, A = DR_VOL / DR_SEP
hit_vbar:
        lda     z:ey
        cmp     #BTY
        bmi     @no
        cmp     #BTY + BTH
        bpl     @no
        lda     z:ex
        cmp     #VLX
        bmi     @no
        cmp     #SLX - 4
        bpl     :+
        lda     #DR_VOL
        sec
        rts
:       cmp     #WW - M
        bpl     @no
        lda     #DR_SEP
        sec
        rts
@no:    clc
        rts

; on the position bar? -> C set
hit_pbar:
        lda     z:ey
        cmp     #PBY - 2
        bmi     @no
        cmp     #PBY + PBH + 2
        bpl     @no
        lda     z:ex
        cmp     #PBX
        bmi     @no
        cmp     #PBX + PBW
        bpl     @no
        sec
        rts
@no:    clc
        rts

; on a tab? -> C set, A = 0 Playlist / 1 Samples
hit_tab:
        lda     z:ey
        cmp     #TABY
        bmi     @no
        cmp     #TABY + TABH
        bpl     @no
        lda     z:ex
        cmp     #M
        bmi     @no
        cmp     tabx1
        bpl     :+
        lda     #0
        sec
        rts
:       cmp     tabx2
        bpl     @no
        lda     #1
        sec
        rts
@no:    clc
        rts

; the pointer on a bar being dragged: its value 0-64 from x, sent, drawn
dragbar:
        lda     drag
        cmp     #DR_SEP
        beq     @sep
        lda     z:ex
        sec
        sbc     #VBX + 1
        ldx     #VBW - 2
        jsr     barval
        cmp     vol
        beq     @out
        sta     vol
        jsr     eng_vol
        jsr     draw_vol
        inc     dirty
@out:   rts
@sep:   lda     z:ex
        sec
        sbc     #SBX + 1
        ldx     #SBW - 2
        jsr     barval
        cmp     msep
        beq     @out
        sta     msep
        jsr     eng_sep
        jsr     draw_sep
        inc     dirty
        rts
; A = pixels into a bar of X pixels (signed) -> A = 0-64 (rounded)
barval: cmp     #$8000
        bcc     :+
        lda     #0
:       stx     z:t3
        cmp     z:t3
        bcc     :+
        txa
:       asl     a                       ; * 64 / width, rounded
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:t0
        txa
        lsr     a
        clc
        adc     z:t0
        ldx     z:t3
        jmp     udiv16

; a path dropped on the window: a folder added, a file added and played
ondrop: lda     win
        ptr     pbuf
        sys     SYS_WDROPGET
        bcs     :+
        jsr     open_path
:       jmp     loop

; ---------------------------------------------------------------- menus
onmenu: lda     ui_ev+4
        asl     a
        tax
        lda     ui_ev+2                 ; File 0, Play 1, View 2, Help 3
        bne     :+
        cpx     #2 * 8
        jcs     loop
        jsr     (mfile,x)
        jmp     loop
:       cmp     #1
        bne     :+
        cpx     #2 * 15
        jcs     loop
        jsr     (mplay,x)
        jmp     loop
:       cmp     #2
        bne     :+
        txa
        lsr     a
        cmp     #2
        jcs     loop
        jsr     setview
        jmp     loop
:       cmp     #3
        jne     loop
        cpx     #2 * 2
        jcs     loop
        jsr     (mhelp,x)
        jmp     loop
m_back: lda     #$FFFF
        jmp     a_seekby
m_fwd:  lda     #1
        jmp     a_seekby
m_quit: pla                             ; (from a menu's jsr)
        jmp     quit
m_none: rts

; the menu items' states: Shuffle, Repeat, View checked; Remove, Clear dimmed when empty
menustate:
        lda     #1 | (8 << 8)
        ldy     shuf
        jsr     @set
        lda     #1 | (9 << 8)
        ldy     #0
        ldx     mrep
        cpx     #RP_OFF
        bne     :+
        iny
:       jsr     @set
        lda     #1 | (10 << 8)
        ldy     #0
        ldx     mrep
        cpx     #RP_ALL
        bne     :+
        iny
:       jsr     @set
        lda     #1 | (11 << 8)
        ldy     #0
        ldx     mrep
        cpx     #RP_ONE
        bne     :+
        iny
:       jsr     @set
        lda     #2 | (0 << 8)
        ldy     #0
        ldx     view
        bne     :+
        iny
:       jsr     @set
        lda     #2 | (1 << 8)
        ldy     view
        jsr     @set
        ldy     #0                      ; Remove: a song selected in the playlist shown
        lda     view
        bne     :+
        lda     lst_pl+LS_SEL
        cmp     pl_n
        bcc     :++
:       ldy     #MS_DIM
:       lda     #0 | (4 << 8)
        jsr     @setr
        ldy     #0                      ; Clear: songs
        lda     pl_n
        bne     :+
        ldy     #MS_DIM
:       lda     #0 | (5 << 8)
        bra     @setr
@set:   cpy     #0                      ; Y = 1: checked
        beq     @setr
        ldy     #MS_CHECK
@setr:  tax
        lda     win
        sys     SYS_WMSTATE
        rts

; ---------------------------------------------------------------- actions
; Play: paused -> on; a song loaded and stopped -> from its start; else the song selected
; (none: the first; an empty playlist: File > Open...)
a_play: lda     phase
        cmp     #PH_READY
        bne     @sel
        lda     estate
        cmp     #MST_PAUSED
        bne     :+
        lda     #MC_PLAY
        ldx     #$FF
        jmp     eng_cmd
:       cmp     #MST_PLAYING
        bne     :+
        rts
:       lda     lst_pl+LS_SEL           ; (another song selected: that one)
        cmp     pl_n
        bcs     :+
        cmp     cur
        bne     @sel
:       lda     #MC_PLAY
        ldx     #0
        jmp     eng_cmd
@sel:   lda     pl_n
        bne     :+
        jmp     a_open
:       lda     lst_pl+LS_SEL
        cmp     pl_n
        bcc     :+
        lda     #0
:       jmp     play_entry

; Pause: playing -> paused; paused -> on
a_pause:
        lda     phase
        cmp     #PH_READY
        bne     @out
        lda     estate
        cmp     #MST_PLAYING
        bne     :+
        lda     #MC_PAUSE
        ldx     #0
        jmp     eng_cmd
:       cmp     #MST_PAUSED
        bne     @out
        lda     #MC_PLAY
        ldx     #$FF
        jmp     eng_cmd
@out:   rts

; Space: Pause while playing, else Play
a_toggle:
        lda     phase
        cmp     #PH_READY
        bne     :+
        lda     estate
        cmp     #MST_PLAYING
        beq     a_pause
:       jmp     a_play

a_stop: lda     phase
        cmp     #PH_READY
        bne     :+
        lda     #MC_STOP
        ldx     #0
        jmp     eng_cmd
:       rts

a_prev: lda     pl_n
        beq     @out
        lda     shuf
        bne     a_next
        lda     cur
        cmp     pl_n
        bcc     :+
        lda     lst_pl+LS_SEL
        cmp     pl_n
        bcs     @last
        bra     @go
:       dec     a
        bpl     @go
@last:  lda     pl_n
        dec     a
@go:    jmp     play_entry
@out:   rts

a_next: lda     pl_n
        beq     @out
        jsr     pick_next               ; (a manual Next goes round at the end)
        bcs     :+
        lda     #0
:       jmp     play_entry
@out:   rts

; Left / Right: A = -1 / +1: a MOD one order back or on, a WAV about 5 seconds
a_seekby:
        sta     z:t5
        lda     phase
        cmp     #PH_READY
        bne     @out
        lda     info+MI_KIND
        and     #$00FF
        cmp     #2
        beq     @wav
        lda     st+2                    ; the order now
        and     #$00FF
        clc
        adc     z:t5
        bmi     @zero
        sta     z:t0
        lda     info+MI_SLEN
        and     #$00FF
        beq     @out
        dec     a
        cmp     z:t0
        bcc     @out                    ; (past the end: nothing)
        lda     z:t0
        bra     @go
@zero:  lda     #0
@go:    tax
        lda     #MC_SEEK
        jmp     eng_cmd
@wav:   lda     info+MI_TENTHS          ; 5 s in 256ths: 50 * 256 / tenths (at least 1)
        beq     @out
        sta     z:t3
        lda     #12800
        ldx     z:t3
        jsr     udiv16
        cmp     #0
        bne     :+
        lda     #1
:       ldx     z:t5
        bpl     :+
        eor     #$FFFF
        inc     a
:       sta     z:t0
        lda     st+2
        and     #$00FF
        clc
        adc     z:t0
        bpl     :+
        lda     #0
:       cmp     #256
        bcc     @go
        lda     #255
        bra     @go
@out:   rts

; a click on the position bar at ex: a MOD to the order there, a WAV to the 256th there
a_seekx:
        lda     phase
        cmp     #PH_READY
        bne     @out
        lda     z:ex
        sec
        sbc     #PBX + 1
        bpl     :+
        lda     #0
:       cmp     #PBW - 2
        bcc     :+
        lda     #PBW - 3
:       sta     z:t5
        lda     info+MI_KIND
        and     #$00FF
        cmp     #2
        beq     @wav
        lda     info+MI_SLEN            ; order = x * length / width
        and     #$00FF
        beq     @out
        ldx     z:t5
        jsr     umul32
        ldx     #PBW - 2
        jsr     udiv32
        tax
        lda     #MC_SEEK
        jmp     eng_cmd
@wav:   lda     z:t5                    ; 256ths = x * 256 / width
        xba
        and     #$FF00
        sta     z:t0
        lda     z:t5
        xba
        and     #$00FF
        sta     z:t1
        ldx     #PBW - 2
        jsr     udiv32
        tax
        lda     #MC_SEEK
        jmp     eng_cmd
@out:   rts

; + / -: the volume by A (4 steps)
a_volby:
        clc
        adc     vol
        bpl     :+
        lda     #0
:       cmp     #65
        bcc     :+
        lda     #64
:       cmp     vol
        beq     :+
        sta     vol
        inc     dirty
        jsr     eng_vol
        jsr     draw_vol
:       rts
m_louder:
        lda     #4
        bra     a_volby
m_softer:
        lda     #$FFFC
        bra     a_volby

; File > Open...: a MOD or WAV file from the file dialog, added and played
a_open: stz     pbuf
        lda     #0
        ldx     #.loword(pbuf)
        ldy     #.loword(t_open)
        jsr     ui_filedlg
        bcs     :+
        jmp     open_path
:       rts

; File > Open folder...: every MOD and WAV file of a folder added (the current folder, the
; file dialog's last one, offered)
a_folder:
        lda     #PATHMAX
        ldx     #.loword(fbuf)
        ldy     pbank
        sys     SYS_GETCWD
        bcc     :+
        lda     #'/'
        sta     fbuf                    ; ('/', 0)
:       ldx     #.loword(ak_fold)
        jsr     ui_ask
        bcs     @out
        ldx     #.loword(fbuf)
        ldy     #.loword(pbuf)
        jsr     ui_strcpy
        jsr     abspath
        jsr     isdir
        bcs     :+
        ldx     #.loword(m_notdir)
        jmp     alertp
:       jmp     add_folder_play
@out:   rts

; File > Open location...: a URL (http://, https://, ftp://), added and played
a_url:  ldx     #.loword(ak_url)
        jsr     ui_ask
        bcs     @out
        ldx     #.loword(ubuf)
        jsr     ui_isurl
        bcs     :+
        ldx     #.loword(al_nourl)
        jsr     ui_alert
        bra     a_url
:       ldx     #.loword(ubuf)
        ldy     #.loword(pbuf)
        jsr     ui_strcpy
        jmp     open_path
@out:   rts

; File > Remove from playlist (Delete): the selected song
a_remove:
        lda     lst_pl+LS_SEL
        cmp     pl_n
        bcs     @out
        jsr     pl_remove
        inc     dirty
        lda     lst_pl+LS_SEL           ; the selection stays at its row (the last one: up)
        cmp     pl_n
        bcc     :+
        lda     pl_n
        dec     a                       ; (none left: $FFFF)
:       sta     lst_pl+LS_SEL
        lda     pl_n
        sta     lst_pl+LS_COUNT
        jsr     plchanged
@out:   rts

; File > Clear playlist (asks first)
a_clear:
        lda     pl_n
        beq     @out
        ldx     #.loword(al_clear)
        jsr     ui_alert
        cmp     #0
        bne     @out
        jsr     pl_init
        lda     #$FFFF
        sta     cur
        sta     lst_pl+LS_SEL
        stz     lst_pl+LS_COUNT
        stz     lst_pl+LS_TOP
        inc     dirty
        jsr     plchanged
@out:   rts

; the playlist changed: drawn (when shown), the tab's count, the status line, the menus
plchanged:
        lda     view
        bne     :+
        ldx     #.loword(lst_pl)
        jsr     ui_draw
:       jsr     draw_tabs
        jsr     draw_status
        jsr     draw_btns
        jsr     idletext
        jmp     menustate

; Play > Shuffle; Repeat off / all / one
m_shuffle:
        lda     shuf
        eor     #1
        sta     shuf
        bra     modes
m_roff: lda     #RP_OFF
        bra     :+
m_rall: lda     #RP_ALL
        bra     :+
m_rone: lda     #RP_ONE
:       sta     mrep
        jsr     eng_loop
modes:  inc     dirty
        jsr     menustate
        jmp     draw_status

; View > Playlist (0) / Samples (1)
setview:
        cmp     view
        beq     @out
        sta     view
        jsr     menustate
        jsr     draw_tabs
        jsr     ctls                    ; the list of the view gets the focus and is drawn
        ldx     #.loword(lst_pl)
        lda     view
        beq     :+
        ldx     #.loword(lst_sm)
:       jmp     ui_draw
@out:   rts

; Help > Keys...
m_keys: ldx     #.loword(dg_keys)
        jsr     ui_dlgopen
        bcs     :+
        ldx     #.loword(dg_keys)
        jsr     ui_dlgrun
        ldx     #.loword(dg_keys)
        jmp     ui_dlgclose
:       rts
m_about:
        ldx     #.loword(al_about)
        jmp     ui_alert

; an alert about the path in pbuf: X = the message ("%" = the path)
alertp: ldy     #.loword(albuf)
@c:     lda     a:0,x
        and     #$00FF
        cmp     #'%'
        bne     :+
        phx
        sty     z:t0
        ldx     #.loword(pbuf)
        jsr     ui_strcpy
        clc
        adc     z:t0
        tay
        plx
        inx
        bra     @c
:       sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        inx
        iny
        cmp     #0
        bne     @c
        ldx     #.loword(al_path)
        jmp     ui_alert

        .include "mu_eng.s"
        .include "mu_draw.s"
        .include "mu_list.s"
        .include "mu_test.s"
        .include "mu_data.s"

; mu_list.s - Music: the playlist (its paths in a bank of their own: MAXPL slots of 128 bytes;
; pl_idx gives the slot of each row), opening paths and folders, names, the settings file
; /SYSTEM/MUSIC.CFG, the requests of ui_launch (/SYSTEM/OPEN.REQ), the error texts, and small
; helpers (strings, numbers). Included by music.s.
;
; /SYSTEM/MUSIC.CFG is text, one item a line (written at the end and when the window loses
; the focus, if something changed; a missing or damaged file is fine):
;   # comment
;   volume=64           the music volume 0-64
;   separation=32       the stereo separation 0-64
;   repeat=all          off, all or one
;   shuffle=off         on or off
;   current=2           the song selected (1 = the first; 0: none)
;   /Music/HORIZON.MOD  the playlist: every line that starts with '/' or holds "://"
;
; Requests: when a program asks for Music with a file while Music runs, the kernel refuses
; the second start (ERUNNING) and raises this window; the controls library's ui_launch then
; writes /SYSTEM/OPEN.REQ: two lines, the program's path and its argument string. Music
; looks for it when its window gets the focus and once a second: when the first line is
; its own path, the file is deleted and the argument opened (added to the playlist, played).

        .segment "CODE"

; ---------------------------------------------------------------- the playlist
; empty: every slot free
pl_init:
        stz     pl_n
        lda     plbank
        sta     z:p0+2
        stz     z:p0
        ldx     #MAXPL
:       lda     #0
        sep     #$20
        .a8
        sta     [p0]
        rep     #$20
        .a16
        lda     z:p0
        clc
        adc     #PATHMAX
        sta     z:p0
        dex
        bne     :-
        rts

; A = a slot -> p0 = its address
pl_slot:
        xba                             ; * 128
        lsr     a
        sta     z:p0
        lda     plbank
        sta     z:p0+2
        rts

; A = a row -> pbuf = its path
pl_get: asl     a
        tax
        lda     pl_idx,x
        jsr     pl_slot
        ldy     #0
:       lda     [p0],y
        sep     #$20
        .a8
        sta     pbuf,y
        rep     #$20
        .a16
        and     #$00FF
        beq     :+
        iny
        cpy     #PATHMAX - 1
        bcc     :-
        lda     #0
        sep     #$20
        .a8
        sta     pbuf,y
        rep     #$20
        .a16
:       rts

; pbuf added at the end (when the same path is there already: that row) -> C clear, A = its
; row; C set: the playlist is full
pl_add: ldx     #0                      ; there already? (ignoring case)
@s:     stx     z:t5
        txa
        cmp     pl_n
        bcs     @new
        asl     a
        tax
        lda     pl_idx,x
        jsr     pl_slot
        ldy     #0
:       lda     [p0],y
        jsr     upper
        sta     z:t0
        lda     pbuf,y
        jsr     upper
        cmp     z:t0
        bne     :+
        iny
        cmp     #0
        bne     :-
        lda     z:t5
        clc
        rts
:       ldx     z:t5
        inx
        bra     @s
@new:   lda     pl_n
        cmp     #MAXPL
        bcs     @full
        lda     #0                      ; a free slot
@f:     sta     z:t5
        jsr     pl_slot
        lda     [p0]
        and     #$00FF
        beq     @put
        lda     z:t5
        inc     a
        bra     @f
@put:   ldy     #0
:       lda     pbuf,y
        sep     #$20
        .a8
        sta     [p0],y
        rep     #$20
        .a16
        and     #$00FF
        beq     :+
        iny
        cpy     #PATHMAX - 1
        bcc     :-
        lda     #0
        sep     #$20
        .a8
        sta     [p0],y
        rep     #$20
        .a16
:       lda     pl_n
        asl     a
        tax
        lda     z:t5
        sta     pl_idx,x
        lda     pl_n
        inc     pl_n
        clc
        rts
@full:  sec
        rts

; A = a row: taken out (its slot freed); cur follows
pl_remove:
        sta     z:t5
        asl     a
        tax
        lda     pl_idx,x
        jsr     pl_slot
        lda     #0
        sep     #$20
        .a8
        sta     [p0]
        rep     #$20
        .a16
:       lda     pl_idx+2,x              ; the rows after it move up
        sta     pl_idx,x
        inx
        inx
        txa
        lsr     a
        cmp     pl_n
        bcc     :-
        dec     pl_n
        lda     cur                     ; the song loaded: its row (none if it was this one)
        cmp     #$FFFF
        beq     @out
        cmp     z:t5
        bcc     @out
        bne     :+
        lda     #$FFFF
        sta     cur
        rts
:       dec     cur
@out:   rts

; the rows from A to the end sorted by their paths (ignoring case): insertion
pl_sort:
        sta     z:g0                    ; the first row of the range
        inc     a
        sta     z:g1                    ; i
@i:     lda     z:g1
        cmp     pl_n
        bcs     @out
        asl     a
        tax
        lda     pl_idx,x
        sta     z:g2                    ; the slot moved
        lda     z:g1
        sta     z:g3                    ; j
@j:     lda     z:g3
        cmp     z:g0
        beq     @put
        dec     a
        asl     a
        tax
        lda     pl_idx,x                ; row j - 1 after the moved one? it moves down
        jsr     pl_slot
        lda     z:p0
        sta     z:p1
        lda     z:p0+2
        sta     z:p1+2
        lda     z:g2
        jsr     pl_slot
        jsr     lcmp                    ; C set: p1's path after p0's
        bcc     @put
        lda     z:g3
        asl     a
        tax
        lda     pl_idx-2,x
        sta     pl_idx,x
        dec     z:g3
        bra     @j
@put:   lda     z:g3
        asl     a
        tax
        lda     z:g2
        sta     pl_idx,x
        inc     z:g1
        bra     @i
@out:   rts

; [p1] after [p0] (ignoring case)? -> C set
lcmp:   ldy     #0
:       lda     [p0],y
        jsr     upper
        sta     z:t0
        lda     [p1],y
        jsr     upper
        cmp     z:t0
        bne     :+
        iny
        cmp     #0
        bne     :-
        clc
:       rts                             ; (C from the compare: set when p1's is after)

; A (a byte, high byte ignored) -> upper case
upper:  and     #$00FF
        cmp     #'a'
        bcc     :+
        cmp     #'z' + 1
        bcs     :+
        and     #$00DF
:       rts

; ---------------------------------------------------------------- opening
; the argument (abuf): opened
open_arg:
        ldx     #.loword(abuf)
        ldy     #.loword(pbuf)
        jsr     ui_strcpy
; pbuf (a path, relative or absolute, or a URL): a folder's songs added, a file added and
; played
open_path:
        ldx     #.loword(pbuf)
        jsr     unquote
        lda     pbuf
        and     #$00FF
        beq     @out
        jsr     abspath
        jsr     isdir
        bcc     :+
        jmp     add_folder_play
:       jsr     pl_add
        bcc     :+
        ldx     #.loword(al_full)
        jmp     ui_alert
:       pha
        inc     dirty
        lda     pl_n
        sta     lst_pl+LS_COUNT
        pla
        jsr     play_entry
        jmp     plchanged
@out:   rts

; the folder in pbuf: its MOD and WAV files added (sorted by name); the first one played when
; nothing plays. None: an alert
add_folder_play:
        ldx     #.loword(pbuf)
        ldy     #.loword(fbuf)
        jsr     ui_strcpy
        lda     pl_n
        sta     z:g4                    ; (the first new row)
        jsr     add_folder
        bcc     :+
        ldx     #.loword(al_full)       ; full (what fitted stays)
        jsr     ui_alert
:       lda     pl_n
        cmp     z:g4
        bne     :+
        ldx     #.loword(fbuf)
        ldy     #.loword(pbuf)
        jsr     ui_strcpy
        ldx     #.loword(m_nosongs)
        jmp     alertp
:       inc     dirty
        lda     pl_n
        sta     lst_pl+LS_COUNT
        lda     phase
        cmp     #PH_READY
        bne     @play
        lda     estate
        cmp     #MST_PLAYING
        beq     :+
        cmp     #MST_PAUSED
        beq     :+
@play:  lda     z:g4
        jsr     play_entry
:       jmp     plchanged

; the folder fbuf: its .MOD and .WAV files (also names "MOD.xxx") added, sorted -> C set:
; the playlist got full
add_folder:
        lda     pl_n
        pha
        stz     z:g5                    ; skip
@call:  lda     #.loword(fbuf)          ; {u24 path, u24 buffer, u16 length, u16 skip}
        sta     rdb
        lda     #.loword(dbuf)
        sta     rdb+3
        sep     #$20
        .a8
        lda     pbank
        sta     rdb+2
        sta     rdb+5
        rep     #$20
        .a16
        lda     #DBUFL
        sta     rdb+6
        lda     z:g5
        sta     rdb+8
        ptr     rdb
        sys     SYS_READDIR
        jcs     @done
        cmp     #0
        jeq     @done
        sta     z:g6                    ; entries in this batch
        clc
        adc     z:g5
        sta     z:g5
        ldx     #0
@ent:   stx     z:g7                    ; {u32 size, u8 attr, u8 length, name}
        lda     dbuf+4,x
        and     #$0010
        bne     @next
        lda     dbuf+5,x
        and     #$00FF
        beq     @next
        cmp     #UI_NAMEMAX
        bcs     @next
        sta     z:t5
        jsr     songname                ; a song's name? -> pbuf = fbuf/name
        bcc     @next
        jsr     pl_add
        bcs     @full
@next:  ldx     z:g7
        lda     dbuf+5,x
        and     #$00FF
        clc
        adc     #6
        adc     z:g7
        tax
        dec     z:g6
        bne     @ent
        jmp     @call
@done:  pla
        jsr     pl_sort
        clc
        rts
@full:  pla
        jsr     pl_sort
        sec
        rts

; the entry at dbuf + g7 (its name t5 long): .MOD, .WAV or MOD.* -> C set and pbuf =
; fbuf + "/" + the name
songname:
        lda     z:g7
        clc
        adc     #.loword(dbuf + 6)
        sta     z:t6                    ; the name
        tax
        lda     a:0,x                   ; "MOD."
        jsr     upper
        cmp     #'M'
        bne     :+
        lda     a:1,x
        jsr     upper
        cmp     #'O'
        bne     :+
        lda     a:2,x
        jsr     upper
        cmp     #'D'
        bne     :+
        lda     a:3,x
        and     #$00FF
        cmp     #'.'
        beq     @yes
:       lda     z:t5                    ; ".MOD", ".WAV"
        cmp     #5
        jcc     @no
        lda     z:t6
        clc
        adc     z:t5
        sec
        sbc     #4
        tax
        lda     a:0,x
        and     #$00FF
        cmp     #'.'
        jne     @no
        lda     a:1,x
        jsr     upper
        sta     z:t0
        lda     a:2,x
        jsr     upper
        xba
        ora     z:t0
        sta     z:t0
        lda     a:3,x
        jsr     upper
        sta     z:t1
        lda     z:t0
        cmp     #'M' | ('O' << 8)
        bne     :+
        lda     z:t1
        cmp     #'D'
        beq     @yes
:       lda     z:t0
        cmp     #'M' | ('I' << 8)
        bne     :+
        lda     z:t1
        cmp     #'D'
        beq     @yes
:       lda     z:t0
        cmp     #'W' | ('A' << 8)
        bne     @no
        lda     z:t1
        cmp     #'V'
        bne     @no
@yes:   ldx     #.loword(fbuf)          ; the path: folder, "/", name
        ldy     #.loword(pbuf)
        jsr     ui_strcpy
        tay
        cpy     #2                      ; ("/": no second one)
        bcc     :+
        lda     #'/'
        sta     pbuf,y                  ; ('/', 0)
        iny
:       ldx     z:t6
        lda     z:t5
        sta     z:t0
:       cpy     #PATHMAX - 1
        bcs     @no
        lda     a:0,x
        sep     #$20
        .a8
        sta     pbuf,y
        rep     #$20
        .a16
        inx
        iny
        dec     z:t0
        bne     :-
        lda     #0
        sep     #$20
        .a8
        sta     pbuf,y
        rep     #$20
        .a16
        sec
        rts
@no:    clc
        rts

; X = a string: the quotes around it (and blanks at its ends) taken off
unquote:
        stx     z:t0
:       lda     a:0,x                   ; the blanks at its start
        and     #$00FF
        cmp     #' '
        bne     :+
        inx
        bra     :-
:       cmp     #'"'
        bne     :+
        inx
:       ldy     z:t0                    ; moved to the start
:       lda     a:0,x
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        and     #$00FF
        beq     :+
        inx
        iny
        bra     :-
:       cpy     z:t0                    ; the end: blanks and a quote off
        beq     @out
        dey
        lda     a:0,y
        and     #$00FF
        cmp     #' '
        beq     :+
        cmp     #'"'
        bne     @out
:       lda     #0
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        bra     :--
@out:   rts

; pbuf made absolute (a relative path: the current folder in front; URLs as they are)
abspath:
        lda     pbuf
        and     #$00FF
        cmp     #'/'
        beq     @out
        ldx     #.loword(pbuf)
        jsr     ui_isurl
        bcs     @out
        lda     #PATHMAX
        ldx     #.loword(tbuf)
        ldy     pbank
        sys     SYS_GETCWD
        bcs     @out
        tay
        cpy     #2
        bcc     :+
        lda     #'/'
        sta     tbuf,y                  ; ('/', 0)
        iny
:       ldx     #.loword(pbuf)
:       cpy     #PATHMAX - 1
        bcs     :+
        lda     a:0,x
        sep     #$20
        .a8
        sta     tbuf,y
        rep     #$20
        .a16
        and     #$00FF
        beq     :++
        inx
        iny
        bra     :-
:       lda     #0
        sep     #$20
        .a8
        sta     tbuf,y
        rep     #$20
        .a16
:       ldx     #.loword(tbuf)
        ldy     #.loword(pbuf)
        jsr     ui_strcpy
@out:   rts

; pbuf a folder? -> C set (a URL: never; asking would fetch it)
isdir:  ldx     #.loword(pbuf)
        jsr     ui_isurl
        bcs     @no
        lda     #.loword(pbuf)          ; {u24 path, u24 out}
        sta     sblk
        lda     #.loword(stb)
        sta     sblk+3
        sep     #$20
        .a8
        lda     pbank
        sta     sblk+2
        sta     sblk+5
        rep     #$20
        .a16
        ptr     sblk
        sys     SYS_STAT
        bcs     @no
        lda     stb+4
        and     #$0010
        beq     @no
        sec
        rts
@no:    clc
        rts

; pbuf (a path or URL) -> nbuf: the name shown: the last part (a URL's without its query; a
; URL without a path: its host)
namepb: ldx     #.loword(pbuf)
        stz     z:t1                    ; a URL?
        jsr     ui_isurl
        bcc     :+
        txa                             ; (the index after "://")
        sec
        sbc     #.loword(pbuf)
        sta     z:t1
:       ldx     #0                      ; the end: the string's, or a URL's '?' or '#'
:       lda     pbuf,x
        and     #$00FF
        beq     :++
        ldy     z:t1
        beq     :+
        cmp     #'?'
        beq     :++
        cmp     #'#'
        beq     :++
:       inx
        bra     :--
:       stx     z:t2                    ; the end
        txy                             ; the start: after the last '/' before the end
@back:  cpy     #0
        beq     @got
        lda     pbuf-1,y
        and     #$00FF
        cmp     #'/'
        beq     @got
        dey
        bra     @back
@got:   cpy     z:t2
        bne     @copy
        lda     z:t1                    ; nothing after it: a URL's host
        beq     @copy
        tay
        ldx     z:t1
:       lda     pbuf,x
        and     #$00FF
        beq     :+
        cmp     #'/'
        beq     :+
        inx
        bra     :-
:       stx     z:t2
@copy:  ldx     #0
:       cpy     z:t2
        bcs     :+
        lda     pbuf,y
        sep     #$20
        .a8
        sta     nbuf,x
        rep     #$20
        .a16
        inx
        iny
        cpx     #PATHMAX - 1
        bcc     :-
:       lda     #0
        sep     #$20
        .a8
        sta     nbuf,x
        rep     #$20
        .a16
        rts

; X = a buffer, Y = its length: bytes that are not printable become blanks, a 0 at Y, the
; blanks at the end taken off
clean:  stx     z:t0
        sty     z:t1
        ldy     #0
:       cpy     z:t1
        bcs     :++
        lda     (t0),y
        and     #$00FF
        cmp     #' '
        bcc     :+
        cmp     #127
        bcc     @ok
:       lda     #' '
@ok:    sep     #$20
        .a8
        sta     (t0),y
        rep     #$20
        .a16
        iny
        bra     :--
:       lda     #0
:       sep     #$20
        .a8
        sta     (t0),y
        rep     #$20
        .a16
        cpy     #0
        beq     :+
        dey
        lda     (t0),y
        and     #$00FF
        cmp     #' '
        bne     :+
        lda     #0
        bra     :-
:       rts

; ---------------------------------------------------------------- the settings file
cfg_maybe:
        lda     dirty
        beq     :+
        stz     dirty
        jmp     cfg_save
:       rts

; /SYSTEM/MUSIC.CFG read (missing: the defaults stay)
cfg_load:
        stz     lnl
        lda     #O_READ
        ptr     p_cfg
        sys     SYS_OPEN
        bcs     @out
        sta     cfh
@rd:    lda     cfh                     ; pieces of IOBL bytes
        sep     #$20
        .a8
        sta     rwb
        rep     #$20
        .a16
        lda     #.loword(iobuf)
        sta     rwb+1
        lda     pbank
        sep     #$20
        .a8
        sta     rwb+3
        rep     #$20
        .a16
        lda     #IOBL
        sta     rwb+4
        ptr     rwb
        sys     SYS_READ
        bcs     @end
        cmp     #0
        beq     @end
        sta     z:g6
        ldx     #0
:       stx     z:g7
        lda     iobuf,x
        and     #$00FF
        jsr     cfg_ch
        ldx     z:g7
        inx
        cpx     z:g6
        bcc     :-
        lda     z:g6
        cmp     #IOBL
        beq     @rd
@end:   lda     #10                     ; (a last line without its end)
        jsr     cfg_ch
        lda     cfh
        sys     SYS_CLOSE
@out:   rts

; a character of the settings text: lines collected in lbuf, each one taken at its end
cfg_ch: cmp     #13
        beq     @out
        cmp     #10
        beq     @line
        ldx     lnl
        cpx     #PATHMAX - 1
        bcs     @out
        sep     #$20
        .a8
        sta     lbuf,x
        rep     #$20
        .a16
        inc     lnl
@out:   rts
@line:  ldx     lnl
        stz     lnl
        sep     #$20
        .a8
        stz     lbuf,x
        rep     #$20
        .a16
        ldx     #.loword(lbuf)
        jsr     unquote
        lda     lbuf
        and     #$00FF
        beq     @out
        cmp     #'#'
        beq     @out
        cmp     #'/'
        beq     @song
        ldx     #.loword(lbuf)
        jsr     ui_isurl
        bcs     @song
        ldx     #0                      ; key=value
@k:     stx     z:t5
        lda     cfgkeys,x
        beq     @out
        tay
        ldx     #.loword(lbuf)
        jsr     prefix                  ; -> C clear: X = the value
        bcc     @val
        lda     z:t5
        clc
        adc     #4
        tax
        bra     @k
@val:   ldy     z:t5
        lda     cfgkeys+2,y
        sta     z:t6
        jmp     (t6)
@song:  ldx     #.loword(lbuf)
        ldy     #.loword(pbuf)
        jsr     ui_strcpy
        jsr     pl_add
        rts

; the string Y a prefix of X (ignoring case)? C clear: yes, X after it
prefix: lda     a:0,y
        and     #$00FF
        bne     :+
        clc
        rts
:       sta     z:t0
        lda     a:0,x
        jsr     upper
        cmp     z:t0
        bne     :+
        inx
        iny
        bra     prefix
:       sec
        rts

; the values: X = the text after '='
cv_vol: jsr     cnum
        bcs     :+
        cmp     #65
        bcs     :+
        sta     vol
:       rts
cv_sep: jsr     cnum
        bcs     :+
        cmp     #65
        bcs     :+
        sta     msep
:       rts
cv_cur: jsr     cnum
        bcs     :+
        dec     a                       ; (1 = the first; 0: none -> $FFFF)
        sta     cur
:       rts
cv_rep: ldy     #.loword(s_off)
        phx
        jsr     prefix
        plx
        bcs     :+
        lda     #RP_OFF
        sta     mrep
        rts
:       ldy     #.loword(s_all)
        phx
        jsr     prefix
        plx
        bcs     :+
        lda     #RP_ALL
        sta     mrep
        rts
:       ldy     #.loword(s_one)
        jsr     prefix
        bcs     :+
        lda     #RP_ONE
        sta     mrep
:       rts
cv_shuf:
        ldy     #.loword(s_on)
        jsr     prefix
        lda     #0
        bcs     :+
        inc     a
:       sta     shuf
        rts
; X = decimal digits -> A (C set: none, or too large)
cnum:   stz     z:t0
        ldy     #0
:       lda     a:0,x
        and     #$00FF
        sec
        sbc     #'0'
        cmp     #10
        bcs     :+
        sta     z:t1
        lda     z:t0
        cmp     #6000
        bcs     @bad
        asl     a
        asl     a
        adc     z:t0
        asl     a
        adc     z:t1
        sta     z:t0
        inx
        iny
        bra     :-
:       cpy     #0
        beq     @bad
        lda     z:t0
        clc
        rts
@bad:   sec
        rts

; /SYSTEM/MUSIC.CFG written (not writable: nothing said)
cfg_save:
        lda     #O_CREATE
        ptr     p_cfg
        sys     SYS_OPEN
        bcs     @out
        sta     cfh
        stz     wsink
        jsr     cfg_text
        jsr     wr_flush
        lda     cfh
        sys     SYS_CLOSE
@out:   rts

; the settings' text through wr_*: the settings, then the playlist
cfg_text:
        stz     wrn
        ldx     #.loword(s_cfghead)
        jsr     wr_s
        ldx     #.loword(s_kvol)
        jsr     wr_s
        lda     vol
        jsr     wr_n
        ldx     #.loword(s_ksep)
        jsr     wr_s
        lda     msep
        jsr     wr_n
        ldx     #.loword(s_krep)
        jsr     wr_s
        lda     mrep
        asl     a
        tax
        lda     repkw,x
        tax
        jsr     wr_s
        lda     #10
        jsr     wr_c
        ldx     #.loword(s_kshuf)
        jsr     wr_s
        ldx     #.loword(w_off)
        lda     shuf
        beq     :+
        ldx     #.loword(w_on)
:       jsr     wr_s
        lda     #10
        jsr     wr_c
        ldx     #.loword(s_kcur)
        jsr     wr_s
        lda     lst_pl+LS_SEL           ; the song selected
        cmp     pl_n
        bcc     :+
        lda     #$FFFF
:       inc     a
        jsr     wr_n
        stz     z:g6
:       lda     z:g6                    ; the songs
        cmp     pl_n
        bcs     :+
        jsr     pl_get
        ldx     #.loword(pbuf)
        jsr     wr_s
        lda     #10
        jsr     wr_c
        inc     z:g6
        bra     :-
:       rts

; the writer: to the file cfh through iobuf, or (wsink) to the console
wr_n:   jsr     dec16p                  ; a number and a line end
        ldx     #.loword(numbuf)
        jsr     wr_s
        lda     #10
        bra     wr_c
wr_s:   lda     a:0,x                   ; a string
        and     #$00FF
        beq     :+
        phx
        jsr     wr_c
        plx
        inx
        bra     wr_s
:       rts
wr_c:   ldx     wsink
        beq     :+
        jmp     out_char
:       ldx     wrn
        sep     #$20
        .a8
        sta     iobuf,x
        rep     #$20
        .a16
        inx
        stx     wrn
        cpx     #IOBL
        bcc     :+
        jmp     wr_flush
:       rts
wr_flush:
        lda     wsink
        bne     @out
        lda     wrn
        beq     @out
        sta     rwb+4
        lda     cfh
        sep     #$20
        .a8
        sta     rwb
        rep     #$20
        .a16
        lda     #.loword(iobuf)
        sta     rwb+1
        lda     pbank
        sep     #$20
        .a8
        sta     rwb+3
        rep     #$20
        .a16
        ptr     rwb
        sys     SYS_WRITE
        stz     wrn
@out:   rts

; ---------------------------------------------------------------- requests
; an old request for Music deleted
req_clear:
        jsr     req_read
        bcs     :+
        ptr     p_req
        sys     SYS_DELETE
:       rts

; a request for Music: deleted, its argument opened
req_check:
        jsr     req_read
        bcs     @out
        ptr     p_req
        sys     SYS_DELETE
        lda     abuf
        and     #$00FF
        beq     @out
        jmp     open_arg
@out:   rts

; /SYSTEM/OPEN.REQ read: C clear when its first line is Music's path (abuf = the second
; line); C set: none, or another program's
req_read:
        lda     #O_READ
        ptr     p_req
        sys     SYS_OPEN
        jcs     @no
        sta     cfh
        sep     #$20
        .a8
        sta     rwb
        rep     #$20
        .a16
        lda     #.loword(iobuf)
        sta     rwb+1
        lda     pbank
        sep     #$20
        .a8
        sta     rwb+3
        rep     #$20
        .a16
        lda     #IOBL - 1
        sta     rwb+4
        ptr     rwb
        sys     SYS_READ
        php
        pha
        lda     cfh
        sys     SYS_CLOSE
        pla
        plp
        bcs     @no
        tax
        sep     #$20
        .a8
        stz     iobuf,x
        rep     #$20
        .a16
        ldx     #.loword(iobuf)         ; the first line: ours?
        ldy     #.loword(p_self)
        jsr     prefix
        bcs     @no
        lda     a:0,x
        and     #$00FF
        cmp     #13
        beq     :+
        cmp     #10
        bne     @no
:       lda     a:0,x                   ; the second line -> abuf
        and     #$00FF
        cmp     #13
        beq     :+
        cmp     #10
        bne     :++
:       inx
        bra     :--
:       ldy     #0
:       lda     a:0,x
        and     #$00FF
        cmp     #' '
        bcc     :+
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
        clc
        rts
@no:    sec
        rts

; ---------------------------------------------------------------- error texts
; A = an error code (a load's) -> X = its text
errtext:
        sta     z:t0
        ldx     #0
:       lda     errtab,x
        beq     @other
        cmp     z:t0
        beq     :+
        inx
        inx
        inx
        inx
        bra     :-
:       lda     errtab+2,x
        tax
        rts
@other: lda     z:t0                    ; "Error $XX."
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        and     #$000F
        tax
        lda     hexd,x
        sep     #$20
        .a8
        sta     m_errn_h
        rep     #$20
        .a16
        lda     z:t0
        and     #$000F
        tax
        lda     hexd,x
        sep     #$20
        .a8
        sta     m_errn_h+1
        rep     #$20
        .a16
        ldx     #.loword(m_errn)
        rts

; ---------------------------------------------------------------- strings and numbers
; append to sbuf (sl its length): the string X, the number A, the character A, the time A
; in tenths ("m:ss")
sapp:   ldy     sl
:       lda     a:0,x
        and     #$00FF
        sep     #$20
        .a8
        sta     sbuf,y
        rep     #$20
        .a16
        beq     :+
        inx
        iny
        cpy     #SBUFL - 1
        bcc     :-
        lda     #0
        sep     #$20
        .a8
        sta     sbuf,y
        rep     #$20
        .a16
:       sty     sl
        rts
sappn:  jsr     dec16p
        ldx     #.loword(numbuf)
        bra     sapp
sapc:   and     #$00FF
        ldy     sl
        cpy     #SBUFL - 1
        bcs     :+
        sta     sbuf,y                  ; (the character and a 0)
        iny
        sty     sl
:       rts
sappt10:
        ldx     #10                     ; tenths -> seconds
        jsr     udiv16
        pha
        ldx     #60
        jsr     udiv16
        jsr     sappn
        lda     #':'
        jsr     sapc
        pla
        ldx     #60
        jsr     udiv16
        lda     z:t2                    ; the seconds: two digits
        cmp     #10
        bcs     :+
        pha
        lda     #'0'
        jsr     sapc
        pla
:       jmp     sappn

; A -> numbuf (decimal, unsigned)
dec16p: ldy     #0
@d:     phy
        ldx     #10
        jsr     udiv16                  ; A = quotient, t2 = remainder
        ply
        pha
        lda     z:t2
        ora     #'0'
        sep     #$20
        .a8
        sta     dtmp,y
        rep     #$20
        .a16
        pla
        iny
        cmp     #0
        bne     @d
        ldx     #0
@r:     dey
        lda     dtmp,y
        sep     #$20
        .a8
        sta     numbuf,x
        rep     #$20
        .a16
        inx
        cpy     #0
        bne     @r
        sep     #$20
        .a8
        stz     numbuf,x
        rep     #$20
        .a16
        rts

; A / X -> A (unsigned 16), the remainder in t2 (t2, t3 used; keeps t0, t1)
udiv16: stx     z:t3
        sta     z:t2                    ; (the dividend shifts out, the quotient in)
        lda     #0
        ldy     #16
:       asl     z:t2
        rol     a
        cmp     z:t3
        bcc     :+
        sbc     z:t3
        inc     z:t2
:       dey
        bne     :--
        pha
        lda     z:t2
        sta     z:t3
        pla
        sta     z:t2
        lda     z:t3
        rts
; A mod X -> A
umod16: jsr     udiv16
        lda     z:t2
        rts
; A * X -> A (low 16 bits; t3, t4 used)
umul16: stx     z:t3
        sta     z:t4
        lda     #0
        ldy     #16
:       asl     a
        asl     z:t4
        bcc     :+
        clc
        adc     z:t3
:       dey
        bne     :--
        rts
; A * X -> t1:t0 (32 bits; t3, t4 used)
umul32: stx     z:t3
        sta     z:t4
        stz     z:t0
        stz     z:t1
        ldy     #16
:       asl     z:t0
        rol     z:t1
        asl     z:t4
        bcc     :+
        lda     z:t0
        clc
        adc     z:t3
        sta     z:t0
        lda     z:t1
        adc     #0
        sta     z:t1
:       dey
        bne     :--
        rts
; t1:t0 / X -> A (the quotient's low 16 bits; t3 used)
udiv32: stx     z:t3
        lda     #0
        ldy     #32
:       asl     z:t0
        rol     z:t1
        rol     a
        cmp     z:t3
        bcc     :+
        sbc     z:t3
        inc     z:t0
:       dey
        bne     :--
        lda     z:t0
        rts

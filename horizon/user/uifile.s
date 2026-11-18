; uifile.s - controls library: the file dialog (open / save). See ui.inc.
;   The current folder is read (SYS_READDIR, in batches) into a bank of its own: an index of
;   2-byte record offsets at $0000 (MAXE entries), records {u8 attr, u8 length, name} from
;   $1000, the READDIR buffer at $F000. Sorted on the way in: folders first, then names
;   ignoring case (binary insertion).
        .include "horizon.inc"
        .include "ui.inc"
        .import ui_modal_begin, ui_modal_end, ui_modal_get

MAXE    = 2000
RECS    = $1000
RECEND  = $EF00
DBUF    = $F000
DBUFLEN = $0800
DW      = 380                           ; the window's content
DH      = 268

        .segment "CODE"
        .a16
        .i16

; A = 0 open / 1 save, X = path buffer (128), Y = title -> C clear: chosen, C set: cancelled
ui_filedlg:
        sta     dl_mode
        stx     dl_out
        sty     dl_wo+8
        jsr     ui_modal_begin
        sys     SYS_BALLOC
        bcc     :+
        jsr     ui_beep
        jsr     ui_modal_end
        sec
        rts
:       sta     dl_bank
        lda     #^dl_wo                 ; (bank)
        sta     dl_wo+10
        sep     #$20
        .a8
        lda     #WF_MODAL               ; (flags: a dialog)
        sta     dl_wo+11
        rep     #$20
        .a16
        ptr     dl_wo
        sys     SYS_WOPEN
        bcc     :+
        lda     dl_bank
        sys     SYS_BFREE
        jsr     ui_modal_end
        sec
        rts
:       sta     dl_win
        sta     z:ui_win
        ldx     #0                      ; the controls: our window, the OK label
:       lda     dl_ctl,x
        beq     :+
        tay
        sep     #$20
        .a8
        lda     dl_win
        sta     a:CT_WIN,y
        rep     #$20
        .a16
        inx
        inx
        bra     :-
:       ldx     #.loword(s_open)
        lda     dl_mode
        beq     :+
        ldx     #.loword(s_save)
:       stx     dl_bok+BT_LABEL
        lda     #UF_FOCUS               ; the name field: empty, or the suggested name
        ldx     dl_mode
        beq     :+
        lda     #0
:       sta     dl_list+CT_FLAGS
        eor     #UF_FOCUS
        sta     dl_name+CT_FLAGS
        lda     #0                      ; (no button focused from the last time)
        sta     dl_bpar+CT_FLAGS
        lda     #UF_CANCEL
        sta     dl_bcan+CT_FLAGS
        lda     #UF_DEFAULT
        sta     dl_bok+CT_FLAGS
        stz     dl_nbuf
        lda     dl_mode
        beq     @nosug
        ldx     dl_out                  ; the part after the last '/'
        ldy     #0
:       lda     a:0,x
        and     #$00FF
        beq     :++
        cmp     #'/'
        bne     :+
        txy
        iny
:       inx
        bra     :--
:       cpy     #0
        bne     :+
        ldy     dl_out
:       tyx
        ldy     #.loword(dl_nbuf)
        jsr     ui_strcpy
@nosug: ldx     #.loword(dl_nbuf)
        jsr     ui_strlen
        sta     dl_name+FD_LEN
        sta     dl_name+FD_CUR
        stz     dl_name+FD_ANC
        stz     dl_name+FD_SCR
        ldx     #.loword(dl_ctl)
        jsr     ui_drawall
        jsr     dl_reload

@loop:  lda     dl_win
        jsr     ui_modal_get
        cmp     #WE_CLOSE
        jeq     @cancel
        ldx     #.loword(dl_ctl)
        jsr     ui_event
        cmp     #UA_CLICK
        bne     @nclick
        cpx     #.loword(dl_bcan)
        jeq     @cancel
        cpx     #.loword(dl_bpar)
        bne     :+
        jsr     dl_parent
        jmp     @loop
:       jsr     dl_ok
        jcs     @loop
        bra     @done
@nclick:
        cmp     #UA_CHANGE
        bne     @nchg
        cpx     #.loword(dl_list)
        jne     @loop
        jsr     dl_selrec               ; a file selected: its name in the field
        jcs     @loop
        ldy     #0
        lda     [ui_p],y
        and     #$0010
        jne     @loop
        jsr     dl_recname
        ldx     #.loword(dl_name)
        ldy     #.loword(dl_rname)
        jsr     ui_fdset
        jmp     @loop
@nchg:  cmp     #UA_OPEN
        bne     @nopen
        jsr     dl_open
        jcs     @loop
        bra     @done
@nopen: cmp     #UA_NONE                ; Backspace in the list: the parent folder
        jne     @loop
        lda     ui_ev
        and     #$00FF
        cmp     #WE_KEY
        jne     @loop
        lda     dl_list+CT_FLAGS
        and     #UF_FOCUS
        jeq     @loop
        lda     ui_key
        cmp     #8
        bne     :+
        jsr     dl_parent
        jmp     @loop
:       jsr     dl_typed                ; (0.15) a character: type-ahead, the Name field
        jmp     @loop
@cancel:
        jsr     dl_close
        sec
        rts
@done:  ldx     #.loword(dl_full)       ; the result
        ldy     dl_out
        jsr     ui_strcpy
        jsr     dl_close
        clc
        rts

dl_close:
        stz     ui_dlfilt               ; (the filter is for one dialog)
        lda     dl_win
        sys     SYS_WCLOSE
        lda     dl_bank
        sys     SYS_BFREE
        jmp     ui_modal_end

; (0.15) a character typed while the list has the focus (ui_key): added to the typed
; prefix (a pause of 1 s starts it again); the first entry starting with it is selected
; (a file: its name goes to the Name field, as by a click). No entry starts with it: the
; prefix goes to the Name field, which gets the focus (typing goes on there).
dl_typed:
        lda     ui_key
        cmp     #' '
        bcc     @r
        cmp     #$7F
        bcc     :+
@r:     rts
:       pha
        sys     SYS_UPTIME
        tax
        sec
        sbc     dl_tat
        stx     dl_tat
        cmp     #1000
        bcc     :+
        stz     dl_tn
:       pla
        ldx     dl_tn
        cpx     #40
        bcs     @r
        sta     dl_tbuf,x
        inx
        stx     dl_tn
        stz     dl_tbuf,x
        stz     z:ui_t5                 ; the first entry starting with it
@f:     lda     z:ui_t5
        cmp     dl_n
        bcs     @none
        jsr     dl_rec
        ldy     #1
        lda     [ui_p],y
        and     #$00FF
        cmp     dl_tn
        bcc     @nx
        ldx     #0
        ldy     #2
:       lda     [ui_p],y
        jsr     lower
        sta     z:ui_t4
        lda     dl_tbuf,x
        jsr     lower
        cmp     z:ui_t4
        bne     @nx
        iny
        inx
        cpx     dl_tn
        bcc     :-
        ldx     #.loword(dl_list)       ; found: selected (a file: its name in the field)
        lda     z:ui_t5
        jsr     ui_lssel
        jsr     dl_selrec
        bcs     @out
        ldy     #0
        lda     [ui_p],y
        and     #$0010
        bne     @out
        jsr     dl_recname
        ldx     #.loword(dl_name)
        ldy     #.loword(dl_rname)
        jmp     ui_fdset
@nx:    inc     z:ui_t5
        bra     @f
@none:  ldx     #.loword(dl_name)       ; none: typing goes on in the Name field
        ldy     #.loword(dl_tbuf)
        jsr     ui_fdset
        ldx     #.loword(dl_name)
        lda     dl_tn
        sta     a:FD_CUR,x
        sta     a:FD_ANC,x
        jsr     ui_draw
        ldx     #.loword(dl_name)
        jsr     ui_focus
        stz     dl_tn
@out:   rts

; OK (button or Enter): the name typed, else the selected folder -> C clear: done (dl_full)
dl_ok:  lda     dl_name+FD_LEN
        bne     dlo_name
dl_open:                                ; (the list's selection: a folder is entered)
        jsr     dl_selrec
        bcs     dlo_beep
        jsr     dl_recname
        ldy     #0
        lda     [ui_p],y
        and     #$0010
        beq     :+
        ldx     #.loword(dl_rname)
        jmp     dl_enter
:       ldx     #.loword(dl_name)
        ldy     #.loword(dl_rname)
        jsr     ui_fdset
dlo_name:  jsr     dl_stat                 ; the name typed: a folder?
        bcs     dlo_new
        lda     dl_st+4
        and     #$0010
        beq     dlo_exists
        ldx     #.loword(dl_nbuf)
        jsr     dl_enter
        ldx     #.loword(dl_name)
        ldy     #.loword(s_empty)
        jsr     ui_fdset
        sec
        rts
dlo_exists:
        jsr     dl_join
        lda     dl_mode                 ; saving over a file: ask
        beq     dlo_ok
        ldx     #.loword(al_repl)
        jsr     ui_alert
        cmp     #0
        bne     dlo_no
        bra     dlo_ok
dlo_new:   jsr     dl_join
        lda     dl_mode                 ; opening a file that is not there
        beq     dlo_beep
dlo_ok:    clc
        rts
dlo_beep:  jsr     ui_beep
dlo_no:    sec
        rts

; STAT dl_nbuf -> C clear: it exists, dl_st = its record
dl_stat:
        lda     #.loword(dl_nbuf)
        sta     dl_sb
        lda     #^dl_nbuf
        sta     dl_sb+2
        lda     #.loword(dl_st)
        sta     dl_sb+3
        lda     #^dl_st
        sta     dl_sb+5
        ptr     dl_sb
        sys     SYS_STAT
        rts

; dl_full = the current folder + "/" + dl_nbuf (dl_nbuf itself if it starts with '/')
dl_join:
        lda     dl_nbuf
        and     #$00FF
        cmp     #'/'
        bne     :+
        ldx     #.loword(dl_nbuf)
        ldy     #.loword(dl_full)
        jmp     ui_strcpy
:       ptr     dl_full
        lda     #128
        sys     SYS_GETCWD
        bcc     :+
        lda     #0
:       tax                             ; X = its length
        beq     :+
        lda     dl_full-1,x
        and     #$00FF
        cmp     #'/'
        beq     :++
:       lda     #'/'
        sta     dl_full,x
        inx
:       ldy     #0
:       lda     dl_nbuf,y
        and     #$00FF
        sep     #$20
        .a8
        sta     dl_full,x
        rep     #$20
        .a16
        beq     :+
        inx
        iny
        cpx     #127
        bcc     :-
        stz     dl_full,x
:       rts

; enter folder X (a name or path): C set (stays in the dialog)
dl_enter:
        ldy     #^dl_rname
        sys     SYS_CHDIR
        bcc     :+
        jsr     ui_beep
        sec
        rts
:       jsr     dl_reload
        sec
        rts

; the parent folder, with the one we came from selected
dl_parent:
        ptr     dl_full
        lda     #128
        sys     SYS_GETCWD
        ldx     #0                      ; the last part
        ldy     #0
:       lda     dl_full,x
        and     #$00FF
        beq     :++
        cmp     #'/'
        bne     :+
        txy
        iny
:       inx
        bra     :--
:       cpx     #2
        bcs     :+
        rts                             ; ("/": nothing above)
:       tya
        clc
        adc     #.loword(dl_full)
        tax
        ldy     #.loword(dl_came)
        jsr     ui_strcpy
        ldx     #.loword(s_dotdot)
        ldy     #^s_dotdot
        sys     SYS_CHDIR
        bcs     @out
        jsr     dl_reload
        stz     z:ui_t5                 ; find it
@f:     lda     z:ui_t5
        cmp     dl_n
        bcs     @out
        jsr     dl_rec
        jsr     dl_recname
        ldx     #0
:       lda     dl_rname,x
        and     #$00FF
        sta     z:ui_t4
        lda     dl_came,x
        and     #$00FF
        cmp     z:ui_t4
        bne     @nx
        cmp     #0
        beq     @hit
        inx
        bra     :-
@nx:    inc     z:ui_t5
        bra     @f
@hit:   ldx     #.loword(dl_list)
        lda     z:ui_t5
        jsr     ui_lssel
@out:   rts

; read the folder, show it
dl_reload:
        jsr     dl_load
        ldx     #.loword(dl_list)
        lda     dl_n
        jsr     ui_lsset
        ; fall through
; the path above the list, cut at the left to fit
dl_path:
        lda     dl_win
        sta     z:ui_win
        lda     #8                      ; "Folder:", then the path
        sta     z:ui_x
        lda     #6
        sta     z:ui_y
        lda     #DW - 16
        sta     z:ui_w
        lda     #UI_LINE + 2
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        lda     #8
        sta     z:ui_y
        stz     z:ui_font
        ldx     #.loword(s_folder)
        lda     #C_DARK | ($FF << 8)
        jsr     ui_text
        ldx     #.loword(s_folder)
        lda     #0
        jsr     ui_twidth
        clc
        adc     #8 + 4
        sta     z:ui_x
        eor     #$FFFF
        sec
        adc     #DW - 8
        sta     dl_pw                   ; the room for the path
        ptr     dl_full
        lda     #128
        sys     SYS_GETCWD
        bcc     :+
        lda     #'?'
        sta     dl_full
:       ldx     #.loword(dl_full)
@cut:   phx
        lda     #0
        jsr     ui_twidth
        plx
        cmp     dl_pw
        bcc     @draw
        beq     @draw
        inx
        lda     a:3,x
        and     #$00FF
        beq     @draw
        lda     #'.' | ('.' << 8)
        sta     a:0,x
        sta     a:1,x
        bra     @cut
@draw:  lda     #C_BLACK | ($FF << 8)
        jmp     ui_text

; ---------------------------------------------------------------- the folder
dl_load:
        stz     dl_n
        lda     #RECS
        sta     dl_heap
        stz     dl_skip
@call:  lda     #.loword(s_dot)         ; block: path ".", buffer, length, skip
        sta     dl_rb
        lda     #^s_dot
        sta     dl_rb+2
        lda     #DBUF
        sta     dl_rb+3
        lda     dl_bank
        sta     dl_rb+5
        lda     #DBUFLEN
        sta     dl_rb+6
        lda     dl_skip
        sta     dl_rb+8
        ptr     dl_rb
        sys     SYS_READDIR
        bcs     @out
        cmp     #0
        beq     @out
        sta     dl_cnt
        clc
        adc     dl_skip
        sta     dl_skip
        lda     #DBUF
        sta     z:ui_q                  ; ui_q = the READDIR entry
        lda     dl_bank
        sta     z:ui_q+2
@ent:   lda     dl_n
        cmp     #MAXE
        bcs     @out
        ldy     #5                      ; record = 2 + length
        lda     [ui_q],y
        and     #$00FF
        clc
        adc     #2
        adc     dl_heap
        bcs     @out
        cmp     #RECEND
        bcs     @out
        jsr     dl_add
        ldy     #5
        lda     [ui_q],y
        and     #$00FF
        clc
        adc     #6
        adc     z:ui_q
        sta     z:ui_q
        dec     dl_cnt
        bne     @ent
        bra     @call
@out:   rts

; the READDIR entry at ui_q -> a record at dl_heap, its index inserted in order (0.15: with
; a filter, only folders and the Atari files of that kind)
dl_add: lda     ui_dlfilt
        beq     dl_add1
        ldy     #4
        lda     [ui_q],y
        and     #$0010
        bne     dl_add1
        lda     [ui_q],y                ; the name, zero-terminated, in dl_rname
        xba
        and     #$00FF
        cmp     #120
        bcc     :+
        lda     #120
:       sta     z:ui_t3
        ldx     #0
        ldy     #6
:       cpx     z:ui_t3
        bcs     :+
        lda     [ui_q],y
        sta     dl_rname,x
        inx
        iny
        bra     :-
:       stz     dl_rname,x
        ptr     dl_rname
        jsr     atari_kind
        cmp     ui_dlfilt
        beq     dl_add1
        rts
dl_add1:
        lda     dl_heap
        sta     z:ui_p
        lda     dl_bank
        sta     z:ui_p+2
        ldy     #4                      ; attr, length, name
        lda     [ui_q],y
        sta     [ui_p]                  ; (2 bytes: attr, length)
        and     #$FF00
        xba
        sta     dl_len
        lda     z:ui_q                  ; copy the name: [t0] -> [t2]
        clc
        adc     #6
        sta     z:ui_t0
        lda     z:ui_p
        inc     a
        inc     a
        sta     z:ui_t2
        lda     dl_bank
        sta     z:ui_t1
        sta     z:ui_t3
        ldy     #0
        sep     #$20
        .a8
:       cpy     dl_len
        bcs     :+
        lda     [ui_t0],y
        sta     [ui_t2],y
        iny
        bra     :-
:       rep     #$20
        .a16
        stz     dl_lo                   ; binary search lo .. hi
        lda     dl_n
        sta     dl_hi
@bs:    lda     dl_lo
        cmp     dl_hi
        bcs     @ins
        clc
        adc     dl_hi
        lsr     a
        sta     dl_mid
        jsr     dl_rec2                 ; [ui_t0] = record mid
        jsr     dl_before
        bcc     :+
        lda     dl_mid
        sta     dl_hi
        bra     @bs
:       lda     dl_mid
        inc     a
        sta     dl_lo
        bra     @bs
@ins:   lda     dl_bank                 ; shift idx[lo..n) up; idx[lo] = new
        sta     z:ui_t1                 ; (ui_t0:t1 = bank:0, a long pointer)
        stz     z:ui_t0
        lda     dl_n
        asl     a
        tay
:       tya
        lsr     a
        cmp     dl_lo
        beq     :+
        dey
        dey
        lda     [ui_t0],y
        iny
        iny
        sta     [ui_t0],y
        dey
        dey
        bra     :-
:       lda     dl_heap
        sta     [ui_t0],y
        inc     dl_n
        lda     dl_len
        clc
        adc     #2
        adc     dl_heap
        sta     dl_heap
        rts

; ui_t0:t1 = the record of entry dl_mid (a long pointer)
dl_rec2:
        lda     dl_bank
        sta     z:ui_t1
        stz     z:ui_t0
        lda     dl_mid
        asl     a
        tay
        lda     [ui_t0],y
        sta     z:ui_t0
        rts

; C set if record ui_p sorts before record [ui_t0]: folders first, then names
dl_before:
        lda     [ui_p]
        and     #$0010
        sta     z:ui_t3
        lda     [ui_t0]
        and     #$0010
        cmp     z:ui_t3
        beq     @names
        bcc     @yes
@no:    clc
        rts
@yes:   sec
        rts
@names: ldy     #1
        lda     [ui_p],y
        and     #$00FF
        sta     z:ui_t4                 ; its length
        lda     [ui_t0],y
        and     #$00FF
        sta     z:ui_t5
        ldy     #2
@c:     tya
        dec     a
        dec     a
        cmp     z:ui_t4
        bcs     @endp
        cmp     z:ui_t5
        bcs     @no
        lda     [ui_p],y
        jsr     lower
        sta     z:ui_t3
        lda     [ui_t0],y
        jsr     lower
        cmp     z:ui_t3
        beq     :+
        bcs     @yes
        bra     @no
:       iny
        bra     @c
@endp:  cmp     z:ui_t5
        bcc     @yes
        bra     @no

lower:  and     #$00FF
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
:       rts

; ui_p = the record of entry A
dl_rec: asl     a
        tay
        lda     dl_bank
        sta     z:ui_p+2
        sta     z:ui_t1
        stz     z:ui_t0
        lda     [ui_t0],y
        sta     z:ui_p
        rts

; ui_p = the record of the list's selection -> C set: none
dl_selrec:
        lda     dl_list+LS_SEL
        cmp     dl_n
        bcs     :+
        jsr     dl_rec
        clc
:       rts

; the name of record ui_p -> dl_rname (at most 120 characters, printable)
dl_recname:
        ldy     #1
        lda     [ui_p],y
        and     #$00FF
        cmp     #120
        bcc     :+
        lda     #120
:       sta     z:ui_t3
        ldx     #0
        ldy     #2
@c:     cpx     z:ui_t3
        bcs     @e
        lda     [ui_p],y
        and     #$00FF
        cmp     #' '
        bcc     :+
        cmp     #$7F
        bcc     :++
:       lda     #'?'
:       sta     dl_rname,x
        inx
        iny
        bra     @c
@e:     stz     dl_rname,x
        rts

; the list's row callback: A = row -> X = its text; an icon at ui_x, ui_y
dl_row: jsr     dl_rec
        jsr     dl_recname
        lda     [ui_p]
        and     #$0010
        beq     @page
        ldy     #.loword(ic_folder)
        bra     :+
@page:  ldy     #.loword(ic_page)
:       jsr     dl_icon
        ldx     #.loword(dl_rname)
        rts

; draw icon table Y at ui_x, ui_y: {op | colour << 8, dx, dy, w, h}..., 0 (keeps ui_x, ui_y)
dl_icon:
        lda     z:ui_x
        pha
        lda     z:ui_y
        pha
@i:     lda     a:0,y
        beq     @out
        lda     a:6,y
        sta     z:ui_w
        lda     a:8,y
        sta     z:ui_h
        lda     1,s                     ; (ui_y)
        clc
        adc     a:4,y
        sta     z:ui_y
        lda     3,s                     ; (ui_x)
        clc
        adc     a:2,y
        sta     z:ui_x
        lda     a:0,y
        phy
        jsr     ui_rect
        ply
        tya
        clc
        adc     #10
        tay
        bra     @i
@out:   pla
        sta     z:ui_y
        pla
        sta     z:ui_x
        rts

        .segment "RODATA"
s_open: .byte   "Open", 0
s_save: .byte   "Save", 0
s_par:  .byte   "Parent", 0
s_can:  .byte   "Cancel", 0
s_namel: .byte  "Name:", 0
s_folder: .byte "Folder:", 0
s_dot:  .byte   ".", 0
s_dotdot: .byte "..", 0
s_empty: .byte  0
s_repl: .byte   "That file already exists.", 10, "Replace it?", 0
s_repb: .byte   "Replace", 0
s_title: .byte  "Replace", 0
al_repl: .word  2, s_title, s_repl, s_repb, s_can, 0
.define IR(op, col, dx, dy, w, h) .word op | (col << 8), dx, dy, w, h
ic_folder:
        IR      WD_FILL, C_DARK, 0, 2, 6, 2         ; the tab
        IR      WD_FRAME, C_DARK, 0, 3, 13, 9       ; the body
        IR      WD_FILL, C_YELLOW, 1, 4, 11, 7
        .word   0
ic_page:
        IR      WD_FRAME, C_DARK, 1, 1, 10, 12
        IR      WD_FILL, C_WHITE, 2, 2, 8, 10
        IR      WD_FILL, C_MID, 3, 4, 6, 1          ; lines of text
        IR      WD_FILL, C_MID, 3, 6, 6, 1
        IR      WD_FILL, C_MID, 3, 8, 6, 1
        IR      WD_FILL, C_MID, 3, 10, 4, 1
        .word   0

        .segment "DATA"
dl_wo:  .word   (640 - DW - 2) / 2, (360 - DH - 17) / 2, DW, DH, 0, 0
dl_ctl: .addr   dl_list, dl_name, dl_lab, dl_bpar, dl_bcan, dl_bok, 0
dl_list: .byte  UT_LIST, 0
        .word   8, 24, DW - 16, 172, 0
        .word   0, $FFFF, 0, dl_row, 16, 0
        .res    SB_SIZE
dl_name: .byte  UT_FIELD, 0
        .word   52, 206, DW - 60, UI_FLDH, 0
        .word   dl_nbuf, 128, 0, 0, 0, 0
dl_lab: .byte   UT_LABEL, 0
        .word   8, 210, 40, UI_LINE, 0
        .word   s_namel
dl_bpar: .byte  UT_BUTTON, 0
        .word   8, 238, 72, UI_BTNH, 0
        .word   s_par
dl_bcan: .byte  UT_BUTTON, 0
        .word   DW - 168, 238, 76, UI_BTNH, UF_CANCEL
        .word   s_can
dl_bok: .byte   UT_BUTTON, 0
        .word   DW - 84, 238, 76, UI_BTNH, UF_DEFAULT
        .word   s_open

        .segment "BSS"
ui_dlfilt: .res 2                       ; (0.15) the next dialog lists only folders and
                                        ;   Atari files of this kind (CK_DISK, ...); 0: all
        .export ui_dlfilt
dl_tat: .res    2                       ; type-ahead: the last key's time, the prefix
dl_tn:  .res    2
dl_tbuf: .res   42
dl_mode: .res   2
dl_pw:  .res    2
dl_out: .res    2
dl_win: .res    2
dl_bank: .res   2
dl_n:   .res    2
dl_heap: .res   2
dl_skip: .res   2
dl_cnt: .res    2
dl_len: .res    2
dl_lo:  .res    2
dl_hi:  .res    2
dl_mid: .res    2
dl_rb:  .res    10
dl_sb:  .res    6
dl_st:  .res    10
dl_nbuf: .res   130
dl_rname: .res  124
dl_full: .res   132
dl_came: .res   130

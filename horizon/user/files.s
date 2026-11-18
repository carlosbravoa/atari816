; FILES - the full-screen file browser (/BIN/FILES.PRG; the shell's "files", and what
; INIT's shell starts with).
;   The current folder is read once (READDIR, in batches) into a bank of its own: one
;   record per entry {u24 size, u8 attr, u8 length, name}, up to MAXENT entries, sorted
;   on the way in (binary insertion: folders first, then names, case-insensitive). Keys
;   and the mouse only move a selection and redraw the lines that change.
;   Keys: up/down, PgUp/PgDn, Home/End move; typing jumps to the first name starting with
;   the typed letters (1 s pause starts over); Enter opens: a folder is entered, an Atari
;   file (.atr .xfd .xex .com .exe .car .rom .bin) is run (start this, and only this:
;   ulib atari_run), a .PRG runs as a Horizon program, a text file (.txt .doc .nfo .md
;   .cfg .ini .asc) is shown a page at a time; Backspace goes to the parent folder; Esc
;   goes back to the shell.
;   Mouse: the wheel scrolls, a click selects, a double click (within 0.5 s) opens.
;   Screen: row 0 the folder, rows 1..rows-4 the list, row rows-2 what is mounted, row
;   rows-1 the keys. Drawn with the console's VT52 escapes (ESC Y, ESC K, ESC p/q).
        .include "horizon.inc"

MAXENT  = 1000
HEAPMAX = $FE00                         ; bytes of entry records in the bank

        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_ICLAIM              ; ours, or lent by the shell
        sys     SYS_CSIZE
        sta     z:cols
        stx     z:rows
        sec
        sbc     #14
        sta     z:namew                 ; name column
        txa
        sec
        sbc     #4
        sta     z:listn                 ; list rows (screen rows 1 .. listn)
        sys     SYS_BALLOC              ; the entry records
        bcc     :+
        print   "files: no memory\n"
        exit    1
:       sta     z:hbank
        jsr     esc_f                   ; no text cursor
        jsr     load
        jsr     redraw

; ---------------------------------------------------------------- input loop
loop:   sys     SYS_IREAD
        jcs     quit
        cmp     #$0200
        jeq     wheel
        cmp     #$0100
        jcs     mouse
        jsr     key_ascii
        cmp     #0
        beq     loop
        sta     z:key
        lda     z:msg                   ; a message on the status line goes with any key
        beq     :+
        stz     z:msg
        jsr     status
        jsr     flush
:       lda     z:key
        cmp     #27
        jeq     quit
        cmp     #3
        jeq     quit
        cmp     #13
        jeq     open
        cmp     #8
        jeq     parent
        cmp     #KEY_UP
        bne     :+
        lda     #$FFFF
        jmp     move
:       cmp     #KEY_DOWN
        bne     :+
        lda     #1
        jmp     move
:       cmp     #KEY_PGUP
        bne     :+
        lda     z:listn
        eor     #$FFFF
        inc     a
        jmp     move
:       cmp     #KEY_PGDN
        bne     :+
        lda     z:listn
        jmp     move
:       cmp     #KEY_HOME
        bne     :+
        lda     #0
        jmp     select
:       cmp     #KEY_END
        bne     :+
        lda     z:n
        dec     a
        jmp     select
:       cmp     #' '
        jcc     loop
        cmp     #$7F
        jcs     loop
        jmp     typeahead

; A = signed step: move the selection, clamped
move:   clc
        adc     z:sel
        bpl     :+
        lda     #0
:       ; fall through
; select entry A (clamped to the list); scroll or redraw the two lines that change
select: cmp     z:n
        bcc     :+
        lda     z:n
        dec     a
        bpl     :+
        lda     #0
:       sta     z:nsel
        cmp     z:top                   ; outside the page: scroll so it shows
        bcc     @page
        sec
        sbc     z:top
        cmp     z:listn
        bcs     @page
        lda     z:sel                   ; same page: old line normal, new line inverse
        cmp     z:nsel
        beq     @done
        pha                             ; move the selection first, so the old line
        lda     z:nsel                  ; is drawn as not selected
        sta     z:sel
        pla
        jsr     line_at
        lda     z:sel
        jsr     line_at
        jsr     flush
@done:  jmp     loop
@page:  lda     z:nsel                  ; new page: the selection at the top, or at the
        sta     z:sel                   ; bottom when going down
        cmp     z:top
        bcc     :+
        sec
        sbc     z:listn
        inc     a
        bra     :++
:       lda     z:nsel
:       bpl     :+
        lda     #0
:       sta     z:top
        jsr     list
        jsr     flush
        jmp     loop

wheel:  stx     z:tmp                   ; X = wheel steps (up > 0): 3 lines each, up
        txa
        asl     a
        clc
        adc     z:tmp
        eor     #$FFFF
        inc     a
        jmp     move

; mouse: A = $0100 | buttons, X = x, Y = y. A left button press selects the line under the
; pointer; a second press on the same line within 0.5 s opens it.
mouse:  and     #$0007
        pha
        eor     z:btn                   ; changed buttons
        and     #$0001
        sta     z:tmp
        pla
        sta     z:btn
        lda     z:tmp                   ; left button just went down?
        jeq     loop
        lda     z:btn
        and     #$0001
        jeq     loop
        tya                             ; text row = (y - 6) / 12
        sec
        sbc     #6
        jcc     loop
        ldx     #0
:       cmp     #12
        bcc     :+
        sbc     #12
        inx
        bra     :-
:       txa                             ; list rows are 1 .. listn
        jeq     loop
        cmp     z:listn
        beq     :+
        jcs     loop
:       dec     a
        clc
        adc     z:top
        cmp     z:n
        jcs     loop
        sta     z:tmp
        sys     SYS_UPTIME
        sta     z:now
        lda     z:tmp
        cmp     z:sel                   ; a second press on the selected line, soon enough
        bne     :+
        lda     z:now
        sec
        sbc     z:lastclk
        cmp     #500
        bcs     :+
        stz     z:lastclk
        jmp     open
:       lda     z:now
        sta     z:lastclk
        lda     z:tmp
        jmp     select

; type-ahead: the typed letters so far (reset after 1 s) find the first name they start
typeahead:
        sys     SYS_UPTIME
        sta     z:now
        sec
        sbc     z:lastkey
        cmp     #1000
        bcc     :+
        stz     z:plen
:       lda     z:now
        sta     z:lastkey
        lda     z:key
        jsr     lower
        ldx     z:plen
        cpx     #31
        bcs     :+
        sep     #$20
        .a8
        sta     prefix,x
        rep     #$20
        .a16
        inc     z:plen
:       ldx     #0                      ; X = entry (sorted order)
@ent:   cpx     z:n
        jcs     loop
        phx
        jsr     rec                     ; pa = record of entry X
        ldy     #4
        lda     [pa],y
        and     #$00FF
        cmp     z:plen
        bcc     @no
        ldx     #0
:       cpx     z:plen
        bcs     @yes
        txa
        clc
        adc     #5
        tay
        lda     [pa],y
        jsr     lower
        sta     z:tmp
        lda     prefix,x
        and     #$00FF
        cmp     z:tmp
        bne     @no
        inx
        bra     :-
@yes:   pla
        jmp     select
@no:    plx
        inx
        bra     @ent

; ---------------------------------------------------------------- actions
; Enter: open the selected entry
open:   lda     z:n
        jeq     loop
        lda     z:sel
        tax
        jsr     rec
        jsr     recname                 ; name -> fname
        ldy     #3
        lda     [pa],y
        and     #$0010
        beq     @file
        ldx     #.loword(fname)         ; a folder: go in
        ldy     #^fname
        sys     SYS_CHDIR
        bcc     :+
        jmp     oops
:       jsr     load
        jsr     redraw
        jmp     loop
@file:  ldx     #.loword(fname)
        ldy     #^fname
        jsr     atari_kind
        cmp     #0
        beq     @prg
        ldx     #.loword(fname)         ; an Atari file: start this, and only this
        ldy     #^fname
        jsr     atari_run
        bcs     oops
        jsr     redraw                  ; (after F12; the status line shows what is in)
        jmp     loop
@prg:   ldx     #.loword(fname)
        ldy     #^fname
        jsr     ext_of
        ldx     #0
:       lda     txt_ext,x               ; text?
        and     #$00FF
        beq     :+
        jsr     ext_is
        jeq     pager
        inx
        inx
        inx
        inx
        bra     :-
:       lda     #'P' | ('R' << 8)       ; a Horizon program?
        cmp     z:ext
        bne     :+
        lda     z:ext+2
        and     #$00FF
        cmp     #'G'
        jeq     program
:       lda     #$C3                    ; unknown
        ; fall through
; an error A: say it on the status line until the next key
oops:   sta     z:err
        jsr     goto_status
        jsr     esc_p
        lda     z:err
        cmp     #$C3
        bne     :+
        print   " unknown file type"
        brl     @end
:       cmp     #$C4
        bne     :+
        print   " not a valid or supported image"
        brl     @end
:       cmp     #$44
        beq     :+
        cmp     #$45
        bne     :++
:       print   " file not found"
        bra     @end
:       cmp     #$C5
        bne     :+
        print   " the firmware menu is open: close it and try again"
        brl     @end
:       print   " error $"
        lda     z:err
        jsr     put_hex8
@end:   print   " (any key) "
        jsr     esc_k
        jsr     esc_q
        jsr     flush
        lda     #1
        sta     z:msg
        jmp     loop

; Backspace: the parent folder, with the folder we came from selected
parent: ldx     #.loword(fname)
        ldy     #^fname
        lda     #128
        sys     SYS_GETCWD
        ldx     #0                      ; the last component -> prefix
        ldy     #0
:       lda     fname,x
        and     #$00FF
        beq     :++
        cmp     #'/'
        bne     :+
        txy
        iny
:       inx
        bra     :--
:       sty     z:tmp                   ; ("/" itself: nothing to do)
        cpx     #2
        jcc     loop
        ldx     #0
:       lda     fname,y
        and     #$00FF
        sep     #$20
        .a8
        sta     came,x
        rep     #$20
        .a16
        beq     :+
        inx
        iny
        bra     :-
:       ldx     #.loword(dotdot)
        ldy     #^dotdot
        sys     SYS_CHDIR
        jsr     load
        ldx     #0                      ; find the folder we came from
@f:     cpx     z:n
        bcs     @show
        phx
        jsr     rec
        jsr     recname
        ldy     #0
:       lda     fname,y
        and     #$00FF
        sta     z:tmp
        lda     came,y
        and     #$00FF
        cmp     z:tmp
        bne     @nx
        cmp     #0
        beq     @hit
        iny
        bra     :-
@nx:    plx
        inx
        bra     @f
@hit:   pla
        sta     z:sel
        sec                             ; its page
        sbc     z:listn
        inc     a
        bpl     :+
        lda     #0
:       sta     z:top
@show:  jsr     redraw
        jmp     loop

; a .PRG: run it (the keyboard lent, ctrl-C stops it), then a key to come back
program:
        jsr     clear
        jsr     esc_e
        jsr     flush
        stz     z:u_arg
        stz     z:u_arg+2
        ldx     #.loword(fname)
        ldy     #^fname
        lda     #2
        jsr     spawn
        jcs     oops2
        sta     z:tmp
        ldx     #1
        sys     SYS_ILEND
        lda     z:tmp
        sys     SYS_WAIT
        sta     z:tmp
        print   "\n[exit "
        lda     z:tmp
        jsr     put_hex16
        print   "] any key"
        jsr     flush
        jsr     read_char
        jsr     esc_f
        jsr     redraw
        jmp     loop
oops2:  pha
        jsr     esc_f
        jsr     redraw
        pla
        jmp     oops

; a text file, a screen at a time
pager:  ldx     #.loword(fname)
        ldy     #^fname
        lda     #O_READ
        sys     SYS_OPEN
        jcs     oops
        sta     blk
        jsr     clear
        stz     z:lines
        stz     z:col
@rd:    lda     #.loword(dbuf)
        sta     blk+1
        sep     #$20
        .a8
        lda     #^dbuf
        sta     blk+3
        rep     #$20
        .a16
        lda     #64
        sta     blk+4
        ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_READ
        bcs     @eof
        cmp     #0
        beq     @eof
        sta     z:tmp
        ldx     #0
@ch:    cpx     z:tmp
        bcs     @rd
        lda     dbuf,x
        and     #$00FF
        phx
        jsr     pchar
        plx
        bcs     @stop
        inx
        bra     @ch
@eof:   jsr     put_nl
        print   "-- end: any key --"
        jsr     flush
        jsr     read_char
@stop:  lda     blk
        and     #$00FF
        sys     SYS_CLOSE
        jsr     redraw
        jmp     loop

; one character of the pager (CR dropped, other control characters as '.'); pauses
; when the screen is full. C set: the reader wants to stop.
pchar:  cmp     #13
        bne     :+
        clc
        rts
:       cmp     #10
        beq     @nl
        cmp     #9
        beq     :+
        cmp     #' '
        bcs     :+
        lda     #'.'
:       pha
        lda     z:col                   ; the line wraps at the screen edge
        cmp     z:cols
        bcc     :+
        jsr     @newl
        bcc     :+
        pla
        rts
:       pla
        jsr     out_char
        inc     z:col
        clc
        rts
@nl:    jsr     put_nl
        stz     z:col
        ; fall through
@newl:  stz     z:col
        inc     z:lines
        lda     z:lines
        inc     a
        cmp     z:rows
        bcc     :+
        stz     z:lines
        print   "-- more: any key, q to stop --"
        jsr     flush
        jsr     read_char
        pha
        lda     #13
        jsr     out_char
        jsr     esc_k
        pla
        cmp     #'q'
        beq     @q
        cmp     #27
        beq     @q
:       clc
        rts
@q:     sec
        rts

quit:   jsr     clear
        jsr     esc_e
        jsr     flush
        lda     z:hbank
        sys     SYS_BFREE
        exit    0

; ---------------------------------------------------------------- the directory
; read the current folder into the bank, sorted
load:   stz     z:n
        stz     z:heap
        stz     z:sel
        stz     z:top
        stz     z:skip
        stz     z:trunc
@call:  lda     #.loword(dot)           ; block: path ".", buffer, length, skip
        sta     blk
        lda     #^dot
        sta     blk+2
        lda     #.loword(dbuf)
        sta     blk+3
        lda     #^dbuf
        sta     blk+5
        lda     #DBUFLEN
        sta     blk+6
        lda     z:skip
        sta     blk+8
        ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_READDIR
        bcs     @out
        cmp     #0
        beq     @out
        sta     z:cnt
        clc
        adc     z:skip
        sta     z:skip
        ldx     #0
@ent:   stx     z:dpos
        lda     z:n                     ; room?
        cmp     #MAXENT
        bcs     @full
        lda     dbuf+5,x
        and     #$00FF
        clc
        adc     #5
        adc     z:heap
        bcs     @full
        cmp     #HEAPMAX
        bcs     @full
        jsr     add
        ldx     z:dpos
        lda     dbuf+5,x
        and     #$00FF
        clc
        adc     #6
        adc     z:dpos
        tax
        dec     z:cnt
        bne     @ent
        bra     @call
@full:  inc     z:trunc
@out:   rts

; record of dbuf entry at dpos -> heap; its index inserted in order
add:    lda     z:heap
        sta     z:pb
        lda     z:hbank
        sta     z:pb+2
        ldx     z:dpos
        ldy     #0
        sep     #$20
        .a8
:       lda     dbuf,x                  ; size (3 bytes)
        sta     [pb],y
        inx
        iny
        cpy     #3
        bne     :-
        inx                             ; (size byte 4 dropped)
:       lda     dbuf,x                  ; attr, length, name
        sta     [pb],y
        inx
        iny
        cpy     #5
        bne     :-
        rep     #$20
        .a16
        ldy     #4
        lda     [pb],y
        and     #$00FF
        sta     z:tmp
        ldy     #5
        sep     #$20
        .a8
:       lda     z:tmp
        beq     :+
        lda     dbuf,x
        sta     [pb],y
        inx
        iny
        dec     z:tmp
        bra     :-
:       rep     #$20
        .a16
        lda     z:heap                  ; binary search: lo .. hi
        sta     z:new
        stz     z:lo
        lda     z:n
        sta     z:hi
@bs:    lda     z:lo
        cmp     z:hi
        bcs     @ins
        clc
        adc     z:hi
        lsr     a
        sta     z:mid
        asl     a
        tax
        lda     idx,x
        sta     z:pa
        lda     z:hbank
        sta     z:pa+2
        jsr     before                  ; new (pb) before mid (pa)?
        bcc     :+
        lda     z:mid
        sta     z:hi
        bra     @bs
:       lda     z:mid
        inc     a
        sta     z:lo
        bra     @bs
@ins:   lda     z:n                     ; shift idx[lo..n) up, idx[lo] = new
        asl     a
        tax
:       txa
        lsr     a
        cmp     z:lo
        beq     :+
        lda     idx-2,x
        sta     idx,x
        dex
        dex
        bra     :-
:       lda     z:new
        sta     idx,x
        inc     z:n
        ldy     #4                      ; heap += 5 + length
        lda     [pb],y
        and     #$00FF
        clc
        adc     #5
        adc     z:heap
        sta     z:heap
        rts

; C set if record pb sorts before record pa: folders first, then names, ignoring case
before: ldy     #3
        lda     [pb],y
        and     #$0010
        sta     z:tmp
        lda     [pa],y
        and     #$0010
        cmp     z:tmp
        beq     @names
        bcc     @yes                    ; pb is a folder, pa is not
        clc
        rts
@names: ldy     #4
        lda     [pb],y
        and     #$00FF
        sta     z:lb
        lda     [pa],y
        and     #$00FF
        sta     z:la
        ldy     #5
@c:     tya                             ; end of either name?
        sec
        sbc     #5
        cmp     z:lb
        bcs     @endb
        cmp     z:la
        bcs     @no                     ; pa ended first: pa is a prefix of pb
        lda     [pb],y
        jsr     lower
        sta     z:tmp
        lda     [pa],y
        jsr     lower
        cmp     z:tmp
        beq     :+
        bcs     @yes                    ; pb's letter is smaller
        bra     @no
:       iny
        bra     @c
@endb:  cmp     z:la                    ; pb ended: before pa if pa is longer
        bcc     @yes
@no:    clc
        rts
@yes:   sec
        rts

; A = character -> lower case (A-Z only)
lower:  and     #$00FF
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
:       rts

; pa = record of entry X (sorted order)
rec:    txa
        asl     a
        tax
        lda     idx,x
        sta     z:pa
        lda     z:hbank
        sta     z:pa+2
        rts

; name of record pa -> fname
recname:
        ldy     #4
        lda     [pa],y
        and     #$00FF
        sta     z:tmp
        ldx     #0
        ldy     #5
        sep     #$20
        .a8
:       cpx     z:tmp
        beq     :+
        lda     [pa],y
        sta     fname,x
        inx
        iny
        bra     :-
:       lda     #0
        sta     fname,x
        rep     #$20
        .a16
        rts

; the extension of fname (X, Y) -> ext (3 letters, upper case; 0 if none)
ext_of: stz     z:ext
        stz     z:ext+2
        stx     z:pb
        tya
        sta     z:pb+2
        ldy     #0
        ldx     #$FFFF
:       lda     [pb],y
        and     #$00FF
        beq     :++
        cmp     #'.'
        bne     :+
        tyx
:       iny
        bra     :--
:       cpx     #$FFFF
        beq     @out
        stx     z:tmp
        tya
        sec
        sbc     z:tmp
        cmp     #3                      ; 2 or 3 letters after the dot
        bcc     @out
        cmp     #5
        bcs     @out
        ldy     z:tmp
        iny
        lda     [pb],y
        and     #$DFDF
        sta     z:ext
        iny
        iny
        lda     [pb],y
        and     #$00FF
        beq     @out
        and     #$00DF
        sta     z:ext+2
@out:   rts

; Z set if ext equals the 4-byte entry at txt_ext + X
ext_is: lda     txt_ext,x
        cmp     z:ext
        bne     :+
        lda     txt_ext+2,x
        and     #$00FF
        cmp     z:ext+2
:       rts

; ---------------------------------------------------------------- drawing
redraw: jsr     title
        jsr     list
        lda     z:rows                  ; the separator row
        sec
        sbc     #3
        ldx     #0
        jsr     goto
        jsr     esc_k
        jsr     status
        jsr     hints
        ; fall through
flush:  jmp     out_flush

; row 0: the folder and the number of entries, in inverse video
title:  lda     #0
        tax
        jsr     goto
        jsr     esc_p
        print   " Files: "
        ldx     #.loword(fname)
        ldy     #^fname
        lda     #128
        sys     SYS_GETCWD
        ldx     #0
        stz     z:col
:       lda     fname,x
        and     #$00FF
        beq     :+
        phx
        jsr     out_char
        plx
        inx
        cpx     #50
        bcc     :-
:       print   "  ("
        lda     z:n
        jsr     put_dec
        print   " entries"
        lda     z:trunc
        beq     :+
        print   ", more not shown"
:       print   ") "
        jsr     esc_k
        jmp     esc_q

; the list: rows 1 .. listn
list:   stz     z:row
@r:     lda     z:row
        clc
        adc     z:top
        cmp     z:n
        bcs     @empty
        jsr     line_at_i
        bra     @nx
@empty: lda     z:row
        inc     a
        ldx     #0
        jsr     goto
        jsr     esc_k
@nx:    inc     z:row
        lda     z:row
        cmp     z:listn
        bcc     @r
        rts

; line of entry A (must be on the page)
line_at:
        pha
        sec
        sbc     z:top
        sta     z:row
        pla
        ; fall through
; entry A on list row z:row (0-based)
line_at_i:
        sta     z:cur
        tax
        jsr     rec
        lda     z:row
        inc     a
        ldx     #0
        jsr     goto
        lda     z:cur
        cmp     z:sel
        bne     :+
        jsr     esc_p
:       lda     #' '
        jsr     out_char
        ldy     #4                      ; the name, cut with '>' if too long
        lda     [pa],y
        and     #$00FF
        sta     z:la
        stz     z:col
@ch:    lda     z:col
        cmp     z:la
        bcs     @pad
        inc     a
        cmp     z:namew
        bcc     :+
        lda     z:la
        cmp     z:namew
        beq     :+
        lda     #'>'
        jsr     out_char
        inc     z:col
        bra     @pad
:       lda     z:col
        clc
        adc     #5
        tay
        lda     [pa],y
        and     #$00FF
        cmp     #' '                    ; (non-ASCII names: '?')
        bcc     :+
        cmp     #$7F
        bcc     :++
:       lda     #'?'
:       jsr     out_char
        inc     z:col
        bra     @ch
@pad:   lda     z:col
        cmp     z:namew
        bcs     :+
        lda     #' '
        jsr     out_char
        inc     z:col
        bra     @pad
:       ldy     #3
        lda     [pa],y
        and     #$0010
        beq     :+
        print   "      <DIR> "
        bra     @end
:       ldy     #2                      ; size: bytes, or K from 64 KB up
        lda     [pa],y
        and     #$00FF
        beq     :+
        ldy     #1
        lda     [pa],y
        lsr     a
        lsr     a
        ldx     #10
        jsr     put_decw
        print   "K"
        bra     @end
:       lda     [pa]
        ldx     #11
        jsr     put_decw
        lda     #' '
        jsr     out_char
@end:   jsr     esc_k                   ; the last column too (a selection bar reaches it)
        lda     z:cur
        cmp     z:sel
        bne     :+
        jsr     esc_q
:       rts

; the status line: what is mounted (D1:, the executable, the cartridge)
status: jsr     goto_status
        print   " D1: "
        lda     #0
        jsr     item
        print   "  XEX: "
        lda     #4
        jsr     item
        print   "  Cart: "
        lda     #5
        jsr     item
        jmp     esc_k
goto_status:
        lda     z:rows
        sec
        sbc     #2
        ldx     #0
        jmp     goto

; mounted item A: its file name (no folders), at most 19 characters, or "-"
item:   ldx     #.loword(fname)
        ldy     #^fname
        sys     SYS_CQUERY
        cmp     #0
        bne     :+
        lda     #'-'
        jmp     out_char
:       ldx     #0                      ; after the last '/'
        ldy     #0
:       lda     fname,x
        and     #$00FF
        beq     :++
        cmp     #'/'
        bne     :+
        txy
        iny
:       inx
        bra     :--
:       ldx     #19                     ; at most 19 characters, '>' when cut
@ch:    lda     fname,y
        and     #$00FF
        beq     @done
        cpx     #1                      ; the last place: '>' if more follows
        bne     @put
        pha
        lda     fname+1,y
        and     #$00FF
        beq     @keep
        pla
        lda     #'>'
        bra     @put
@keep:  pla
@put:   phx
        phy
        jsr     out_char
        ply
        plx
        iny
        dex
        bne     @ch
@done:  rts

hints:  lda     z:rows
        dec     a
        ldx     #0
        jsr     goto
        jsr     esc_p
        print   " Enter open  Bksp up  Esc shell  arrows PgUp PgDn Home End  type to find"
        jsr     esc_k
        jmp     esc_q

; cursor to row A, column X
goto:   pha
        phx
        lda     #27
        jsr     out_char
        lda     #'Y'
        jsr     out_char
        plx
        pla
        clc
        adc     #32
        phx
        jsr     out_char
        pla
        clc
        adc     #32
        jmp     out_char

clear:  lda     #12
        jmp     out_char
esc_p:  lda     #'p'
        bra     esc
esc_q:  lda     #'q'
        bra     esc
esc_k:  lda     #'K'
        bra     esc
esc_e:  lda     #'e'
        bra     esc
esc_f:  lda     #'f'
esc:    pha
        lda     #27
        jsr     out_char
        pla
        jmp     out_char

        .segment "RODATA"
dot:    .byte   ".", 0
dotdot: .byte   "..", 0
txt_ext: .byte  "TXT", 0, "DOC", 0, "NFO", 0, "MD", 0, 0, "CFG", 0, "INI", 0, "ASC", 0, 0

        .segment "BSS"
DBUFLEN = 512
idx:    .res    MAXENT * 2
dbuf:   .res    DBUFLEN + 2
blk:    .res    10
fname:  .res    130
came:   .res    130
prefix: .res    32

        .segment "ZEROPAGE"
cols:   .res    2
rows:   .res    2
namew:  .res    2
listn:  .res    2
hbank:  .res    2
n:      .res    2
heap:   .res    2
sel:    .res    2
nsel:   .res    2
top:    .res    2
skip:   .res    2
cnt:    .res    2
dpos:   .res    2
trunc:  .res    2
new:    .res    2
lo:     .res    2
hi:     .res    2
mid:    .res    2
la:     .res    2
lb:     .res    2
pa:     .res    4
pb:     .res    4
tmp:    .res    2
key:    .res    2
msg:    .res    2
err:    .res    2
btn:    .res    2
now:    .res    2
lastclk: .res   2
lastkey: .res   2
plen:   .res    2
row:    .res    2
cur:    .res    2
col:    .res    2
lines:  .res    2
ext:    .res    4

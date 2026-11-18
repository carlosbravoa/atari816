; uicopy.s - controls library (0.20): copying, deleting and moving files and whole folders.
; A move between the card and the PC volume (/PC:, the PC link) cannot be a SYS_RENAME (the
; I/O processor answers $89, Horizon error $C9): ui_mvtree copies, then deletes the source.
; (0.21) Files are copied in pieces of 16 KB; ui_cpcb is called when a file starts and after
; every piece, and may cancel the copy (C set: ECANCELED, the partial file deleted).
; (0.22) A URL (http://, https://, ftp://: the PC link) is a source like a file: its size may
; be unknown (0), so a file is read until a short read, never to its STAT size; ui_cpblk sets
; the piece (a URL's read waits until the piece is full); ui_cpx keeps the X of a failed
; STAT or OPEN of the source (E_HTTP: the HTTP status).
; Self-contained (no zero page; it does not need ui.s): the shell links it too. See ui.inc.
        .include "horizon.inc"
        .include "ui.inc"

CP_MAXD = 48                            ; folders inside folders, at most
CP_DBL  = 400                           ; the READDIR buffer: the path (127), then entries
CP_BLK  = 16384                         ; (0.21) bytes read and written at a time: a piece

        .segment "CODE"
        .a16
        .i16

; X = from, Y = to (paths): moved (SYS_RENAME). Between the card and the PC: copied, then the
; source deleted (only when the whole copy worked: never after an error or a cancel). C set:
; A = error ($48: "to" is there; ECANCELED: ui_cpcb cancelled the copy).
ui_mvtree:
        stx     cp_a
        sty     cp_b
        stx     cp_rb
        sty     cp_rb+3
        sep     #$20
        .a8
        lda     #^cp_rb
        sta     cp_rb+2
        sta     cp_rb+5
        rep     #$20
        .a16
        ldx     #.loword(cp_rb)
        ldy     #^cp_rb
        sys     SYS_RENAME
        bcc     @out
        cmp     #EIO + $89              ; not the same volume
        bne     @err
        ldx     cp_b                    ; (there already: as SYS_RENAME says)
        jsr     cp_stat
        bcs     :+
        lda     #EIO + 8
        bra     @err
:       ldx     cp_a
        ldy     cp_b
        jsr     ui_cptree
        bcs     @out
        ldx     cp_a
        jmp     ui_rmtree
@err:   sec
@out:   rts

; X = source, Y = destination (the new name): a file copied (a file there is replaced), or a
; folder and everything in it (the destination folder must not exist). Not into itself
; (EINVAL). C set: A = error (ECANCELED: ui_cpcb cancelled); a file copied in part is
; deleted, the folders and files copied before it stay. ui_cpcb (0: none) is called when a
; file starts (ui_cpk = 0) and after each piece of 16 KB.
ui_cptree:
        phy
        ldy     #.loword(cp_src)
        jsr     cp_cpy
        ply
        jcs     @inval
        tyx
        ldy     #.loword(cp_dst)
        jsr     cp_cpy
        jcs     @inval
        jsr     cp_inside
        jcs     @inval
        sys     SYS_BALLOC
        bcc     :+
        lda     #ENOMEM
        sec
        rts
:       sta     cp_bank
        ldx     #.loword(cp_src)
        jsr     cp_stat
        stx     ui_cpx                  ; (0.22) E_HTTP: the status
        jcs     @end
        lda     cp_st+4
        and     #$0010
        bne     @tree
        lda     cp_st                   ; a file
        sta     ui_cpsize
        lda     cp_st+2
        sta     ui_cpsize+2
        jsr     cp_file
        jmp     @end
@tree:  ldx     #.loword(cp_dst)
        ldy     #^cp_dst
        sys     SYS_MKDIR
        jcs     @end
        stz     cp_d
        stz     cp_skip
@next:  ldx     cp_d                    ; the next entry of the folder at depth d
        lda     cp_skip,x
        jsr     cp_rd
        bcs     @end
        cmp     #0
        bne     @ent
        lda     cp_d                    ; the folder is done: up
        beq     @ok
        dec     cp_d
        dec     cp_d
        jsr     cp_up2
        bra     @skip
@ent:   ldx     #.loword(cp_src)
        jsr     cp_app
        bcs     @inval2
        ldx     #.loword(cp_dst)
        jsr     cp_app
        bcs     @inval2
        lda     cp_dbuf+4
        and     #$0010
        beq     @file
        ldx     #.loword(cp_dst)        ; a folder: made, then entered
        ldy     #^cp_dst
        sys     SYS_MKDIR
        bcs     @end
        lda     cp_d
        cmp     #(CP_MAXD - 1) * 2
        bcs     @inval2
        inc     a
        inc     a
        sta     cp_d
        tax
        stz     cp_skip,x
        bra     @next
@file:  lda     cp_dbuf
        sta     ui_cpsize
        lda     cp_dbuf+2
        sta     ui_cpsize+2
        jsr     cp_file
        bcs     @end
        jsr     cp_up2
@skip:  ldx     cp_d
        inc     cp_skip,x
        bra     @next
@inval2:
        lda     #EINVAL
        sec
        bra     @end
@ok:    lda     #0
        clc
@end:   php
        pha
        lda     cp_bank
        sys     SYS_BFREE
        pla
        plp
        rts
@inval: lda     #EINVAL
        sec
        rts

; X = path: a file deleted, or a folder and everything in it. C set: A = error (what could
; not be deleted stays, and what is in it)
ui_rmtree:
        ldy     #.loword(cp_src)
        jsr     cp_cpy
        bcc     :+
        lda     #EINVAL
        rts
:       stz     cp_d
@try:   ldx     #.loword(cp_src)
        ldy     #^cp_src
        sys     SYS_DELETE
        bcc     @gone
        sta     cp_err
        cmp     #EIO + 7                ; denied: a folder with something in it?
        bne     @fail
        lda     #0
        jsr     cp_rd
        bcs     @fail2
        cmp     #0
        beq     @fail2
        ldx     #.loword(cp_src)
        jsr     cp_app
        bcs     @fail2
        inc     cp_d
        bra     @try
@gone:  lda     cp_d                    ; deleted: back to the folder it was in
        beq     @ok
        dec     cp_d
        ldx     #.loword(cp_src)
        jsr     cp_up
        bra     @try
@ok:    clc
        rts
@fail2: lda     cp_err
@fail:  sec
        rts

;(0.22) X = a string -> C set if it is a URL: letters, then "://" (X = the index after it).
; Keeps Y
ui_isurl:
        stx     cp_p
:       lda     a:0,x
        and     #$00DF                  ; (upper case)
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        inx
        bra     :-
:       cpx     cp_p
        beq     @no
        lda     a:0,x
        cmp     #':' | ('/' << 8)
        bne     @no
        lda     a:2,x
        and     #$00FF
        cmp     #'/'
        bne     @no
        inx
        inx
        inx
        sec
        rts
@no:    clc
        rts

; (0.22) X = a path or URL, Y = a buffer (UI_NAMEMAX + 1 bytes) -> the name a copy of it gets
; in a folder: a path's last part (after its last '/'); a URL's last path part without its
; query ("?...") or fragment ("#..."): "index.html" when that is empty, "listing.txt" for an
; ftp:// URL (a folder's listing); characters a card name cannot hold (controls, : * " < > |
; \) become '_'; at most UI_NAMEMAX characters
ui_urlname:
        sty     cp_q
        stx     cp_s
        stz     cp_u
        jsr     ui_isurl
        bcs     @url
        ldx     cp_s                    ; a path: after its last '/'
        stx     cp_t
:       lda     a:0,x
        and     #$00FF
        beq     @fromt
        inx
        cmp     #'/'
        bne     :-
        stx     cp_t
        bra     :-
@url:   inc     cp_u                    ; the host, up to the path's first '/'
:       lda     a:0,x
        and     #$00FF
        jsr     cp_uend
        bcs     @empty                  ; no path
        cmp     #'/'
        beq     :+
        inx
        bra     :-
:       lda     a:0,x                   ; the last '/' before the end
        and     #$00FF
        jsr     cp_uend
        bcs     @fromt
        inx
        cmp     #'/'
        bne     :-
        stx     cp_t
        bra     :-
@fromt: ldx     cp_t
        ldy     cp_q
        stz     cp_n
:       lda     a:0,x
        and     #$00FF
        jsr     cp_uend
        bcs     @end
        jsr     cp_badch
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        inx
        iny
        inc     cp_n
        lda     cp_n
        cmp     #UI_NAMEMAX
        bcc     :-
@end:   sep     #$20
        .a8
        lda     #0
        sta     a:0,y
        rep     #$20
        .a16
        lda     cp_n
        bne     @out
        lda     cp_u
        beq     @out                    ; (a path ending in '/': "")
@empty: ldx     cp_s                    ; ftp://: a folder's listing
        lda     a:0,x
        and     #$00DF
        ldx     #.loword(cp_sindex)
        cmp     #'F'
        bne     :+
        ldx     #.loword(cp_slist)
:       ldy     cp_q
:       lda     a:0,x
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        inx
        iny
        and     #$00FF
        bne     :-
@out:   rts

; A = a character: C set at the end of the name's part (0; a URL's '?', '#'). Keeps A, X, Y
cp_uend:
        cmp     #0
        beq     @y
        pha
        lda     cp_u
        beq     @n
        pla
        cmp     #'?'
        beq     @y
        cmp     #'#'
        beq     @y
        clc
        rts
@n:     pla
        clc
        rts
@y:     sec
        rts

; A = a character -> A, '_' if a card name cannot hold it. Keeps X, Y
cp_badch:
        cmp     #' '
        bcc     @bad
        phx
        ldx     #0
:       cmp     cp_bads,x
        beq     :+
        inx
        cpx     #7
        bcc     :-
        plx
        rts
:       plx
@bad:   lda     #'_'
        rts

; ---- helpers
; copy cp_src to cp_dst (new; replaced if a file is there) through cp_bank. C set: A = error
; (the half copy deleted; ECANCELED: ui_cpcb said so)
cp_file:
        ldx     #.loword(cp_src)        ; ui_cpname: the name after the last '/'
        stx     ui_cpname
:       lda     a:0,x
        and     #$00FF
        beq     :++
        inx
        cmp     #'/'
        bne     :+
        stx     ui_cpname
:       bra     :--
:       stz     ui_cpk
        stz     cp_done
        stz     cp_done+2
        jsr     cp_call                 ; (0.21) a file starts: the name can be shown
        bcc     :+
        lda     #ECANCELED
        rts
:       ldx     #.loword(cp_src)
        ldy     #^cp_src
        lda     #O_READ
        sys     SYS_OPEN
        stx     ui_cpx                  ; (0.22) E_HTTP: the status
        bcs     @r
        sta     cp_h1
        ldx     #.loword(cp_dst)
        ldy     #^cp_dst
        lda     #O_CREATE
        sys     SYS_OPEN
        bcc     :+
        pha
        lda     cp_h1
        sys     SYS_CLOSE
        pla
        sec
@r:     rts
:       sta     cp_h2
@lp:    lda     cp_h1                   ; read a piece (up to ui_cpblk: 16 KB)
        jsr     cp_rw
        lda     ui_cpblk
        sta     cp_rwb+4
        ldx     #.loword(cp_rwb)
        ldy     #^cp_rwb
        sys     SYS_READ
        bcs     @e
        cmp     #0
        beq     @done
        sta     cp_rwb+4
        sta     cp_n
        sta     cp_got
        lda     cp_h2                   ; and write them
        jsr     cp_rw
        ldx     #.loword(cp_rwb)
        ldy     #^cp_rwb
        sys     SYS_WRITE
        bcs     @e
        cmp     cp_n
        beq     :+
        lda     #$01FF                  ; (fewer: the volume is full)
        bra     @e
:       clc                             ; ui_cpk = the K copied (rounded up)
        adc     cp_done
        sta     cp_done
        bcc     :+
        inc     cp_done+2
:       jsr     cp_kset
        jsr     cp_call
        bcs     :+
        lda     cp_got                  ; (0.22) a short read: the end (a URL's size may be
        cmp     ui_cpblk                ; unknown; reading after its end is not needed)
        bcs     @lp
        bra     @done
:       lda     #ECANCELED              ; cancelled: as an error (the half copy deleted)
@e:     sta     cp_err
        lda     cp_h2
        sys     SYS_CLOSE
        lda     cp_h1
        sys     SYS_CLOSE
        ldx     #.loword(cp_dst)        ; no half copy left
        ldy     #^cp_dst
        sys     SYS_DELETE
        lda     cp_err
        sec
        rts
@done:  lda     cp_h2
        sys     SYS_CLOSE
        php
        pha
        lda     cp_h1
        sys     SYS_CLOSE
        pla
        plp
        rts

; (0.21) ui_cpk = (cp_done + 1023) / 1024
cp_kset:
        lda     cp_done
        clc
        adc     #1023
        sta     cp_n
        lda     cp_done+2
        adc     #0
        asl     a                       ; high word << 6
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        sta     cp_p
        lda     cp_n                    ; | low word >> 10
        xba
        and     #$00FF
        lsr     a
        lsr     a
        ora     cp_p
        sta     ui_cpk
        rts

; (0.21) call ui_cpcb (if any) -> C set: cancel
cp_call:
        lda     ui_cpcb
        beq     :+
        ldx     #0
        jmp     (ui_cpcb,x)
:       clc
        rts

; the read / write block: handle A, buffer cp_bank:0000 (the length set after)
cp_rw:  sep     #$20
        .a8
        sta     cp_rwb
        lda     cp_bank
        sta     cp_rwb+3
        rep     #$20
        .a16
        stz     cp_rwb+1
        rts

; X = string -> Y = buffer (zero-terminated); C set if longer than 127
cp_cpy: stz     cp_n
:       lda     a:0,x
        and     #$00FF
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        beq     :+
        inx
        iny
        inc     cp_n
        bra     :-
:       lda     cp_n
        cmp     #128
        rts

; C set if cp_dst is cp_src or inside it (ignoring case)
cp_inside:
        ldx     #0
:       lda     cp_src,x
        and     #$00FF
        beq     :+
        jsr     cp_lower
        sta     cp_n
        lda     cp_dst,x
        jsr     cp_lower
        cmp     cp_n
        bne     @no
        inx
        bra     :-
:       lda     cp_dst,x                ; cp_src ended: the same, or a '/' (not after a '/')
        and     #$00FF
        beq     @yes
        cmp     #'/'
        bne     @no
@yes:   sec
        rts
@no:    clc
        rts

cp_lower:
        and     #$00FF
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
:       rts

; X = path -> cp_st (STAT). C set: A = error
cp_stat:
        stx     cp_sb
        lda     #.loword(cp_st)
        sta     cp_sb+3
        sep     #$20
        .a8
        lda     #^cp_st
        sta     cp_sb+2
        sta     cp_sb+5
        rep     #$20
        .a16
        ldx     #.loword(cp_sb)
        ldy     #^cp_sb
        sys     SYS_STAT
        rts

; READDIR of cp_src, skipping A entries -> A = entries (the first one at cp_dbuf). C set: error
cp_rd:  sta     cp_db+8
        lda     #.loword(cp_src)
        sta     cp_db
        lda     #.loword(cp_dbuf)
        sta     cp_db+3
        lda     #CP_DBL
        sta     cp_db+6
        sep     #$20
        .a8
        lda     #^cp_src
        sta     cp_db+2
        sta     cp_db+5
        rep     #$20
        .a16
        ldx     #.loword(cp_db)
        ldy     #^cp_db
        sys     SYS_READDIR
        rts

; X = path buffer: '/' and the name of the entry at cp_dbuf appended. C set: longer than 127
cp_app: stx     cp_p
:       lda     a:0,x                   ; its end
        and     #$00FF
        beq     :+
        inx
        bra     :-
:       lda     cp_dbuf+5               ; the name's length
        and     #$00FF
        sta     cp_n
        txa
        sec
        sbc     cp_p
        sec                             ; + '/' + the name (+ 1: C set above 127)
        adc     cp_n
        cmp     #128
        bcs     @out
        dex                             ; (no second '/' after the root)
        lda     a:0,x
        inx
        and     #$00FF
        cmp     #'/'
        beq     :+
        lda     #'/'
        sep     #$20
        .a8
        sta     a:0,x
        rep     #$20
        .a16
        inx
:       ldy     #0
        sep     #$20
        .a8
:       cpy     cp_n
        beq     :+
        lda     cp_dbuf+6,y
        sta     a:0,x
        inx
        iny
        bra     :-
:       stz     a:0,x
        rep     #$20
        .a16
        clc
@out:   rts

; both paths one folder up
cp_up2: ldx     #.loword(cp_src)
        jsr     cp_up
        ldx     #.loword(cp_dst)
        ; fall through
; X = path buffer: cut at its last '/' (a '/' that is the first character stays)
cp_up:  stx     cp_p
        ldy     #$FFFF
:       lda     a:0,x
        and     #$00FF
        beq     :++
        cmp     #'/'
        bne     :+
        txy
:       inx
        bra     :--
:       cpy     #$FFFF
        beq     @out
        cpy     cp_p
        bne     :+
        iny                             ; "/name": "/"
:       tyx
        sep     #$20
        .a8
        stz     a:0,x
        rep     #$20
        .a16
@out:   rts

        .segment "RODATA"
cp_sindex: .byte "index.html", 0
cp_slist: .byte "listing.txt", 0
cp_bads: .byte  ":*\"<>|\\"

        .segment "DATA"
ui_cpcb: .word  0                       ; called when a file starts and after each 16 KB
                                        ; copied (0: none); C set on return: cancel
ui_cpblk: .word CP_BLK                  ; (0.22) the piece: bytes read and written at a time

        .segment "BSS"
ui_cpname: .res 2                       ; the name of the file being copied (in cp_src)
ui_cpk:  .res   2                       ; K of it copied so far
cp_done: .res   4                       ; (0.21) bytes of it copied so far
ui_cpsize: .res 4                       ; its size
ui_cpx:  .res   2                       ; (0.22) X of the last STAT / OPEN of a source (E_HTTP: the status)
cp_src: .res    130
cp_dst: .res    130
cp_dbuf: .res   CP_DBL
cp_st:  .res    10
cp_skip: .res   CP_MAXD * 2
cp_sb:  .res    6
cp_db:  .res    10
cp_rb:  .res    6
cp_rwb: .res    6
cp_a:   .res    2
cp_b:   .res    2
cp_d:   .res    2
cp_n:   .res    2
cp_got: .res    2
cp_q:   .res    2
cp_s:   .res    2
cp_t:   .res    2
cp_u:   .res    2
cp_p:   .res    2
cp_h1:  .res    2
cp_h2:  .res    2
cp_bank: .res   2
cp_err: .res    2

; uiopen.s - controls library: starting programs and opening files by their type
; (ui_launch, ui_spawnerr, ui_ftype, ui_open). One table of file types for Files and the
; Desktop. See ui.inc.
        .include "horizon.inc"
        .include "ui.inc"
        .include "icons.inc"

NAMEMAX = 40                            ; a name in a message (longer: cut)
TITLEMAX = 18                           ; in a title ("Cannot start " + 18 = 31)

        .segment "CODE"
        .a16
        .i16

; X = program path, Y = argument string (0: none), A = its name for messages (0: from the
; path) -> C clear: started (or a single-instance one runs already: raised); C set: the
; alert was shown, A = the error
ui_launch:
        stx     op_prg
        sty     op_arg
        sta     op_name
        cmp     #0
        bne     :+
        ldx     op_prg                  ; (0.14: a known program's own name)
        jsr     ui_prog
        stx     op_name
        cpx     #0
        bne     :+
        jsr     op_pname
:       lda     op_arg
        sta     z:u_arg
        beq     :+
        lda     #^op_nbuf
:       sta     z:u_arg+2
        ldx     op_prg
        ldy     #^op_nbuf
        lda     #1 | SP_DETACH
        jsr     spawn
        bcc     @named
        cmp     #ERUNNING
        beq     @req
        pha
        ldx     op_name
        jsr     ui_spawnerr
        pla
        sec
        rts
@named: ldx     op_name                 ; (0.14) the menu bar shows its name
        ldy     #^op_nbuf
        sys     SYS_TNAME
@ok:    clc
        rts
@req:   lda     op_arg                  ; (0.26) a single-instance program runs already: an
        beq     @ok                     ; argument goes to it through /SYSTEM/OPEN.REQ
        jsr     op_request
        clc
        rts

; (0.26) /SYSTEM/OPEN.REQ written: op_prg, LF, op_arg, LF (the running program reads it when
; its window gets the focus, or within a second, and deletes it: Music)
op_request:
        ldx     op_prg
        ldy     #.loword(op_lbuf)
        jsr     ui_strcpy
        clc
        adc     #.loword(op_lbuf)
        tay
        lda     #10
        sta     a:0,y
        iny
        tya
        pha
        ldx     op_arg
        jsr     ui_strcpy
        sta     op_t
        pla
        clc
        adc     op_t
        tay
        lda     #10
        sta     a:0,y
        iny
        sty     op_end
        ptr     p_req
        lda     #O_CREATE
        sys     SYS_OPEN
        bcs     @out
        sta     op_t
        sta     op_rw
        lda     #.loword(op_lbuf)
        sta     op_rw+1
        lda     #^op_lbuf
        sta     op_rw+3
        lda     op_end
        sec
        sbc     #.loword(op_lbuf)
        sta     op_rw+4
        ptr     op_rw
        sys     SYS_WRITE
        lda     op_t
        sys     SYS_CLOSE
@out:   rts

; A = a spawn error, X = the program's name: a warning alert saying why it did not start
ui_spawnerr:
        sta     op_err
        stx     op_name
        ldx     #.loword(m_other)
        lda     op_err
        cmp     #ENOMEM
        bne     :+
        ldx     #.loword(m_nomem)
:       cmp     #EAGAIN
        bne     :+
        ldx     #.loword(m_again)
:       cmp     #EINVAL
        bne     :+
        ldx     #.loword(m_inval)
:       cmp     #$44
        beq     :+
        cmp     #$45
        bne     :++
:       ldx     #.loword(m_notf)
:       ldy     #.loword(t_start)
; the alert: message template X, title template Y (with op_name, op_err)
op_alert:
        phy
        ldy     #.loword(op_msg)
        lda     #NAMEMAX
        jsr     op_fmt
        plx
        ldy     #.loword(op_title)
        lda     #TITLEMAX
        jsr     op_fmt
        ldx     #.loword(op_al)
        jmp     ui_alert

; X = a file name or path -> A = its type FT_* by the extension (never FT_FOLDER)
ui_ftype:
        stx     op_t
        ldy     #^op_nbuf
        jsr     atari_kind
        cmp     #0
        beq     :+
        lda     #FT_ATARI
        rts
:       ldx     op_t                    ; the last '.' after the last '/'
        stz     op_dot
:       lda     a:0,x
        and     #$00FF
        beq     :+++
        cmp     #'/'
        bne     :+
        stz     op_dot
:       cmp     #'.'
        bne     :+
        stx     op_dot
:       inx
        bra     :---
:       ldx     op_dot
        beq     @none
        ldy     #0                      ; the extension, upper case (at most 4 letters)
:       inx
        lda     a:0,x
        and     #$00FF
        cmp     #'a'
        bcc     :+
        cmp     #'z' + 1
        bcs     :+
        and     #$00DF
:       sep     #$20
        .a8
        sta     op_ext,y
        rep     #$20
        .a16
        cmp     #0
        beq     :+
        iny
        cpy     #5
        bcc     :--
        bra     @none
:       ldx     #0                      ; the table: "EXT", 0, type
@ent:   lda     ft_tab,x
        and     #$00FF
        beq     @none
        ldy     #0
@c:     lda     ft_tab,x
        and     #$00FF
        sta     op_t
        lda     op_ext,y
        and     #$00FF
        cmp     op_t
        bne     @skip
        inx
        iny
        cmp     #0
        bne     @c
        lda     ft_tab,x
        and     #$00FF
        rts
@skip:  lda     ft_tab,x                ; to the next entry
        and     #$00FF
        beq     :+
        inx
        bra     @skip
:       inx
        inx
        bra     @ent
@none:  lda     #FT_OTHER
        rts

; X = the full path of a file or folder: opened by its type -> C clear: opened (started);
; C set: not (an alert said why)
ui_open:
        stx     op_path
        jsr     op_base                 ; its name (after the last '/')
        stx     op_name
        jsr     op_isdir
        bcc     @file
        ldx     op_path                 ; a folder: Files there
        jsr     op_quote
        ldx     #.loword(p_files)
        ldy     #.loword(op_abuf)
        lda     #.loword(n_files)
        jmp     ui_launch
@file:  ldx     op_path
        jsr     ui_ftype
        sta     op_type
        cmp     #FT_LINK
        jeq     op_link
        cmp     #FT_ATARI
        bne     @prg
        ldx     op_path                 ; Atari software: start this, and only this
        ldy     #^op_nbuf
        jsr     atari_run
        jcc     @ok
        sta     op_err
        ldx     #.loword(m_aerr)
        cmp     #$C4
        bne     :+
        ldx     #.loword(m_aimg)
:       cmp     #$C5
        bne     :+
        ldx     #.loword(m_aiop)
:       cmp     #ENOMEM                 ; (0.18) no room for the cartridge's banks
        bne     :+
        ldx     #.loword(m_anom)
:       ldy     #.loword(t_open)
        jsr     op_alert
        sec
        rts
@prg:   cmp     #FT_PRG
        bne     @data
        ldx     op_path                 ; a program: not one of the system's
        ldy     #0
:       lda     a:0,x
        and     #$00FF
        cmp     #'a'
        bcc     :+
        cmp     #'z' + 1
        bcs     :+
        and     #$00DF
:       sta     op_t
        lda     s_sys,y
        and     #$00FF
        beq     @sysp
        cmp     op_t
        bne     @run
        inx
        iny
        bra     :--
@sysp:  ldx     #.loword(m_sys)
        ldy     #.loword(t_open)
        jsr     op_alert
        sec
        rts
@run:   ldx     op_path
        ldy     #0
        lda     #0
        jmp     ui_launch
@data:  cmp     #FT_OTHER
        bne     :+
        ldx     #.loword(m_noprog)      ; nothing opens it
        ldy     #.loword(t_open)
        jsr     op_alert
        sec
        rts
:       ldx     op_path                 ; its program, with the path
        jsr     op_quote
        lda     op_type
        asl     a
        tax
        lda     ft_name,x
        pha
        lda     ft_prog,x
        tax
        ldy     #.loword(op_abuf)
        pla
        jmp     ui_launch
@ok:    clc
        rts

; X = path -> X = its name (after the last '/')
op_base:
        txy
:       lda     a:0,x
        and     #$00FF
        beq     :++
        inx
        cmp     #'/'
        bne     :+
        txy
:       bra     :--
:       tyx
        rts

; op_path a folder? -> C set
op_isdir:
        ldx     op_path
        lda     a:0,x                   ; "/": the root
        cmp     #'/'
        beq     @yes
        stx     op_sblk
        lda     #^op_nbuf
        sta     op_sblk+2
        lda     #.loword(op_st)
        sta     op_sblk+3
        lda     #^op_st
        sta     op_sblk+5
        ptr     op_sblk
        sys     SYS_STAT
        bcs     @no
        lda     op_st+4
        and     #$0010
        beq     @no
@yes:   sec
        rts
@no:    clc
        rts

; op_abuf = string X in quotes (at most 127 characters of it)
op_quote:
        lda     #'"'
        sta     op_abuf
        ldy     #1
:       lda     a:0,x
        and     #$00FF
        beq     :+
        cpy     #128
        bcs     :+
        sep     #$20
        .a8
        sta     op_abuf,y
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       lda     #'"'                    ; ('"', 0)
        sta     op_abuf,y
        rts

; the program's name from its path op_prg: the file name without its extension, capitalised
; ("/BIN/PAINT.PRG": "Paint") -> op_name = op_nbuf
op_pname:
        ldx     op_prg
        jsr     op_base
        ldy     #0
:       lda     a:0,x
        and     #$00FF
        beq     :+++
        cmp     #'.'
        beq     :+++
        cmp     #'A'                    ; lower case after the first
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        cpy     #0
        beq     :++
        ora     #$20
        bra     :++
:       cmp     #'a'                    ; the first upper case
        bcc     :+
        cmp     #'z' + 1
        bcs     :+
        cpy     #0
        bne     :+
        and     #$00DF
:       sep     #$20
        .a8
        sta     op_nbuf,y
        rep     #$20
        .a16
        inx
        iny
        cpy     #NAMEMAX
        bcc     :---
:       lda     #0
        sep     #$20
        .a8
        sta     op_nbuf,y
        rep     #$20
        .a16
        lda     #.loword(op_nbuf)
        sta     op_name
        rts

; template X -> Y: '%' the name op_name (at most A characters), '#' op_err in hex
op_fmt: sta     op_nmax
        stx     z:ui_t0
        sty     z:ui_t1
@c:     lda     (ui_t0)
        and     #$00FF
        inc     z:ui_t0
        cmp     #'%'
        beq     @name
        cmp     #'#'
        beq     @hex
        jsr     @put
        cmp     #0
        bne     @c
        rts
@name:  ldx     op_name
        ldy     op_nmax
:       lda     a:0,x
        and     #$00FF
        beq     @c
        dey
        bmi     @c
        jsr     @put
        inx
        bra     :-
@hex:   lda     op_err
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @dig
        lda     op_err
        jsr     @dig
        bra     @c
@dig:   and     #$000F
        tax
        lda     hexd,x
@put:   sep     #$20
        .a8
        sta     (ui_t1)
        rep     #$20
        .a16
        inc     z:ui_t1
        rts

; (0.14) a shortcut (op_path, a .LNK): its target opened (a folder: Files there; a program:
; started with the link's arguments and title; a file: by its type)
op_link:
        ldx     op_path
        jsr     ui_lnkread
        bcc     :+
        ldx     #.loword(m_link)
        ldy     #.loword(t_open)
        jsr     op_alert
        sec
        rts
:       ldx     #.loword(ui_lktgt)
        jsr     ui_ftype
        cmp     #FT_LINK                ; (no link to a link)
        beq     :+
        cmp     #FT_PRG
        bne     @open
        ldx     #.loword(ui_lktgt)      ; a program: its arguments, its title
        stx     op_path
        lda     ui_lkargs
        and     #$00FF
        beq     :+
        lda     #.loword(ui_lkargs)
:       tay
        lda     ui_lktitl
        and     #$00FF
        beq     :+
        lda     #.loword(ui_lktitl)
:       ldx     #.loword(ui_lktgt)
        jmp     ui_launch
@open:  ldx     #.loword(ui_lktgt)
        jmp     ui_open

; X = the path of a .LNK -> ui_lktgt (the target path), ui_lktitl, ui_lkargs ("" if none).
; C set: not readable or no target. The file: lines of text; the first that starts with
; '/' is the target, "title=..." and "args=..." are optional, '#' starts a comment.
ui_lnkread:
        sep     #$20
        .a8
        stz     ui_lktgt
        stz     ui_lktitl
        stz     ui_lkargs
        rep     #$20
        .a16
        ldy     #^op_nbuf
        lda     #O_READ
        sys     SYS_OPEN
        jcs     @no
        sta     op_t
        sta     op_rw
        lda     #.loword(op_lbuf)
        sta     op_rw+1
        lda     #^op_lbuf
        sta     op_rw+3
        lda     #LBUFL - 1
        sta     op_rw+4
        ptr     op_rw
        sys     SYS_READ
        php
        pha
        lda     op_t
        sys     SYS_CLOSE
        pla
        plp
        bcs     @no
        tax
        sep     #$20
        .a8
        stz     op_lbuf,x
        rep     #$20
        .a16
        ldx     #.loword(op_lbuf)
@line:  lda     a:0,x                   ; a line
        and     #$00FF
        beq     @end
        cmp     #'/'
        bne     :+
        ldy     #.loword(ui_lktgt)
        bra     @val
:       ldy     #0                      ; "title=", "args="
        jsr     @key
        bcs     @skip
@val:   lda     #127                    ; copy to the end of the line
        sta     op_nmax
:       lda     a:0,x
        and     #$00FF
        cmp     #' '
        bcc     :+
        dec     op_nmax
        bmi     :+
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       sep     #$20
        .a8
        lda     #0
        sta     a:0,y
        rep     #$20
        .a16
@skip:  lda     a:0,x                   ; to the next line
        and     #$00FF
        beq     @end
        inx
        cmp     #10
        bne     @skip
        bra     @line
@end:   lda     ui_lktgt
        and     #$00FF
        beq     @no
        clc
        rts
@no:    sec
        rts
; X = a line: "title=" -> Y = ui_lktitl, "args=" -> ui_lkargs, X past the '='; C set: neither
@key:   phx
        ldy     #.loword(s_title)
        jsr     @pre
        bcc     :+
        plx
        phx
        ldy     #.loword(s_args)
        jsr     @pre
        bcc     :++
        plx
        sec
        rts
:       pla
        ldy     #.loword(ui_lktitl)
        clc
        rts
:       pla
        ldy     #.loword(ui_lkargs)
        clc
        rts
; the prefix Y at X (ignoring case)? C clear: yes, X past it
@pre:   lda     a:0,y
        and     #$00FF
        bne     :+
        clc
        rts
:       sta     op_t
        lda     a:0,x
        and     #$00FF
        cmp     #'a'
        bcc     :+
        cmp     #'z' + 1
        bcs     :+
        and     #$00DF
:       cmp     op_t
        bne     :+
        inx
        iny
        bra     @pre
:       sec
        rts

; X = a program's path -> X = its name ("Calculator"; 0: not one of Horizon's own), A = its
; icon (ICO_*; ICO_PROGRAM for the others)
ui_prog:
        jsr     op_base                 ; the file name, upper case, without its extension
        ldy     #0
:       lda     a:0,x
        and     #$00FF
        beq     :++
        cmp     #'.'
        beq     :++
        cmp     #'a'
        bcc     :+
        cmp     #'z' + 1
        bcs     :+
        and     #$00DF
:       sep     #$20
        .a8
        sta     op_ext,y
        rep     #$20
        .a16
        inx
        iny
        cpy     #8
        bcc     :--
:       lda     #0
        sta     op_ext,y
        ldx     #0                      ; the table: "FILE", 0, icon, "Name", 0
@ent:   lda     pg_tab,x
        and     #$00FF
        beq     @none
        ldy     #0
@c:     lda     pg_tab,x
        and     #$00FF
        sta     op_t
        lda     op_ext,y
        and     #$00FF
        cmp     op_t
        bne     @skip
        inx
        iny
        cmp     #0
        bne     @c
        lda     pg_tab,x                ; found: the icon, the name
        and     #$00FF
        pha
        txa
        sec
        adc     #.loword(pg_tab)
        tax
        pla
        rts
@skip:  lda     pg_tab,x                ; to the next entry: past the file, icon, name
        inx
        and     #$00FF
        bne     @skip
        inx
:       lda     pg_tab,x
        inx
        and     #$00FF
        bne     :-
        bra     @ent
@none:  ldx     #0
        lda     #ICO_PROGRAM
        rts

; X = a path, A = 1 if it is a folder -> A = its icon (ICO_*: a folder, a program by
; ui_prog, a document by its type, an Atari file by its kind; a .LNK: ICO_DOC)
ui_ficon:
        cmp     #0
        beq     :+
        lda     #ICO_FOLDER
        rts
:       stx     op_path
        ldy     #^op_nbuf
        jsr     atari_kind
        cmp     #0
        beq     :+
        clc
        adc     #ICO_DISK - 1
        rts
:       ldx     op_path
        jsr     ui_ftype
        cmp     #FT_PRG
        bne     :+
        ldx     op_path
        jmp     ui_prog
:       tax
        lda     ft_icon,x
        and     #$00FF
        rts

; X = a path: a shortcut to it in /Desktop ("NAME.LNK": a program by its own name, else the
; file or folder name; " 2" .. " 9" when taken). C set: not made.
ui_mklink:
        stx     op_path
        lda     #.loword(op_lbuf)       ; the link's text: the target, a title for programs
        sta     op_t
        ldy     #.loword(op_lbuf)
        jsr     ui_strcpy
        clc
        adc     #.loword(op_lbuf)
        tay
        lda     #10
        sta     a:0,y
        iny
        sty     op_end
        ldx     op_path
        jsr     ui_ftype
        cmp     #FT_PRG
        bne     @file
        ldx     op_path
        jsr     ui_prog
        cpx     #0
        beq     @file
        stx     op_name
        ldx     #.loword(s_tl)          ; "title=Name", 10
        ldy     op_end
        jsr     ui_strcpy
        clc
        adc     op_end
        sta     op_t
        tay
        ldx     op_name
        jsr     ui_strcpy
        clc
        adc     op_t
        tay
        lda     #10
        sta     a:0,y
        iny
        sty     op_end
        ldx     op_name                 ; its file: the program's name
        bra     @nm
@file:  ldx     op_path
        jsr     op_base
        lda     a:0,x                   ; (the root: "SD card")
        and     #$00FF
        bne     @nm
        ldx     #.loword(s_sd)
@nm:    stx     op_name
        lda     #'1'                    ; the name: "/Desktop/" + name (+ " N") + ".LNK"
        sta     op_err
@try:   ldx     #.loword(s_desk)
        ldy     #.loword(op_abuf)
        jsr     ui_strcpy
        clc
        adc     #.loword(op_abuf)
        tay
        ldx     op_name
:       lda     a:0,x                   ; (at most 100 characters of it)
        and     #$00FF
        beq     :+
        cpy     #.loword(op_abuf + 109)
        bcs     :+
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       lda     op_err
        cmp     #'1'
        beq     :+
        lda     #' '
        sta     a:0,y
        iny
        lda     op_err
        sta     a:0,y
        iny
:       ldx     #.loword(s_lnk)
        jsr     ui_strcpy
        lda     #.loword(op_abuf)       ; there already? the next number
        sta     op_sblk
        lda     #^op_nbuf
        sta     op_sblk+2
        lda     #.loword(op_st)
        sta     op_sblk+3
        lda     #^op_st
        sta     op_sblk+5
        ptr     op_sblk
        sys     SYS_STAT
        bcs     @new
        inc     op_err
        lda     op_err
        cmp     #'9' + 1
        bcc     @try
        sec
        rts
@new:   ptr     op_abuf
        lda     #O_CREATE
        sys     SYS_OPEN
        bcs     @out
        sta     op_t
        sta     op_rw
        lda     #.loword(op_lbuf)
        sta     op_rw+1
        lda     #^op_lbuf
        sta     op_rw+3
        lda     op_end
        sec
        sbc     #.loword(op_lbuf)
        sta     op_rw+4
        ptr     op_rw
        sys     SYS_WRITE
        php
        lda     op_t
        sys     SYS_CLOSE
        plp
@out:   rts


; (0.15) X = an Atari file's path: loaded into the Atari by its kind: a disk on the first
; empty drive (D1: counts as taken while an executable is loaded: it is its boot disk; all
; taken: D1:) or an executable, nothing booted; (0.18) a cartridge is a power cycle, as on
; a real machine: the executable ejected (it cannot boot with a cartridge; the disks stay),
; the cartridge mounted, the classic machine cold booted without being shown (classic_boot
; CB_STAY) -> C clear: A = the kind mounted; C set: A = 0 not an Atari file, else the error
; of classic_mount (ENOMEM: no room for the cartridge) or classic_boot
ui_atload:
        stx     op_at
        ldy     #^op_at
        jsr     atari_kind
        cmp     #0
        bne     :+
        sec
        rts
:       sta     op_atk
        cmp     #CK_DISK
        bne     @go
        stz     op_ats                  ; the first empty drive
        lda     #4
        ptr     op_qb
        sys     SYS_CQUERY
        bcs     :+
        cmp     #0
        beq     :+
        inc     op_ats
:       lda     op_ats
        ptr     op_qb
        sys     SYS_CQUERY
        bcs     :+
        cmp     #0
        beq     :+
        inc     op_ats
        lda     op_ats
        cmp     #4
        bcc     :-
        stz     op_ats
:       lda     op_ats
        xba
        ora     op_atk
        sta     op_atk
        bra     @go2
@go:    cmp     #CK_CART
        bne     @go2
        lda     #CK_XEX                 ; (0.18) a cartridge: no executable
        sys     SYS_CEJECT
@go2:   ldx     op_at
        ldy     #^op_at
        lda     op_atk
        sys     SYS_CMOUNT
        bcs     @out
        cmp     #CK_CART
        bne     @ok
        lda     #CB_STAY                ; switched off and on, the desktop stays
        sys     SYS_CBOOT
        bcs     @out
        lda     #CK_CART
@ok:    clc
@out:   rts

        .segment "RODATA"
; (0.14) Horizon's programs: "FILE", 0, its icon, "Name", 0
pg_tab: .byte   "EDIT", 0, ICO_EDIT, "Edit", 0, "WRITE", 0, ICO_WRITE, "Write", 0
        .byte   "SHEET", 0, ICO_SHEET, "Sheet", 0, "PAINT", 0, ICO_PAINT, "Paint", 0
        .byte   "BASIC", 0, ICO_BASIC, "BASIC", 0, "CALC", 0, ICO_CALC, "Calculator", 0
        .byte   "SOLITAIR", 0, ICO_SOLITAIRE, "Solitaire", 0, "TERM", 0, ICO_TERMINAL, "Terminal", 0
        .byte   "WFILES", 0, ICO_FILES, "Files", 0, "SETTINGS", 0, ICO_SETTINGS, "Settings", 0
        .byte   "FREECELL", 0, ICO_FREECELL, "FreeCell", 0
        .byte   "MUSIC", 0, ICO_MUSIC, "Music", 0
        .byte   "ABOUT", 0, ICO_ABOUT, "About", 0, 0
; the icon of each type (FT_* order)
ft_icon: .byte  ICO_DOC, ICO_FOLDER, ICO_DISK, ICO_PROGRAM, ICO_TEXT, ICO_BASDOC, ICO_PICTURE
        .byte   ICO_SHEETDOC, ICO_WRITEDOC, ICO_DOC, ICO_MUSICDOC
s_title: .byte  "TITLE=", 0
s_args: .byte   "ARGS=", 0
s_tl:   .byte   "title=", 0
s_desk: .byte   "/Desktop/", 0
s_lnk:  .byte   ".LNK", 0
s_sd:   .byte   "SD card", 0
m_link: .byte   "The shortcut % is damaged.", 10, "It does not name a file.", 0
; the types by extension: "EXT", 0, FT_*
ft_tab: .byte   "LNK", 0, FT_LINK, "PRG", 0, FT_PRG, "BAS", 0, FT_BASIC, "PIC", 0, FT_PICTURE
        .byte   "SHT", 0, FT_SHEET, "CSV", 0, FT_SHEET, "MD", 0, FT_WRITE
        .byte   "TXT", 0, FT_TEXT, "DOC", 0, FT_TEXT, "NFO", 0, FT_TEXT, "CFG", 0, FT_TEXT
        .byte   "INI", 0, FT_TEXT, "ASC", 0, FT_TEXT, "LOG", 0, FT_TEXT, "S", 0, FT_TEXT
        .byte   "INC", 0, FT_TEXT, "ASM", 0, FT_TEXT
        .byte   "LST", 0, FT_TEXT       ; (0.23) a BASIC listing (LIST "D:..." on the Atari: $9B line ends)
        .byte   "MOD", 0, FT_MUSIC, "WAV", 0, FT_MUSIC  ; (0.26) Music
        .byte   "MID", 0, FT_MUSIC                      ; (REV $0C) OPL2 MIDI
        .byte   0
; the program of each type (FT_* order) and its name for messages
ft_prog: .addr  0, p_files, 0, 0, p_edit, p_basic, p_paint, p_sheet, p_write, 0, p_music
ft_name: .addr  0, n_files, 0, 0, n_edit, n_basic, n_paint, n_sheet, n_write, 0, n_music
p_files: .byte  "/BIN/WFILES.PRG", 0
p_edit: .byte   "/BIN/EDIT.PRG", 0
p_basic: .byte  "/BIN/BASIC.PRG", 0
p_paint: .byte  "/BIN/PAINT.PRG", 0
p_sheet: .byte  "/BIN/SHEET.PRG", 0
p_write: .byte  "/BIN/WRITE.PRG", 0
p_music: .byte  "/BIN/MUSIC.PRG", 0
p_req:  .byte   "/SYSTEM/OPEN.REQ", 0
n_files: .byte  "Files", 0
n_edit: .byte   "Edit", 0
n_basic: .byte  "BASIC", 0
n_paint: .byte  "Paint", 0
n_sheet: .byte  "Sheet", 0
n_write: .byte  "Write", 0
n_music: .byte  "Music", 0
s_sys:  .byte   "/SYSTEM/", 0
s_ok:   .byte   "OK", 0
hexd:   .byte   "0123456789ABCDEF"
t_start: .byte  "Cannot start %", 0
t_open: .byte   "Cannot open", 0
m_nomem: .byte  "Not enough memory to start %.", 10, "Close a program and try again.", 0
m_again: .byte  "Too many programs are running to start %.", 10
        .byte   "Close a program and try again.", 0
m_notf: .byte   "% was not found on the card.", 0
m_inval: .byte  "% is not a Horizon program,", 10, "or its file is damaged.", 0
m_other: .byte  "% could not be started", 10, "(error $#).", 0
m_sys:  .byte   "% is a system program.", 10, "It can only be started by Horizon.", 0
m_noprog: .byte "There is no program for %.", 0
m_aimg: .byte   "% is not a valid or supported", 10, "Atari image.", 0
m_aiop: .byte   "% could not be started: the firmware", 10
        .byte   "menu is open. Close it and try again.", 0
m_aerr: .byte   "% could not be started", 10, "(error $#).", 0
m_anom: .byte   "% could not be started: not enough free", 10
        .byte   "memory for the cartridge. Close a program", 10, "and try again.", 0

        .segment "DATA"
op_al:  .word   1, op_title, op_msg, s_ok, 0, 0

        .segment "BSS"
op_at:  .res    2                       ; ui_atload: the path, the kind | slot << 8, the slot
op_atk: .res    2
op_ats: .res    2
op_qb:  .res    130
op_prg: .res    2
op_arg: .res    2
op_name: .res   2
op_err: .res    2
op_path: .res   2
op_type: .res   2
op_t:   .res    2
op_dot: .res    2
op_nmax: .res   2
op_ext: .res    6
op_nbuf: .res   NAMEMAX + 2
op_abuf: .res   132
op_title: .res  34
op_msg: .res    3 * 90
op_sblk: .res   6
op_st:  .res    10
LBUFL   = 512
op_lbuf: .res   LBUFL + 2               ; a .LNK file's text
op_rw:  .res    6
op_end: .res    2                       ; ui_mklink: the end of the link's text
ui_lktgt: .res  130                     ; ui_lnkread: the target, the title, the arguments
ui_lktitl: .res 130
ui_lkargs: .res 130

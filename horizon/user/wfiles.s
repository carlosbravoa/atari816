; WFILES - the Files window (/BIN/WFILES.PRG): the file browser of the desktop.
;   WFILES [folder]: opens there (else in the current directory). Several may run: each new
;   window takes the first free place of 8 (+24, +24 from (24, 24), then the same 12 pixels
;   lower right) that no other window's content starts at. The title says the folder.
;   The current folder is read (READDIR, in batches) into a bank of its own, one record
;   per entry {u24 size, u8 attr, u8 length, name}, sorted on the way in (folders first,
;   then names, case-insensitive): the same as FILES. Outside the root a ".." entry comes
;   first (it goes up; it cannot be dragged, deleted, renamed or copied). Hidden unless
;   View > Show system files is on: /SYSTEM, and entries with the FAT hidden or system
;   attribute.
;   Content: a header bar (an Up button, the folder's full path cut at the left, the number
;   of entries), the list (one 12-pixel row per entry: an icon, the name, the size of files
;   right-aligned), a footer bar (what is mounted: D1:, XEX:, Cart:; messages until the
;   next key or click; 0.14: looked at again every 2 s, so a disk mounted elsewhere shows).
;   Keys: up/down, PgUp/PgDn, Home/End move; typing jumps to the first name starting with
;   the typed letters (1 s pause starts over); Enter opens; Backspace = parent folder;
;   Delete deletes; ctrl-C / ctrl-V copy / paste; ctrl-N a new window; Esc closes.
;   Mouse: a click selects, a double click (0.5 s) opens, the wheel scrolls 3 rows a step;
;   the Up button goes to the parent folder.
;   Drag and drop: a press on a row moved more than 4 pixels drags it (the drag pointer).
;   Released on a folder row of the same window (".." too): moved into it. On another
;   window: that window gets the full path (SYS_WDROP; this one reloads 0.6 s later). A path
;   dropped here is moved (SYS_RENAME) into the folder row under the pointer, else this folder.
;   Menus: File: Open, New window, New folder..., Rename..., Delete, Add to desktop (0.14: a
;          shortcut in /Desktop, ui_mklink), Close.
;          Edit: Copy (the selected entry's full path to the clipboard), Paste (copies the
;          file named on the clipboard into this folder, 32 KB at a time through a bank;
;          "Copy of NAME" when NAME is there already; folders are not copied).
;          View: Show system files (a check mark), Parent folder.
;   Open: a folder is entered (and becomes the current directory); a file goes to ui_open
;   (the controls library: its program by its type, a .PRG started, refused under /SYSTEM;
;   an alert when nothing opens it or the program cannot start).
;   If WFILES started the window system itself (no Desktop), it stops it at the end.
        .include "horizon.inc"
        .include "ui.inc"

MAXENT  = 1000
HEAPMAX = $FE00                         ; bytes of entry records in the bank
ROWH    = 12                            ; list row height
LISTY   = 16                            ; the first list row
HDRH    = 14                            ; header bar (then a 1-pixel line)
FOOTH   = 14                            ; footer: a 1-pixel line, then 13 pixels
WX      = 24                            ; the first window's place (outer) and content size
WY      = 24
WW      = 304
WH      = 216
NSLOT   = 8                             ; places: 4 down the diagonal, twice
PMAX    = 400                           ; path buffers (a path itself: 127 at most)
NAMEMAX = 100                           ; a name typed in the name dialog
UPW     = 18                            ; the Up button in the header: (2, 1), UPW x 12
TICKP   = 200                           ; (0.14) the timer: the footer looked at every 2 s

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        sys     SYS_WSSTART
        bcc     :+
        print   "wfiles: no window system\n"
        exit    1
:       sta     z:wsown
        jsr     ui_init
        sys     SYS_BALLOC              ; the entry records
        bcc     :+
        jsr     stopws
        print   "wfiles: no memory\n"
        exit    1
:       sta     z:hbank
        jsr     getarg
        ptr     wopen
        sys     SYS_WOPEN
        bcc     :+
        lda     z:hbank
        sys     SYS_BFREE
        jsr     stopws
        print   "wfiles: no window\n"
        exit    1
:       sta     z:win
        jsr     place
        lda     z:win
        ldx     #.loword(menus)
        ldy     #^menus
        sys     SYS_WMENU
        lda     z:win                   ; (0.14) the footer follows what is mounted
        ldx     #TICKP
        sys     SYS_WTIMER
        lda     wopen+4
        sta     z:cw
        lda     wopen+6
        sta     z:ch
        jsr     geom
        jsr     load
        jsr     findcame                ; (0.15) a file named by the argument: selected
        bcs     :+
        sta     z:sel
        jsr     showsel
:       jsr     redraw

; ---------------------------------------------------------------- events
loop:   lda     #0
        jsr     ui_getev
        bcs     loop
        ldx     #6
:       lda     ui_ev,x
        sta     ev,x
        dex
        dex
        bpl     :-
        lda     ev
        and     #$00FF
        cmp     #WE_KEY
        jeq     onkey
        cmp     #WE_BUTTON
        jeq     mouse
        cmp     #WE_MOTION
        jeq     motion
        cmp     #WE_WHEEL
        jeq     wheel
        cmp     #WE_CLOSE
        jeq     quit
        cmp     #WE_RESIZE
        jeq     resize
        cmp     #WE_DROP
        jeq     ondrop
        cmp     #WE_TICK
        jeq     ontick
        cmp     #WE_MENU
        jne     loop
        jsr     unmsg
        lda     ev+2                    ; menu: File 0, Edit 1, View 2
        beq     :+
        cmp     #2
        bne     @edit
        lda     ev+4                    ; View: 0 Show system files, (1 -), 2 Parent folder
        jeq     togsys
        cmp     #2
        jeq     parent
        jmp     loop
:       lda     ev+4                    ; File: 0 Open, 1 New window, 2 New folder...,
        asl     a                       ;   3 Rename..., 4 Delete, 5 Add to desktop, (6 -), 7 Close
        tax
        cpx     #16
        jcs     loop
        jmp     (ftab,x)
@edit:  lda     ev+4                    ; Edit: 0 Copy, 1 Paste
        jeq     copy
        cmp     #1
        jeq     paste
        jmp     loop

onkey:  jsr     ui_menukey              ; (0.15) the menu key: the selected row's menu
        bcc     :+
        jsr     unmsg
        lda     #1
        jmp     ctxmenu
:       lda     ev+2
        ldx     ev+4
        jsr     key_ascii
        cmp     #0
        jeq     loop
        sta     z:key
        jsr     unmsg
        lda     z:key
        cmp     #27
        jeq     quit
        cmp     #13
        jeq     open
        cmp     #8
        jeq     parent
        cmp     #3                      ; ctrl-C
        jeq     copy
        cmp     #22                     ; ctrl-V
        jeq     paste
        cmp     #14                     ; ctrl-N
        jeq     newwin
        cmp     #KEY_DEL
        jeq     delete
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

; ---------------------------------------------------------------- open
open:   lda     z:n
        jeq     loop
        ldx     z:sel
        jsr     isup                    ; "..": up
        jcs     parent
        ldx     z:sel
        jsr     rec
        jsr     kind                    ; (name -> fname)
        cmp     #FT_FOLDER
        bne     @file
        ldx     #.loword(fname)         ; a folder: go in
        ldy     #^fname
        sys     SYS_CHDIR
        jcs     oops
        jsr     load
        jsr     redraw
        jmp     loop
@file:  jsr     fullname                ; a file: its program (the library's table)
        jcs     long
        ldx     #.loword(pth)
        jsr     ui_open
        stz     z:btn                   ; (back after F12, or an alert)
        stz     z:pressed
        jsr     footer
        jmp     loop

; X = entry: C set if it is the ".." entry (the first one, outside the root)
isup:   cpx     #0
        bne     :+
        lda     z:hasup
        beq     :+
        sec
        rts
:       clc
        rts

; not for "..": X = entry -> C set (and the beep) if it is the ".." entry
notup:  jsr     isup
        bcc     :+
        jsr     ui_beep
        sec
:       rts

; View > Show system files: on / off (the check mark), the folder read again
togsys: lda     z:showsys
        eor     #1
        sta     z:showsys
        ldy     #0
        lda     #MS_STATE
        ldx     z:showsys
        beq     :+
        ldy     #MS_CHECK
        ora     #MS_CHECK
:       sep     #$20
        .a8
        sta     m_show
        rep     #$20
        .a16
        lda     z:win
        ldx     #2                      ; (menu 2, item 0)
        sys     SYS_WMSTATE
        bcc     :+
        lda     z:win                   ; (an older kernel: the menus again)
        ldx     #.loword(menus)
        ldy     #^menus
        sys     SYS_WMENU
:       jsr     keepsel
        jsr     reload
        jmp     loop

; error A: beep, and say it on the footer until the next key or click
oops:   sta     z:err
        ldx     #0
@t:     lda     errtab,x
        beq     @num
        cmp     z:err
        beq     @hit
        inx
        inx
        inx
        inx
        bra     @t
@hit:   lda     errtab+2,x
        tax
        jsr     say
        jmp     loop
@num:   jsr     ui_beep
        lda     #.loword(fbuf)
        sta     z:bp
        ldx     #.loword(m_err)
        jsr     app
        lda     z:err
        jsr     app_dec
        lda     #1
        sta     z:msg
        jsr     footer_draw
        jmp     loop

; the path too long: say so
long:   ldx     #.loword(m_long)
        jsr     say
        jmp     loop

; message X (ours) on the footer in red, with the error beep
say:    phx
        jsr     ui_beep
        plx
        lda     #1
        bra     note1
; message X on the footer in black (no beep)
note:   lda     #2
note1:  sta     z:msg
        lda     #.loword(fbuf)
        sta     z:bp
        jsr     app
        jmp     footer_draw

; a message on the footer goes with the next key, click or menu pick
unmsg:  lda     z:msg
        beq     :+
        stz     z:msg
        jsr     footer
:       rts

; Backspace: the parent folder, with the folder we came from selected
parent: ldx     #.loword(fname)
        ldy     #^fname
        lda     #128
        sys     SYS_GETCWD
        ldx     #0                      ; the last component -> came
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
:       cpx     #2                      ; ("/" itself: nothing to do)
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
        jcs     oops
        jsr     load
        jsr     findcame                ; the folder we came from
        bcs     :+
        sta     z:sel
        jsr     showsel
:       jsr     redraw
        jmp     loop

; the entry named in came -> A, C clear; C set: none
findcame:
        ldx     #0
@f:     cpx     z:n
        bcs     @no
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
        clc
        rts
@no:    sec
        rts

; the selected entry's name -> came (nothing: empty)
keepsel:
        stz     came
        lda     z:n
        beq     :+
        ldx     z:sel
        jsr     rec
        jsr     recname
        ldx     #.loword(fname)
        ldy     #.loword(came)
        jmp     ui_strcpy
:       rts

; read the folder again: the entry named in came selected, else the same place
reload: lda     z:sel
        pha
        lda     z:top
        pha
        jsr     load
        pla
        sta     z:top
        jsr     findcame
        bcc     @sel
        pla
        cmp     z:n
        bcc     :+
        lda     z:n
        dec     a
        bpl     :+
        lda     #0
:       sta     z:sel
        bra     @show
@sel:   sta     z:sel
        pla
@show:  jsr     showsel
        jmp     redraw

quit:   lda     z:dragging              ; (the pointer as it was)
        beq     :+
        lda     #0
        sys     SYS_WPTR
:       lda     z:win
        sys     SYS_WCLOSE
        lda     z:hbank
        sys     SYS_BFREE
        jsr     stopws
        exit    0

stopws: lda     z:wsown                 ; started by us: stop it again
        beq     :+
        sys     SYS_WSSTOP
:       rts

; the argument: a folder to start in ("quoted" if it has spaces)
getarg: lda     argl
        beq     @out
        ldx     argx
        jsr     args_init
        ldx     #.loword(pth)
        ldy     #^pth
        lda     #128
        jsr     next_arg
        beq     @out
        ldx     #.loword(pth)
        ldy     #^pth
        sys     SYS_CHDIR
        bcc     @out
        ldx     #.loword(pth)           ; (0.15) a file: its folder, the file selected
        jsr     basename                ; (Show original on the Desktop)
        cpx     #.loword(pth)
        beq     @out
        phx
        ldy     #.loword(came)
        jsr     ui_strcpy
        plx
        dex
        cpx     #.loword(pth)           ; ("/NAME": the root)
        bne     :+
        inx
:       stz     a:0,x
        ldx     #.loword(pth)
        ldy     #^pth
        sys     SYS_CHDIR
@out:   rts

; the window's place: the first of the NSLOT places whose content position no other
; window has (all taken: the first)
place:  lda     z:win
        ptr     winf
        sys     SYS_WINFO
        lda     winf                    ; the content position at place 0
        sta     z:ox
        lda     winf+2
        sta     z:oy
        stz     z:slot
@s:     jsr     slotoff
        sta     z:soff
        ldx     #0
@w:     cpx     z:win
        beq     @nw
        phx
        txa
        ldx     #.loword(winf2)
        ldy     #^winf2
        sys     SYS_WINFO
        plx
        bcs     @nw
        lda     z:ox
        clc
        adc     z:soff
        cmp     winf2
        bne     @nw
        lda     z:oy
        clc
        adc     z:soff
        cmp     winf2+2
        bne     @nw
        inc     z:slot                  ; taken: the next place
        lda     z:slot
        cmp     #NSLOT
        bcc     @s
        rts
@nw:    inx
        cpx     #16
        bcc     @w
        lda     z:soff                  ; free
        beq     @out
        clc
        adc     #WX
        tax
        lda     z:soff
        clc
        adc     #WY
        tay
        lda     z:win
        sys     SYS_WMOVE
@out:   rts

; the offset of place z:slot: 24 * (slot & 3) + 12 * (slot >> 2)
slotoff:
        lda     z:slot
        and     #3
        sta     z:tmp
        asl     a
        adc     z:tmp                   ; 3 k
        asl     a
        asl     a
        asl     a                       ; 24 k
        sta     z:tmp
        lda     z:slot
        lsr     a
        lsr     a
        asl     a
        asl     a                       ; 4 c
        sta     z:tmp2
        asl     a
        adc     z:tmp2                  ; 12 c
        clc
        adc     z:tmp
        rts

; the title: "Files: " and the folder (its end, "..." before it, when long)
settitle:
        ptr     pth
        lda     #128
        sys     SYS_GETCWD
        bcc     :+
        lda     #'?'
        sta     pth
        lda     #1
:       sta     z:tmp
        ldx     #.loword(s_ftitle)
        ldy     #.loword(ttl)
        jsr     ui_strcpy
        ldx     #.loword(pth)
        lda     z:tmp
        cmp     #25
        bcc     :+
        lda     #'.' | ('.' << 8)
        sta     ttl+7
        sta     ttl+8
        lda     z:tmp
        sec
        sbc     #21
        clc
        adc     #.loword(pth)
        tax
        ldy     #.loword(ttl+10)
        bra     :++
:       ldy     #.loword(ttl+7)
:       jsr     ui_strcpy
        lda     z:win
        ptr     ttl
        sys     SYS_WTITLE
        rts

; ---------------------------------------------------------------- paths
; X = buffer: the current folder with a '/' at its end -> X = its end (the 0)
cwdto:  stx     z:pp
        ldy     #^pth
        lda     #128
        sys     SYS_GETCWD
        bcc     :+
        lda     #'/'                    ; ('/', 0)
        sta     (pp)
        lda     #1
:       clc
        adc     z:pp
        tax
        dex
        lda     a:0,x
        inx
        and     #$00FF
        cmp     #'/'
        beq     :+
        lda     #'/'                    ; ('/', 0)
        sta     a:0,x
        inx
:       rts

; append string X at Y (the end of a string) -> X = the new end
cat:    phy
        jsr     ui_strcpy
        clc
        adc     1,s
        tax
        ply
        rts

; pth = the current folder / fname -> X = its end; C set if longer than 127
fullname:
        ldx     #.loword(pth)
        jsr     cwdto
        txy
        ldx     #.loword(fname)
        jsr     cat
        txa
        sec
        sbc     #.loword(pth)
        cmp     #128
        rts

; X = path -> X = its last part (after the last '/')
basename:
        stx     z:bs
        txy
@c:     lda     a:0,y
        and     #$00FF
        beq     @e
        iny
        cmp     #'/'
        bne     @c
        sty     z:bs
        bra     @c
@e:     ldx     z:bs
        rts

; strings X and Y the same, ignoring case? -> C set
samestr:
        stx     z:sa
        sty     z:sb
        ldy     #0
:       lda     (sa),y
        jsr     lower
        sta     z:tmp
        lda     (sb),y
        jsr     lower
        cmp     z:tmp
        bne     @no
        cmp     #0
        beq     @yes
        iny
        bra     :-
@no:    clc
        rts
@yes:   sec
        rts

; does path X exist? -> C set (its record in st)
exists: stx     sblk
        lda     #^pth
        sta     sblk+2
        lda     #.loword(st)
        sta     sblk+3
        lda     #^st
        sta     sblk+5
        ptr     sblk
        sys     SYS_STAT
        bcs     :+
        sec
        rts
:       clc
        rts

; rename pth to pth2 -> C set, A = error
rename2:
        lda     #.loword(pth)
        sta     rnblk
        lda     #^pth
        sta     rnblk+2
        lda     #.loword(pth2)
        sta     rnblk+3
        lda     #^pth2
        sta     rnblk+5
        ptr     rnblk
        sys     SYS_RENAME
        rts

; abuf = string X in quotes; u_arg = abuf (a spawn's argument)
quote:  phx
        lda     #'"'                    ; ('"', 0)
        sta     abuf
        plx
        ldy     #.loword(abuf+1)
        jsr     ui_strcpy
        tax
        lda     #'"'
        sta     abuf+1,x
        lda     #.loword(abuf)
        sta     z:u_arg
        lda     #^abuf
        sta     z:u_arg+2
        rts

; ---------------------------------------------------------------- pop-up menus (0.15)
; A right press on a row (it is selected) or on the empty part of the list, or the menu
; key (Shift+F10) with a row selected: a pop-up menu (ui_popup). Each item has an action
; (a routine of the File / Edit / View menus, or one of its own):
;   a file: Open, (text: Open with Edit, Open with Write; an Atari file: Load into Atari), -,
;     Copy, Add to desktop, -, Rename..., Delete
;   a folder: Open, Open in new window, -, Add to desktop, -, Rename..., Delete
;   "..": Open
;   the background: New folder..., Paste (dimmed: an empty clipboard), -, Parent folder
;     (dimmed at the root)
; A = 0: at the pointer, 1: from the keyboard (below the selected row)
ctxmenu:
        sta     z:pkey
        stz     z:btn                   ; (the menu takes the button's release)
        lda     z:pkey
        bne     @sel
        jsr     rowat
        jcs     @back
        cmp     z:sel                   ; the row pressed is selected
        beq     @sel
        sta     z:sel
        jsr     showsel
        jsr     list
@sel:   lda     z:n
        jeq     loop
        ldy     #0                      ; the items and their actions
        sty     z:pn
        ldx     z:sel
        jsr     isup
        bcc     :+
        lda     #A_OPEN                 ; "..": Open
        jsr     additem
        bra     @show
:       ldx     z:sel
        jsr     rec
        jsr     kind
        sta     z:pk
        lda     #A_OPEN
        jsr     additem
        lda     z:pk
        cmp     #FT_FOLDER
        bne     @file
        lda     #A_NEWW
        jsr     additem
        lda     #A_SEP
        jsr     additem
        bra     @desk
@file:  cmp     #FT_TEXT
        beq     :+
        cmp     #FT_WRITE
        bne     :++
:       lda     #A_EDIT
        jsr     additem
        lda     #A_WRITE
        jsr     additem
:       lda     z:pk
        cmp     #FT_ATARI
        bne     :+
        lda     #A_LOAD
        jsr     additem
:       lda     #A_SEP
        jsr     additem
        lda     #A_COPY
        jsr     additem
@desk:  lda     #A_DESK
        jsr     additem
        lda     #A_SEP
        jsr     additem
        lda     #A_REN
        jsr     additem
        lda     #A_DEL
        jsr     additem
@show:  lda     z:pkey
        beq     @ptr
        lda     #8                      ; below the selected row
        sta     z:ui_x
        lda     z:sel
        sec
        sbc     z:top
        inc     a
        ldx     #ROWH
        jsr     mul
        clc
        adc     #LISTY
        sta     z:ui_y
        jsr     endmenu
        lda     z:win
        ldx     #.loword(pbuf)
        jsr     ui_popat
        bra     @do
@back:  ldy     #0                      ; the background
        sty     z:pn
        lda     #A_NEWF
        jsr     additem
        lda     #A_PASTE
        jsr     additem
        jsr     clipempty
        bcc     :+
        jsr     dimlast
:       lda     #A_SEP
        jsr     additem
        lda     #A_UP
        jsr     additem
        lda     z:atroot
        beq     @ptr
        jsr     dimlast
@ptr:   jsr     endmenu
        lda     z:win
        ldx     #.loword(pbuf)
        jsr     ui_popup
@do:    stz     z:btn
        cmp     z:pn
        jcs     loop
        tax
        lda     pact,x
        and     #$00FF
        asl     a
        tax
        jmp     (acttab,x)

; item A (A_*) appended to pbuf: its text (after a state byte), its action in pact
additem:
        ldx     z:pn
        sep     #$20
        .a8
        sta     pact,x
        rep     #$20
        .a16
        inc     z:pn
        pha
        lda     z:pn                    ; (the first item: the buffer's start)
        cmp     #1
        bne     :+
        lda     #.loword(pbuf)
        sta     z:pw
:       lda     z:pw
        sta     z:pl                    ; (where this item starts: dimlast)
        pla
        asl     a
        tax
        ldy     z:pw
        lda     acttxt,x
        tax
        cpx     #.loword(s_asep)        ; (a separator: no state byte)
        beq     :+
        lda     #MS_STATE
        sta     a:0,y
        iny
:       sty     z:pd
        jsr     ui_strcpy
        sec                             ; past its 0
        adc     z:pd
        sta     z:pw
        rts
; the last item added: dimmed
dimlast:
        ldx     z:pl
        sep     #$20
        .a8
        lda     #MS_STATE | MS_DIM
        sta     a:0,x
        rep     #$20
        .a16
        rts
; the list ended ("")
endmenu:
        ldx     z:pw
        stz     a:0,x
        rts

; C set if the clipboard is empty
clipempty:
        lda     #.loword(clblk2)
        sta     clblk2
        lda     #^clblk2
        sta     clblk2+2
        stz     clblk2+3
        ptr     clblk2
        sys     SYS_CLGET
        bcs     :+
        cmp     #0
        bne     :++
:       sec
        rts
:       clc
        rts

; A * X -> A (small numbers)
mul:    sta     z:tmp
        lda     #0
        cpx     #0
        beq     :++
:       clc
        adc     z:tmp
        dex
        bne     :-
:       rts

; the actions of their own: Open in new window (a folder), Open with Edit / Write, Load
; into Atari
a_neww: jsr     fullsel                 ; Files in that folder
        jcs     long
        ldx     #.loword(pth)
        jsr     quote
        ldx     #.loword(p_wfiles)
        ldy     #.loword(abuf)
        lda     #.loword(t_files)
        jsr     ui_launch
        jmp     loop
a_edit: ldx     #.loword(p_edit)
        lda     #.loword(t_edit)
        bra     a_with
a_write:
        ldx     #.loword(p_write)
        lda     #.loword(t_write)
a_with: stx     z:pq
        sta     z:pr
        jsr     fullsel
        jcs     long
        ldx     #.loword(pth)
        jsr     quote
        ldx     z:pq
        ldy     #.loword(abuf)
        lda     z:pr
        jsr     ui_launch
        jmp     loop
a_load: jsr     fullsel
        jcs     long
        ldx     #.loword(pth)
        jsr     ui_atload
        bcc     :+
        cmp     #ENOMEM                 ; (0.18) no room for a cartridge's banks
        jne     oops
        ldx     #.loword(m_cnom)
        jsr     say
        jmp     loop
:
        jsr     footer                  ; the footer says what is mounted
        jmp     loop
; pth = the selected entry's full path; C set: too long
fullsel:
        ldx     z:sel
        jsr     rec
        jsr     recname
        jmp     fullname

; ---------------------------------------------------------------- moving
; move pth into the folder pth2 (its path with a '/' at the end, which is z:pe); refused
; (beep, a message): a folder into itself, the same place, a name that is there
domove: ldy     #0                      ; pth2 inside pth: pth2 starts with pth and '/'
:       lda     pth,y
        jsr     lower
        sta     z:tmp
        cmp     #0
        beq     @pre
        lda     pth2,y
        jsr     lower
        cmp     z:tmp
        bne     @ok
        iny
        bra     :-
@pre:   lda     pth2,y
        and     #$00FF
        cmp     #'/'
        bne     @ok
        ldx     #.loword(m_self)
        jsr     say
        jmp     loop
@ok:    lda     z:pe
        sec
        sbc     #.loword(pth2)
        cmp     #128
        jcs     long
        ldx     #.loword(pth)
        jsr     basename
        ldy     z:pe
        jsr     cat
        txa
        sec
        sbc     #.loword(pth2)
        cmp     #128
        jcs     long
        ldx     #.loword(pth)
        ldy     #.loword(pth2)
        jsr     samestr
        bcc     :+
        ldx     #.loword(m_there)
        jsr     say
        jmp     loop
:       ldx     #.loword(pth2)
        jsr     exists
        bcc     :+
        ldx     #.loword(m_exists)
        jsr     say
        jmp     loop
:       jsr     rename2
        jcs     oops
        ldx     #.loword(pth2)          ; (selected if it is in this list now)
        jsr     basename
        ldy     #.loword(came)
        jsr     ui_strcpy
        jsr     reload
        jmp     loop

; WE_DROP: a path dropped here, moved into the folder row under the pointer, else here
ondrop: lda     z:win
        ptr     dropbuf
        sys     SYS_WDROPGET
        jcs     loop
        jsr     unmsg
        lda     dropbuf
        and     #$00FF
        cmp     #'/'
        jne     loop
        ldx     #.loword(pth2)
        jsr     cwdto
        stx     z:pe
        jsr     rowat
        bcs     @here
        tax
        jsr     isup
        bcc     :+
        ldx     #.loword(pth2)          ; "..": the parent folder
        jsr     upto
        stx     z:pe
        bra     @here
:       jsr     rec
        ldy     #3
        lda     [pa],y
        and     #$0010
        beq     @here
        jsr     recname
        ldx     #.loword(fname)
        ldy     z:pe
        jsr     cat
        lda     #'/'                    ; ('/', 0)
        sta     a:0,x
        inx
        stx     z:pe
@here:  ldx     #.loword(dropbuf)
        ldy     #.loword(pth)
        jsr     ui_strcpy
        jmp     domove

; the timer after a drag to another window: read the folder again (once)
ontick: lda     z:win                   ; (back to the slow period)
        ldx     #TICKP
        sys     SYS_WTIMER
        lda     z:rl                    ; a reload after a drop
        beq     :+
        stz     z:rl
        jsr     keepsel
        jsr     reload
        jmp     loop
:       lda     z:msg                   ; (0.14) what is mounted changed: the footer
        jne     loop
        ldx     #0
:       lda     fbuf,x
        sta     fbuf2,x
        inx
        inx
        cpx     #200
        bcc     :-
        lda     #.loword(fbuf)          ; (built as footer does)
        sta     z:bp
        ldx     #.loword(s_d1)
        jsr     app
        lda     #0
        jsr     item
        ldx     #.loword(s_xex)
        jsr     app
        lda     #4
        jsr     item
        ldx     #.loword(s_cart)
        jsr     app
        lda     #5
        jsr     item
        ldx     #0
:       lda     fbuf,x
        cmp     fbuf2,x
        bne     :+
        bit     #$00FF                  ; (the end in either byte)
        beq     @same
        bit     #$FF00
        beq     @same
        inx
        inx
        bra     :-
:       jsr     footer_draw
@same:  jmp     loop

; ---------------------------------------------------------------- copy and paste
; Copy: the selected entry's full path to the clipboard
copy:   lda     z:n
        jeq     loop
        ldx     z:sel
        jsr     notup
        jcs     loop
        ldx     z:sel
        jsr     rec
        jsr     recname
        jsr     fullname
        jcs     long
        txa
        sec
        sbc     #.loword(pth)
        pha
        lda     #.loword(pth)
        sta     clblk
        lda     #^pth
        sta     clblk+2
        pla
        sta     clblk+3
        ptr     clblk
        sys     SYS_CLPUT
        jcs     oops
        ldx     #.loword(fname)         ; "Copied NAME" (the footer)
        lda     z:cw
        sec
        sbc     #60
        jsr     fit
        lda     #.loword(fbuf)
        sta     z:bp
        ldx     #.loword(s_copied)
        jsr     app
        ldx     #.loword(fname)
        jsr     app
        lda     #2
        sta     z:msg
        jsr     footer_draw
        jmp     loop

; (0.14) File > Add to desktop: a shortcut to the selected entry in /Desktop
addesk: lda     z:n
        jeq     loop
        ldx     z:sel
        jsr     notup
        jcs     loop
        ldx     z:sel
        jsr     rec
        jsr     recname
        jsr     fullname
        jcs     long
        ldx     #.loword(pth)
        jsr     ui_mklink
        jcs     oops
        ldx     #.loword(fname)         ; "Added NAME to the desktop" (the footer)
        lda     z:cw
        sec
        sbc     #120
        jsr     fit
        lda     #.loword(fbuf)
        sta     z:bp
        ldx     #.loword(s_added)
        jsr     app
        ldx     #.loword(fname)
        jsr     app
        ldx     #.loword(s_added2)
        jsr     app
        lda     #2
        sta     z:msg
        jsr     footer_draw
        jmp     loop

; Paste: the file named on the clipboard copied into this folder
paste:  lda     #.loword(clbuf)
        sta     clblk
        lda     #^clbuf
        sta     clblk+2
        lda     #127
        sta     clblk+3
        ptr     clblk
        sys     SYS_CLGET
        jcs     @none
        cmp     #128                    ; (longer: not a path)
        jcs     @none
        cmp     #2
        jcc     @none
        tax
        stz     clbuf,x
        lda     clbuf
        and     #$00FF
        cmp     #'/'
        jne     @none
        ldx     #.loword(clbuf)
        jsr     exists
        bcs     :+
        lda     #$44
        jmp     oops
:       lda     st+4
        and     #$0010
        beq     :+
        ldx     #.loword(m_nofold)
        jsr     say
        jmp     loop
:       lda     st                      ; its size
        sta     z:csize
        lda     st+2
        sta     z:csize+2
        ldx     #.loword(pth2)          ; here / its name
        jsr     cwdto
        stx     z:pe
        ldx     #.loword(clbuf)
        jsr     basename
        stx     z:bn
        ldy     z:pe
        jsr     cat
        txa
        sec
        sbc     #.loword(pth2)
        cmp     #128
        jcs     long
        ldx     #.loword(pth2)
        jsr     exists
        bcc     docopy
        ldx     #.loword(s_copyof)      ; there already: "Copy of NAME"
        ldy     z:pe
        jsr     cat
        txy
        ldx     z:bn
        jsr     cat
        txa
        sec
        sbc     #.loword(pth2)
        cmp     #128
        jcs     long
        ldx     #.loword(pth2)
        jsr     exists
        bcc     docopy
        ldx     #.loword(m_exists)
        jsr     say
        jmp     loop
@none:  ldx     #.loword(m_noclip)
        jsr     say
        jmp     loop

; copy clbuf to pth2 (new), 32 KB at a time through a bank of its own
docopy: ldx     #.loword(clbuf)
        ldy     #^clbuf
        lda     #O_READ
        sys     SYS_OPEN
        jcs     oops
        sta     z:h1
        ldx     #.loword(pth2)
        ldy     #^pth2
        lda     #O_CREATE
        sys     SYS_OPEN
        bcc     :+
        pha
        lda     z:h1
        sys     SYS_CLOSE
        pla
        jmp     oops
:       sta     z:h2
        sys     SYS_BALLOC
        bcc     :+
        lda     #ENOMEM
        sta     z:err
        stz     z:cbank
        bra     @fail
:       sta     z:cbank
        stz     z:kdone
        lda     z:csize+1               ; the size in K
        lsr     a
        lsr     a
        sta     z:ktot
@lp:    lda     z:h1                    ; read up to 32 KB
        jsr     rwset
        sys     SYS_READ
        bcs     @err
        cmp     #0
        beq     @done
        sta     rwblk+4
        sta     z:cnt
        lda     z:h2                    ; write them
        sep     #$20
        .a8
        sta     rwblk
        rep     #$20
        .a16
        ptr     rwblk
        sys     SYS_WRITE
        bcs     @err
        cmp     z:cnt
        beq     :+
        lda     #$01FF                  ; (fewer: the card is full)
        bra     @err
:       lda     z:kdone
        clc
        adc     #32
        sta     z:kdone
        lda     z:ktot                  ; a large file: say how far
        cmp     #33
        bcc     @lp
        jsr     progress
        bra     @lp
@err:   sta     z:err
@fail:  lda     z:cbank
        beq     :+
        sys     SYS_BFREE
:       lda     z:h2
        sys     SYS_CLOSE
        lda     z:h1
        sys     SYS_CLOSE
        ptr     pth2                    ; (no half copy left)
        sys     SYS_DELETE
        lda     z:err
        jmp     oops
@done:  lda     z:cbank
        sys     SYS_BFREE
        lda     z:h2
        sys     SYS_CLOSE
        lda     z:h1
        sys     SYS_CLOSE
        ldx     #.loword(pth2)          ; the copy selected
        jsr     basename
        ldy     #.loword(came)
        jsr     ui_strcpy
        jsr     reload
        jmp     loop

; the read / write block {handle A, buffer cbank:0000, 32768} -> X, Y
rwset:  sep     #$20
        .a8
        sta     rwblk
        lda     z:cbank
        sta     rwblk+3
        rep     #$20
        .a16
        stz     rwblk+1
        lda     #32768
        sta     rwblk+4
        ptr     rwblk
        rts

; "Copying 64 of 300 K: NAME" on the footer
progress:
        lda     #.loword(fbuf)
        sta     z:bp
        ldx     #.loword(s_copying)
        jsr     app
        lda     z:kdone
        cmp     z:ktot
        bcc     :+
        lda     z:ktot
:       jsr     app_dec
        ldx     #.loword(s_of)
        jsr     app
        lda     z:ktot
        jsr     app_dec
        ldx     #.loword(s_kcolon)
        jsr     app
        ldx     z:bn
        jsr     app
        lda     #2
        sta     z:msg
        jmp     footer_draw

; ---------------------------------------------------------------- File menu
; New window: another Files, in this folder
newwin: ptr     pth
        lda     #128
        sys     SYS_GETCWD
        ldx     #.loword(pth)
        jsr     quote
        ldx     #.loword(p_wfiles)
        ldy     #.loword(abuf)
        lda     #.loword(t_files)
        jsr     ui_launch
        jmp     loop

; New folder...: its name in a dialog
newdir: ldx     #.loword(s_newf)
        ldy     #.loword(nbuf)
        jsr     ui_strcpy
        ldx     #.loword(ak_newdir)
        jsr     ui_ask
        jcs     loop
        jsr     chkname
        jcs     loop
        ldx     #.loword(pth)
        jsr     cwdto
        txy
        ldx     #.loword(nbuf)
        jsr     cat
        txa
        sec
        sbc     #.loword(pth)
        cmp     #128
        jcs     long
        ldx     #.loword(pth)
        jsr     exists
        bcc     :+
        ldx     #.loword(m_exists)
        jsr     say
        jmp     loop
:       ptr     pth
        sys     SYS_MKDIR
        jcs     oops
        ldx     #.loword(nbuf)
        ldy     #.loword(came)
        jsr     ui_strcpy
        jsr     reload
        jmp     loop

; Rename...: the selected entry's new name in a dialog
rename: lda     z:n
        jeq     loop
        ldx     z:sel
        jsr     notup
        jcs     loop
        ldx     z:sel
        jsr     rec
        jsr     recname
        ldx     #.loword(fname)
        ldy     #.loword(ibuf)
        jsr     ui_strcpy
        ldx     #.loword(fname)
        ldy     #.loword(nbuf)
        jsr     ui_strcpy
        ldx     #.loword(ak_rename)
        jsr     ui_ask
        jcs     loop
        jsr     chkname
        jcs     loop
        ldy     #0                      ; the same name exactly: nothing to do
:       lda     nbuf,y
        and     #$00FF
        sta     z:tmp
        lda     ibuf,y
        and     #$00FF
        cmp     z:tmp
        bne     :+
        cmp     #0
        jeq     loop
        iny
        bra     :-
:       ldx     #.loword(ibuf)          ; pth = the old one, pth2 = the new one
        ldy     #.loword(fname)
        jsr     ui_strcpy
        jsr     fullname
        jcs     long
        ldx     #.loword(pth2)
        jsr     cwdto
        txy
        ldx     #.loword(nbuf)
        jsr     cat
        txa
        sec
        sbc     #.loword(pth2)
        cmp     #128
        jcs     long
        ldx     #.loword(ibuf)          ; (only the case changes: the same file)
        ldy     #.loword(nbuf)
        jsr     samestr
        bcs     :+
        ldx     #.loword(pth2)
        jsr     exists
        bcc     :+
        ldx     #.loword(m_exists)
        jsr     say
        jmp     loop
:       jsr     rename2
        jcs     oops
        ldx     #.loword(nbuf)
        ldy     #.loword(came)
        jsr     ui_strcpy
        jsr     reload
        jmp     loop

; the name in nbuf usable? (not empty, no '/', not "." or "..") C set: no (said so)
chkname:
        lda     nbuf
        and     #$00FF
        beq     @bad
        ldx     #0
:       lda     nbuf,x
        and     #$00FF
        beq     :+
        cmp     #'/'
        beq     @bad
        cmp     #$5C                    ; (a backslash)
        beq     @bad
        inx
        bra     :-
:       lda     nbuf                    ; "." / ".."
        cmp     #'.'
        beq     @bad
        cmp     #'.' | ('.' << 8)
        bne     @ok
        lda     nbuf+2
        and     #$00FF
        beq     @bad
@ok:    clc
        rts
@bad:   ldx     #.loword(m_badname)
        jsr     say
        sec
        rts

; Delete: the selected entry, after a warning (a folder must be empty)
delete: lda     z:n
        jeq     loop
        ldx     z:sel
        jsr     notup
        jcs     loop
        ldx     z:sel
        jsr     rec
        ldy     #3
        lda     [pa],y
        and     #$0010
        sta     z:isdir
        jsr     recname
        jsr     fullname
        jcs     long
        lda     z:isdir
        beq     @ask
        lda     #.loword(pth)           ; a folder: anything in it?
        sta     rblk
        lda     #^pth
        sta     rblk+2
        lda     #.loword(dbuf)
        sta     rblk+3
        lda     #^dbuf
        sta     rblk+5
        lda     #DBUFLEN
        sta     rblk+6
        stz     rblk+8
        ptr     rblk
        sys     SYS_READDIR
        jcs     oops
        cmp     #0
        beq     @ask
        ldx     #.loword(m_full2)
        jsr     say
        jmp     loop
@ask:   ldx     #.loword(fname)         ; "Delete NAME?"
        lda     #220
        jsr     fit
        ldx     #.loword(s_del)
        ldy     #.loword(atext)
        jsr     ui_strcpy
        clc
        adc     #.loword(atext)
        tay
        ldx     #.loword(fname)
        jsr     cat
        txy
        ldx     #.loword(s_qm)
        jsr     cat
        ldx     #.loword(al_del)
        jsr     ui_alert
        cmp     #0
        jne     loop
        ptr     pth
        sys     SYS_DELETE
        jcs     oops
        stz     came
        jsr     reload
        jmp     loop

; ---------------------------------------------------------------- selection
; A = signed step: move the selection, clamped
move:   clc
        adc     z:sel
        bpl     :+
        lda     #0
:       ; fall through
; select entry A (clamped to the list); scroll, or redraw the two rows that change
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
        lda     z:sel                   ; same page: the old row, then the new one
        cmp     z:nsel
        beq     @done
        pha
        lda     z:nsel
        sta     z:sel
        pla
        jsr     row_of
        lda     z:sel
        jsr     row_of
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
        jmp     loop

; top so that the selection shows (at the bottom if below the page), and not past the end
showsel:
        lda     z:sel
        cmp     z:top
        bcs     :+
        sta     z:top
:       lda     z:sel
        sec
        sbc     z:listn
        inc     a
        bmi     :+
        cmp     z:top
        bcc     :+
        sta     z:top
:       lda     z:n                     ; no empty rows when the list is long enough
        sec
        sbc     z:listn
        bpl     :+
        lda     #0
:       cmp     z:top
        bcs     :+
        sta     z:top
:       rts

; the wheel: a = steps (up > 0), 3 rows each
wheel:  lda     ev+2
        sta     z:tmp
        asl     a
        clc
        adc     z:tmp
        eor     #$FFFF
        inc     a
        clc
        adc     z:top
        bpl     :+
        lda     #0
:       sta     z:tmp
        lda     z:n                     ; at most n - listn
        sec
        sbc     z:listn
        bpl     :+
        lda     #0
:       cmp     z:tmp
        bcc     :+
        lda     z:tmp
:       cmp     z:top
        jeq     loop
        sta     z:top
        jsr     list
        jmp     loop

; the entry under the pointer (ev a, b) -> A, C clear; C set: none
rowat:  lda     ev+2
        cmp     z:cw
        bcs     @no
        lda     ev+4
        sec
        sbc     #LISTY
        bmi     @no
        ldx     #0
:       cmp     #ROWH
        bcc     :+
        sbc     #ROWH
        inx
        bra     :-
:       cpx     z:listn
        bcs     @no
        txa
        clc
        adc     z:top
        cmp     z:n
        bcs     @no
        clc
        rts
@no:    sec
        rts

; a button event: a left press selects the row under the pointer (and may start a drag);
; a second press on the same row within 0.5 s opens it; the release ends a drag
mouse:  lda     ev+6
        and     #$0007
        pha
        eor     z:btn                   ; changed buttons
        sta     z:tmp
        pla
        sta     z:btn
        and     z:tmp                   ; (0.15) the right button pressed: the pop-up menu
        and     #$0002
        beq     :+
        jsr     unmsg
        lda     ev+4                    ; (not on the header or footer)
        cmp     #HDRH
        jcc     loop
        lda     #0
        jmp     ctxmenu
:       lda     z:tmp
        and     #$0001
        sta     z:tmp
        lda     z:tmp                   ; the left button changed?
        jeq     loop
        lda     z:btn
        and     #$0001
        jeq     release
        stz     z:pressed
        jsr     unmsg
        lda     ev+4                    ; the Up button
        cmp     #HDRH
        bcs     :+
        lda     ev+2
        cmp     #2 + UPW
        bcs     :+
        lda     z:atroot
        jne     loop
        lda     #1
        jsr     upbtn
        sys     SYS_WSSYNC
        lda     #80
        sys     SYS_SLEEP
        jmp     parent
:       jsr     rowat
        jcs     loop
        sta     z:tmp
        sys     SYS_UPTIME
        sta     z:now
        lda     z:tmp
        cmp     z:sel                   ; a second press on the selected row, soon enough
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
        lda     z:tmp                   ; (a drag may start here)
        sta     z:drg
        lda     ev+2
        sta     z:px
        lda     ev+4
        sta     z:py
        ldx     z:tmp                   ; (".." is not dragged)
        jsr     isup
        bcs     :+
        lda     #1
        sta     z:pressed
:       lda     z:tmp
        jmp     select

; the pointer moved with the button held: more than 4 pixels from the press = a drag
motion: lda     z:pressed
        jeq     loop
        lda     z:dragging
        jne     loop
        lda     ev+2
        sec
        sbc     z:px
        jsr     absv
        cmp     #5
        bcs     :+
        lda     ev+4
        sec
        sbc     z:py
        jsr     absv
        cmp     #5
        jcc     loop
:       lda     #1
        sta     z:dragging
        sys     SYS_WPTR
        jmp     loop
absv:   bpl     :+
        eor     #$FFFF
        inc     a
:       rts

; the release: the end of a drag. On a folder row here: moved into it; on another window:
; it gets the path (and this one reads the folder again a moment later)
release:
        stz     z:pressed
        lda     z:dragging
        jeq     loop
        stz     z:dragging
        lda     #0
        sys     SYS_WPTR
        lda     z:win
        ptr     winf
        sys     SYS_WINFO
        lda     winf                    ; the point on the screen
        clc
        adc     ev+2
        tax
        lda     winf+2
        clc
        adc     ev+4
        tay
        sys     SYS_WINAT
        and     #$00FF
        cmp     #$FF
        jeq     loop
        cmp     z:win
        beq     @self
        sta     z:tgt
        ldx     z:drg
        jsr     rec
        jsr     recname
        jsr     fullname
        jcs     long
        lda     z:tgt
        ptr     pth
        sys     SYS_WDROP
        jcs     oops
        inc     z:rl
        lda     z:win
        ldx     #60
        sys     SYS_WTIMER
        jmp     loop
@self:  jsr     rowat
        jcs     loop
        cmp     z:drg
        jeq     loop
        tax
        jsr     isup
        bcc     :+
        ldx     #.loword(pth2)          ; "..": into the parent folder
        jsr     upto
        stx     z:pe
        bra     @from
:       jsr     rec
        ldy     #3
        lda     [pa],y
        and     #$0010
        jeq     loop
        jsr     recname                 ; pth2 = here / the folder /
        ldx     #.loword(pth2)
        jsr     cwdto
        txy
        ldx     #.loword(fname)
        jsr     cat
        lda     #'/'                    ; ('/', 0)
        sta     a:0,x
        inx
        stx     z:pe
@from:  ldx     z:drg                   ; pth = here / the entry
        jsr     rec
        jsr     recname
        jsr     fullname
        jcs     long
        jmp     domove

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
:       ldx     z:hasup                 ; X = entry (sorted order; not "..")
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

; WE_RESIZE: the new content size; the rows that fit
resize: lda     ev+2
        sta     z:cw
        lda     ev+4
        sta     z:ch
        jsr     geom
        jsr     showsel
        jsr     redraw
        jmp     loop

; listn from the content height (at least 1)
geom:   lda     z:ch
        sec
        sbc     #LISTY + FOOTH
        bpl     :+
        lda     #0
:       ldx     #0
:       cmp     #ROWH
        bcc     :+
        sbc     #ROWH
        inx
        bra     :-
:       txa
        bne     :+
        inc     a
:       sta     z:listn
        rts

; ---------------------------------------------------------------- the directory
; read the current folder into the bank, sorted
load:   stz     z:n
        stz     z:heap
        stz     z:sel
        stz     z:top
        stz     z:skip
        stz     z:trunc
        stz     z:hasup
        stz     z:atroot
        ptr     tbuf                    ; at the root?
        lda     #128
        sys     SYS_GETCWD
        bcs     @call
        lda     tbuf
        cmp     #'/'                    ; ("/", 0)
        bne     @call
        inc     z:atroot
@call:  lda     #.loword(dot)           ; block: path ".", buffer, length, skip
        sta     rblk
        lda     #^dot
        sta     rblk+2
        lda     #.loword(dbuf)
        sta     rblk+3
        lda     #^dbuf
        sta     rblk+5
        lda     #DBUFLEN
        sta     rblk+6
        lda     z:skip
        sta     rblk+8
        ldx     #.loword(rblk)
        ldy     #^rblk
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
        jsr     hidden
        bcs     :+
        jsr     add
:       ldx     z:dpos
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
@out:   lda     z:atroot                ; outside the root: ".." first
        bne     @sel
        lda     z:n
        cmp     #MAXENT
        bcc     :+
        dec     z:n
        inc     z:trunc
:       lda     z:heap                  ; its record {0, $10, 2, ".."}
        sta     z:pb
        lda     z:hbank
        sta     z:pb+2
        ldy     #0
        lda     #0
        sta     [pb],y
        ldy     #2
        lda     #$1000
        sta     [pb],y
        ldy     #4
        lda     #2 | ('.' << 8)
        sta     [pb],y
        ldy     #6
        lda     #'.'
        sep     #$20
        .a8
        sta     [pb],y
        rep     #$20
        .a16
        lda     z:n                     ; idx[1..n] = idx[0..n), idx[0] = it
        asl     a
        tax
:       cpx     #0
        beq     :+
        lda     idx-2,x
        sta     idx,x
        dex
        dex
        bra     :-
:       lda     z:heap
        sta     idx
        clc
        adc     #7
        sta     z:heap
        inc     z:n
        inc     z:hasup
        lda     z:n                     ; the first real entry selected
        cmp     #2
        bcc     @sel
        lda     #1
        sta     z:sel
@sel:   jmp     settitle

; dbuf entry at dpos hidden? (View > Show system files off: the hidden or system attribute,
; /SYSTEM) -> C set
hidden: lda     z:showsys
        bne     @show
        ldx     z:dpos
        lda     dbuf+4,x
        and     #$0006
        bne     @hide
        lda     z:atroot
        beq     @show
        lda     dbuf+5,x
        and     #$00FF
        cmp     #6
        bne     @show
        ldy     #0
:       lda     dbuf+6,x
        and     #$00DF
        sta     z:tmp
        lda     s_system,y
        and     #$00FF
        beq     @hide
        cmp     z:tmp
        bne     @show
        inx
        iny
        bra     :-
@hide:  sec
        rts
@show:  clc
        rts

; X = buffer: the parent of the current folder with a '/' at its end -> X = its end (the 0)
upto:   stx     z:pp2
        jsr     cwdto
        dex                             ; (at the '/' of the end)
:       cpx     z:pp2
        beq     :+
        dex
        lda     a:0,x
        and     #$00FF
        cmp     #'/'
        bne     :-
:       inx
        sep     #$20
        .a8
        stz     a:0,x
        rep     #$20
        .a16
        rts

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

; the kind of record pa (its name -> fname): A = FT_* (ui_ftype), FT_FOLDER, or KUP for ".."
kind:   jsr     recname
        ldy     #3
        lda     [pa],y
        and     #$0010
        beq     @file
        lda     fname                   ; ".."?
        cmp     #'.' | ('.' << 8)
        bne     :+
        lda     fname+2
        and     #$00FF
        bne     :+
        lda     #KUP
        rts
:       lda     #FT_FOLDER
        rts
@file:  ldx     #.loword(fname)
        jmp     ui_ftype

; ---------------------------------------------------------------- drawing
; the whole content
redraw: jsr     header
        jsr     list
        ; fall through
footer: stz     z:msg                   ; what is mounted (it replaces a message)
        lda     #.loword(fbuf)
        sta     z:bp
        ldx     #.loword(s_d1)
        jsr     app
        lda     #0
        jsr     item
        ldx     #.loword(s_xex)
        jsr     app
        lda     #4
        jsr     item
        ldx     #.loword(s_cart)
        jsr     app
        lda     #5
        jsr     item
        ; fall through
footer_draw:
        lda     z:ch                    ; a line, the bar, the text (red for a message)
        sec
        sbc     #FOOTH
        sta     z:fy
        tay
        ldx     #0
        lda     z:cw
        sta     z:kw
        lda     #1
        sta     z:kh
        lda     #WD_FILL | (C_DARK << 8)
        jsr     rect
        lda     z:fy
        inc     a
        tay
        ldx     #0
        lda     #FOOTH - 1
        sta     z:kh
        lda     #WD_FILL | (C_LIGHT << 8)
        jsr     rect
        ldx     #.loword(fbuf)
        lda     z:cw
        sec
        sbc     #8
        jsr     fit
        ldx     #.loword(fbuf)
        stx     z:sp
        ldx     #4
        lda     #C_BLACK
        ldy     z:msg
        cpy     #1
        bne     :+
        lda     #C_RED
:       pha
        lda     z:fy
        clc
        adc     #3
        tay
        pla
        jmp     text

; mounted item A appended: its file name (no folders), or "-"
item:   ldx     #.loword(tbuf)
        ldy     #^tbuf
        sys     SYS_CQUERY
        bcs     :+
        cmp     #0
        bne     :++
:       ldx     #.loword(s_none)
        jmp     app
:       ldx     #0                      ; after the last '/'
        ldy     #0
:       lda     tbuf,x
        and     #$00FF
        beq     :++
        cmp     #'/'
        bne     :+
        txy
        iny
:       inx
        bra     :--
:       tya
        clc
        adc     #.loword(tbuf)
        tax
        jmp     app

; the header: the folder (cut from the left to fit) and the number of entries
header: ldx     #.loword(hbuf+3)
        ldy     #^hbuf
        lda     #128
        sys     SYS_GETCWD
        bcc     :+
        lda     #'?'
        sta     hbuf+3
:       ldx     #.loword(hbuf+3)        ; the end of the path
        ldy     #0
:       lda     a:0,x
        and     #$00FF
        beq     :+
        inx
        bra     :-
:       stx     z:bp
        ldx     #.loword(s_open)
        jsr     app
        lda     z:n
        sec
        sbc     z:hasup
        jsr     app_dec
        ldx     #.loword(s_ent)
        lda     z:n
        sec
        sbc     z:hasup
        cmp     #1
        bne     :+
        ldx     #.loword(s_ent1)
:       jsr     app
        lda     z:trunc
        beq     :+
        ldx     #.loword(s_more)
        jsr     app
:       ldx     #.loword(s_close)
        jsr     app
        ldx     #.loword(hbuf+3)        ; cut from the left: "..." and the end of it
@cut:   stx     z:sp
        phx
        ldx     z:sp
        ldy     #^hbuf
        lda     #0
        sys     SYS_WTWIDTH
        plx
        clc
        adc     #UPW + 10
        cmp     z:cw
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
@draw:  ldx     #0
        ldy     #0
        lda     z:cw
        sta     z:kw
        lda     #HDRH
        sta     z:kh
        lda     #WD_FILL | (C_LIGHT << 8)
        jsr     rect
        ldx     #0
        ldy     #HDRH
        lda     #1
        sta     z:kh
        lda     #WD_FILL | (C_DARK << 8)
        jsr     rect
        ldx     #0                      ; (a body-coloured gap above the list)
        ldy     #HDRH + 1
        lda     #LISTY - HDRH - 1
        sta     z:kh
        lda     #WD_FILL | (C_BODY << 8)
        jsr     rect
        lda     #0
        jsr     upbtn
        ldx     #UPW + 6
        ldy     #2
        lda     #C_BLACK
        jmp     text

; the Up button at (2, 1): A = 0 raised, 1 pressed; dimmed at the root
upbtn:  pha
        lda     z:win
        sta     z:ui_win
        lda     #2
        sta     z:ui_x
        lda     #1
        sta     z:ui_y
        lda     #UPW
        sta     z:ui_w
        lda     #12
        sta     z:ui_h
        lda     #WD_FRAME | (C_DARK << 8)
        jsr     ui_rect
        inc     z:ui_x
        inc     z:ui_y
        dec     z:ui_w
        dec     z:ui_w
        dec     z:ui_h
        dec     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        pla
        pha
        jsr     ui_bevel
        lda     #C_BLACK                ; the arrow
        ldx     z:atroot
        beq     :+
        lda     #C_MID
:       xba
        ora     #WD_FILL
        sta     z:tmp
        pla                             ; (pressed: one pixel down right)
        sta     z:tmp2
        ldx     #0
:       lda     uparrow,x               ; {w, h, dx, dy} from (9, 3), w = 0: the end
        beq     :+
        sta     z:ui_w
        lda     uparrow+2,x
        sta     z:ui_h
        lda     uparrow+4,x
        clc
        adc     z:tmp2
        clc
        adc     #9
        sta     z:ui_x
        lda     uparrow+6,x
        clc
        adc     z:tmp2
        clc
        adc     #3
        sta     z:ui_y
        phx
        lda     z:tmp
        jsr     ui_rect
        plx
        txa
        clc
        adc     #8
        tax
        bra     :-
:       rts

; the list rows, and the body below the last one
list:   stz     z:row
@r:     lda     z:row
        clc
        adc     z:top
        cmp     z:n
        bcs     @empty
        jsr     row_i
        bra     @nx
@empty: jsr     row_y
        ldx     #0
        lda     z:cw
        sta     z:kw
        lda     #ROWH
        sta     z:kh
        lda     #WD_FILL | (C_BODY << 8)
        jsr     rect
@nx:    inc     z:row
        lda     z:row
        cmp     z:listn
        bcc     @r
        jsr     row_y                   ; row = listn: the rest down to the footer
        sty     z:tmp
        lda     z:ch
        sec
        sbc     #FOOTH
        sec
        sbc     z:tmp
        beq     @out
        bmi     @out
        sta     z:kh
        lda     z:cw
        sta     z:kw
        ldx     #0
        lda     #WD_FILL | (C_BODY << 8)
        jsr     rect
@out:   lda     z:n                     ; an empty folder says so
        cmp     z:hasup
        bne     :+
        lda     #.loword(s_empty)
        sta     z:sp
        ldx     #24
        ldy     #LISTY + 1
        lda     z:hasup
        beq     @e
        ldy     #LISTY + 1 + ROWH
@e:     lda     #C_MID
        jmp     text
:       rts

; Y = the y of list row z:row
row_y:  lda     z:row
        asl     a
        adc     z:row                   ; * 3
        asl     a
        asl     a                       ; * 12
        clc
        adc     #LISTY
        tay
        rts

; the row of entry A (must be on the page)
row_of: pha
        sec
        sbc     z:top
        sta     z:row
        pla
        ; fall through
; entry A on list row z:row
row_i:  sta     z:cur
        tax
        jsr     rec
        jsr     row_y
        sty     z:ry
        lda     #C_BODY                 ; the colours
        ldx     #C_BLACK
        ldy     z:cur
        cpy     z:sel
        bne     :+
        lda     #C_SELECT
        ldx     #C_WHITE
:       stx     z:fg
        xba
        ora     #WD_FILL
        ldx     #0
        ldy     z:ry
        pha
        lda     z:cw
        sta     z:kw
        lda     #ROWH
        sta     z:kh
        pla
        jsr     rect
        jsr     kind                    ; the icon
        sta     z:knd
        asl     a
        tax
        lda     icons,x
        jsr     icon
        ldx     #0                      ; the name, printable
        sep     #$20
        .a8
:       lda     fname,x
        beq     :++
        cmp     #' '
        bcc     :+
        cmp     #$7F
        bcc     :++
:       lda     #'?'
        sta     fname,x
:       lda     fname,x
        beq     :+
        inx
        bra     :---
:       rep     #$20
        .a16
        lda     z:cw                    ; folders: the name up to the right edge
        sec
        sbc     #24 + 4
        sta     z:nw
        lda     z:knd
        cmp     #FT_FOLDER
        beq     @name
        cmp     #KUP
        beq     @name
        lda     #.loword(sbuf)          ; files: the size, right-aligned
        sta     z:bp
        ldy     #2                      ; bytes, or K from 64 KB up
        lda     [pa],y
        and     #$00FF
        beq     :+
        ldy     #1
        lda     [pa],y
        lsr     a
        lsr     a
        jsr     app_dec
        ldx     #.loword(s_k)
        jsr     app
        bra     :++
:       lda     [pa]
        jsr     app_dec
:       ldx     #.loword(sbuf)
        ldy     #^sbuf
        lda     #0
        sys     SYS_WTWIDTH
        sta     z:tmp
        lda     z:cw
        sec
        sbc     #6
        sec
        sbc     z:tmp
        sta     z:sx
        sec
        sbc     #24 + 10
        sta     z:nw
        lda     #.loword(sbuf)
        sta     z:sp
        ldx     z:sx
        lda     z:ry
        inc     a
        tay
        lda     z:fg
        jsr     text
@name:  ldx     #.loword(fname)
        lda     z:nw
        jsr     fit
        lda     #.loword(fname)
        sta     z:sp
        ldx     #24
        lda     z:ry
        inc     a
        tay
        lda     z:fg
        jmp     text

; draw icon table A at row y z:ry: {op | colour << 8, dx, dy, w, h}..., 0
icon:   sta     z:ip
@i:     lda     (ip)
        beq     @out
        pha
        ldy     #6
        lda     (ip),y
        sta     z:kw
        ldy     #8
        lda     (ip),y
        sta     z:kh
        ldy     #4
        lda     (ip),y
        clc
        adc     z:ry
        pha
        ldy     #2
        lda     (ip),y
        tax
        ply
        pla
        jsr     rect
        lda     z:ip
        clc
        adc     #10
        sta     z:ip
        bra     @i
@out:   rts

; cut the string at X (ours) with "..." until it is at most A pixels wide (UI font)
fit:    stx     z:sp
        cmp     #$8000
        bcc     :+
        lda     #0
:       sta     z:fmax
        ldy     #0                      ; its length
:       lda     a:0,x
        and     #$00FF
        beq     :+
        inx
        iny
        bra     :-
:       sty     z:flen
@try:   ldx     z:sp
        ldy     #^fname
        lda     #0
        sys     SYS_WTWIDTH
        cmp     z:fmax
        bcc     @out
        beq     @out
        lda     z:flen
        beq     @out
        dec     z:flen
        lda     z:sp
        clc
        adc     z:flen
        tax
        lda     #'.' | ('.' << 8)
        sta     a:0,x
        sta     a:1,x
        stz     a:3,x                   ; ('.', 0 at +2, +3)
        lda     #'.'
        sta     a:2,x
        bra     @try
@out:   rts

; op | colour << 8 in A, x X, y Y, size kw x kh: draw in our window
rect:   sta     dblk
        stx     dblk+4
        sty     dblk+6
        lda     z:kw
        sta     dblk+8
        lda     z:kh
        sta     dblk+10
draw:   lda     z:win
        ldx     #.loword(dblk)
        ldy     #^dblk
        sys     SYS_WDRAW
        rts

; text z:sp (ours) in ink A at X, Y, UI font, no paper
text:   xba
        ora     #WD_TEXT
        sta     dblk
        lda     #$00FF
        sta     dblk+2
        stx     dblk+4
        sty     dblk+6
        lda     z:sp
        sta     dblk+12
        lda     #^fname
        sta     dblk+14
        bra     draw

; append the string at X (ours) to z:bp (zero-terminated; bp moves to the 0)
app:    ldy     #0
        sep     #$20
        .a8
:       lda     a:0,x
        sta     (bp),y
        beq     :+
        inx
        iny
        cpy     #60
        bcc     :-
        lda     #0
        sta     (bp),y
:       rep     #$20
        .a16
        tya
        clc
        adc     z:bp
        sta     z:bp
        rts

; append A in decimal
app_dec:
        sta     z:dv
        stz     z:dz                    ; a digit written (no leading zeros)
        ldx     #0
@d:     ldy     #'0'
:       lda     z:dv
        cmp     pow10,x
        bcc     :+
        sbc     pow10,x
        sta     z:dv
        iny
        bra     :-
:       tya
        cpx     #8                      ; the last digit always
        beq     :+
        cmp     #'0'
        bne     :+
        ldy     z:dz
        beq     @nx
:       sta     z:dz
        sep     #$20
        .a8
        sta     (bp)
        rep     #$20
        .a16
        inc     z:bp
@nx:    inx
        inx
        cpx     #10
        bcc     @d
        lda     #0
        sep     #$20
        .a8
        sta     (bp)
        rep     #$20
        .a16
        rts

        .segment "RODATA"
wopen:  .word   WX, WY, WW, WH
        .faraddr t_files
        .byte   WF_RESIZE
t_files: .byte  "Files", 0
s_added: .byte  "Added ", 0
s_added2: .byte " to the desktop", 0
ftab:   .addr   open, newwin, newdir, rename, delete, addesk, loop, quit
; (0.15) the pop-up menus' actions (A_*) and texts
A_OPEN  = 0
A_NEWW  = 1
A_EDIT  = 2
A_WRITE = 3
A_LOAD  = 4
A_SEP   = 5
A_COPY  = 6
A_DESK  = 7
A_REN   = 8
A_DEL   = 9
A_NEWF  = 10
A_PASTE = 11
A_UP    = 12
acttab: .addr   open, a_neww, a_edit, a_write, a_load, loop, copy, addesk, rename, delete
        .addr   newdir, paste, parent
acttxt: .addr   s_aopen, s_aneww, s_aedit, s_awrite, s_aload, s_asep, s_acopy, s_adesk
        .addr   s_aren, s_adel, s_anewf, s_apaste, s_aup
s_aopen: .byte  "Open", 9, "Enter", 0
s_aneww: .byte  "Open in new window", 0
s_aedit: .byte  "Open with Edit", 0
s_awrite: .byte "Open with Write", 0
s_aload: .byte  "Load into Atari", 0
s_asep: .byte   "-", 0
s_acopy: .byte  "Copy", 9, "Ctrl+C", 0
s_adesk: .byte  "Add to desktop", 0
s_aren: .byte   "Rename...", 0
s_adel: .byte   "Delete", 9, "Del", 0
s_anewf: .byte  "New folder...", 0
s_apaste: .byte "Paste", 9, "Ctrl+V", 0
s_aup:  .byte   "Parent folder", 9, "Backspace", 0
p_edit: .byte   "/BIN/EDIT.PRG", 0
p_write: .byte  "/BIN/WRITE.PRG", 0
t_edit: .byte   "Edit", 0
t_write: .byte  "Write", 0
dot:    .byte   ".", 0
dotdot: .byte   "..", 0
p_wfiles: .byte "/BIN/WFILES.PRG", 0
s_system: .byte "SYSTEM", 0
s_ftitle: .byte "Files: ", 0
s_d1:   .byte   "D1: ", 0
s_xex:  .byte   "    XEX: ", 0
s_cart: .byte   "    Cart: ", 0
s_none: .byte   "-", 0
s_open: .byte   "   (", 0
s_ent:  .byte   " entries", 0
s_ent1: .byte   " entry", 0
s_more: .byte   ", more not shown", 0
s_close: .byte  ")", 0
s_k:    .byte   " K", 0
s_empty: .byte  "(empty folder)", 0
s_copied: .byte "Copied ", 0
s_copying: .byte "Copying ", 0
s_of:   .byte   " of ", 0
s_kcolon: .byte " K: ", 0
s_copyof: .byte "Copy of ", 0
s_newf: .byte   "New folder", 0
s_del:  .byte   "Delete ", 0
s_qm:   .byte   "?", 0
s_cancel: .byte "Cancel", 0
s_delbtn: .byte "Delete", 0
t_newdir: .byte "New folder", 0
l_newdir: .byte "Name of the new folder:", 0
t_rename: .byte "Rename", 0
l_rename: .byte "New name:", 0
ak_newdir: .addr t_newdir, l_newdir, nbuf
        .word   NAMEMAX
        .addr   0
ak_rename: .addr t_rename, l_rename, nbuf
        .word   NAMEMAX
        .addr   0
t_delete: .byte "Delete", 0
al_del: .word   2, t_delete, atext, s_delbtn, s_cancel, 0
m_unk:  .byte   "Not an Atari file type", 0
m_img:  .byte   "Not a valid or supported image", 0
m_nf:   .byte   "File not found", 0
m_iop:  .byte   "The firmware menu is open. Close it and try again.", 0
m_err:  .byte   "Error ", 0
m_exists: .byte "That name is already in use there", 0
m_denied: .byte "Access denied", 0
m_badname: .byte "Not a valid name", 0
m_nomem: .byte  "Not enough memory", 0
m_cnom: .byte   "Not enough free memory for the cartridge", 0
m_long: .byte   "The path is too long", 0
m_self: .byte   "A folder cannot be moved into itself", 0
m_there: .byte  "It is already in that folder", 0
m_nofold: .byte "Folders cannot be copied", 0
m_noclip: .byte "The clipboard holds no file. Copy a file first.", 0
m_full: .byte   "The card is full", 0
m_full2: .byte  "The folder is not empty", 0
errtab: .word   $C3, m_unk, $C4, m_img, $44, m_nf, $45, m_nf, $C5, m_iop, $48, m_exists
        .word   $47, m_denied, $46, m_badname, ENOMEM, m_nomem, $01FF, m_full, 0
pow10:  .word   10000, 1000, 100, 10, 1
KUP     = 9                             ; kind: the ".." entry (after the FT_* types)
icons:  .addr   ic_blank, ic_folder, ic_atari, ic_prg, ic_page, ic_page, ic_pic, ic_page
        .addr   ic_page, ic_up
; the Up button's arrow: {w, h, dx, dy} from (9, 3) (centred in it), 0
uparrow: .word  2, 1, 1, 0,  4, 1, 0, 1,  6, 1, $FFFF, 2,  8, 1, $FFFE, 3,  2, 4, 1, 4,  0
.define IR(op, col, dx, dy, w, h) .word op | (col << 8), dx, dy, w, h
ic_folder:
        IR      WD_FRAME, C_BLACK, 4, 1, 6, 3       ; the tab
        IR      WD_FRAME, C_BLACK, 4, 3, 14, 8      ; the body
        IR      WD_FILL, C_YELLOW, 5, 2, 4, 2
        IR      WD_FILL, C_YELLOW, 5, 4, 12, 6
        .word   0
ic_up:                                              ; "..": a folder with an up arrow
        IR      WD_FRAME, C_BLACK, 4, 1, 6, 3
        IR      WD_FRAME, C_BLACK, 4, 3, 14, 8
        IR      WD_FILL, C_YELLOW, 5, 2, 4, 2
        IR      WD_FILL, C_YELLOW, 5, 4, 12, 6
        IR      WD_FILL, C_BLACK, 10, 4, 2, 1
        IR      WD_FILL, C_BLACK, 9, 5, 4, 1
        IR      WD_FILL, C_BLACK, 8, 6, 6, 1
        IR      WD_FILL, C_BLACK, 10, 7, 2, 3
        .word   0
ic_page:                                            ; a text: lines on a page
        IR      WD_FRAME, C_BLACK, 6, 0, 10, 12
        IR      WD_FILL, C_WHITE, 7, 1, 8, 10
        IR      WD_FILL, C_MID, 8, 3, 6, 1
        IR      WD_FILL, C_MID, 8, 5, 6, 1
        IR      WD_FILL, C_MID, 8, 7, 6, 1
        IR      WD_FILL, C_MID, 8, 9, 4, 1
        .word   0
ic_blank:                                           ; anything else: a blank page
        IR      WD_FRAME, C_BLACK, 6, 0, 10, 12
        IR      WD_FILL, C_WHITE, 7, 1, 8, 10
        IR      WD_FILL, C_LIGHT, 13, 1, 2, 2       ; (the folded corner)
        .word   0
ic_atari:                                           ; a cartridge
        IR      WD_FRAME, C_BLACK, 4, 1, 14, 7
        IR      WD_FILL, C_ORANGE, 5, 2, 12, 5
        IR      WD_FILL, C_RED, 7, 3, 8, 2          ; the label
        IR      WD_FRAME, C_BLACK, 6, 7, 10, 4      ; the edge connector
        IR      WD_FILL, C_YELLOW, 7, 8, 8, 2
        .word   0
ic_pic:                                             ; a picture: sky, sun, a hill
        IR      WD_FRAME, C_BLACK, 4, 1, 14, 10
        IR      WD_FILL, C_SELECT, 5, 2, 12, 8
        IR      WD_FILL, C_YELLOW, 13, 3, 3, 2
        IR      WD_FILL, C_GREEN, 5, 7, 12, 3
        IR      WD_FILL, C_GREEN, 8, 6, 5, 1
        .word   0
ic_prg:                                             ; a small window
        IR      WD_FRAME, C_BLACK, 4, 1, 14, 10
        IR      WD_FILL, C_TITLE, 5, 2, 12, 2
        IR      WD_FILL, C_SELECT, 5, 4, 12, 6
        IR      WD_FILL, C_WHITE, 7, 6, 6, 1
        .word   0

        .segment "DATA"
; the menus (written: the state byte of View > Show system files); 256 bytes are read
menus:  .byte   "File", 0, "Open", 9, "Enter", 0, "New window", 9, "Ctrl+N", 0
        .byte   "New folder...", 0, "Rename...", 0, "Delete", 9, "Del", 0
        .byte   "Add to desktop", 0, "-", 0
        .byte   "Close", 9, "Esc", 0, 0
        .byte   "Edit", 0, "Copy", 9, "Ctrl+C", 0, "Paste", 9, "Ctrl+V", 0, 0
        .byte   "View", 0
m_show: .byte   MS_STATE, "Show system files", 0, "-", 0, "Parent folder", 9, "Backspace", 0, 0
        .byte   0
        .res    256 - (* - menus)

        .segment "BSS"
DBUFLEN = 512
idx:    .res    MAXENT * 2
dbuf:   .res    DBUFLEN + 2
rblk:   .res    10
dblk:   .res    16
ev:     .res    8
fname:  .res    260
came:   .res    260
pbuf:   .res    300                     ; (0.15) a pop-up menu's items, their actions
pact:   .res    12
clblk2: .res    6                       ; clip_get: the clipboard's length
prefix: .res    32
tbuf:   .res    130
hbuf:   .res    220
fbuf:   .res    200
fbuf2:  .res    200
sbuf:   .res    16
pth:    .res    PMAX
pth2:   .res    PMAX
abuf:   .res    PMAX + 4
dropbuf: .res   130
clbuf:  .res    130
nbuf:   .res    NAMEMAX + 2
ibuf:   .res    260
atext:  .res    90
ttl:    .res    34
winf:   .res    8
winf2:  .res    8
st:     .res    10
sblk:   .res    8
rnblk:  .res    8
clblk:  .res    8
rwblk:  .res    8
argl:   .res    2
argx:   .res    2

        .segment "ZEROPAGE"
win:    .res    2
wsown:  .res    2
rl:     .res    2
cw:     .res    2
ch:     .res    2
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
tmp2:   .res    2
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
ry:     .res    2
fg:     .res    2
knd:    .res    2
nw:     .res    2
sx:     .res    2
fy:     .res    2
kw:     .res    2
kh:     .res    2
sp:     .res    2
bp:     .res    2
ip:     .res    2
fmax:   .res    2
flen:   .res    2
dv:     .res    2
dz:     .res    2
ex:     .res    2
pp:     .res    2
pe:     .res    2
bs:     .res    2
bn:     .res    2
sa:     .res    2
sb:     .res    2
ox:     .res    2
oy:     .res    2
pkey:   .res    2                       ; (0.15) the pop-up menus
pn:     .res    2
pk:     .res    2
pw:     .res    2
pl:     .res    2
pd:     .res    2
pq:     .res    2
pr:     .res    2
slot:   .res    2
soff:   .res    2
pressed: .res   2
dragging: .res  2
drg:    .res    2
px:     .res    2
py:     .res    2
tgt:    .res    2
isdir:  .res    2
hasup:  .res    2                       ; 1: entry 0 is ".."
atroot: .res    2                       ; 1: the folder is the root
showsys: .res   2                       ; View > Show system files
pp2:    .res    2
h1:     .res    2
h2:     .res    2
cbank:  .res    2
kdone:  .res    2
ktot:   .res    2
csize:  .res    4

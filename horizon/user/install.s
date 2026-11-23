; INSTALL - the Installer (/BIN/INSTALL.PRG, 0.29): apps from archives (.HZA), and their
; removal. An app is a folder in /APPS (sdk/docs/apps.md); its archive is a plain POSIX
; ustar file, uncompressed, holding that one folder with APP.INF in it.
;   install FILE.HZA          what it is (name, version, description, size, where it goes),
;                             "Install? (y/n)", then installed
;   install -y FILE.HZA       the same without the question (scripts, tests)
;   install -l FILE.HZA       its files listed, nothing installed
;   install -r NAME           the app /APPS/NAME removed (with everything in it), after a
;                             question (-y: none); NAME may be /APPS/NAME
;   install -w ...            the same in windows (alerts): Files and the Desktop start it so
;                             (a double click on an .HZA: "-w FILE"; Files' Remove app...:
;                             "-w -r /APPS/NAME")
; The archive is read twice: first its headers only (SEEK over the data: the checks, APP.INF,
; the sizes), then, after the question, from the start in pieces of 16 KB, each file written
; as it comes (never the whole archive in memory). The app is unpacked into /APPS/.INSTALL
; (deleted first if a failed install left it), then moved to /APPS/NAME. When that folder is
; there already (an update), the files of the old one that the archive does not have (saves,
; high scores, settings) are moved into the new one first, then the rest of the old one is
; deleted. Any error deletes /APPS/.INSTALL: the old app stays as it was. At the end
; /SYSTEM/APPS.NEW is made: the Desktop reads the apps again when its Programs menu opens.
; The archive: 512-byte records; a header (ustar: name + prefix, the "ustar" magic of POSIX
; or of GNU tar), then the data in records. Taken: files ('0', NUL, '7'), folders ('5');
; pax headers ('x', 'g') are skipped (their data is not read: the name in the ustar header
; is used); refused: GNU long names ('L', 'K'), links, devices, base-256 sizes. Every header's
; checksum is checked; the end is a record of zeros (a cut archive has none). Names: one top
; folder for everything; no "..", no absolute path, no empty part, no character below 32 or
; above 126 or any of \ : * ? " < > |, no part ending in '.' or ' ', no part starting with
; ' '; the top folder at most 32 characters and not starting with '.'; inside it a path of
; at most 112 characters, and /APPS/NAME/path at most 127.
; There is no call for the card's free space: a full card shows as a write that comes back
; short; the install then stops, deletes what it wrote, and says so.
; Each outcome is also one console line, in windows too (there it goes to the log), for
; scripts and tests to wait on: "install: installed /APPS/NAME", "install: replaced
; /APPS/NAME", "install: removed /APPS/NAME", "install: cancelled", "install: failed:
; REASON"; in windows the question too, before it is asked: "install: asks: Install
; /APPS/NAME" (Replace, Remove).
        .include "horizon.inc"
        .include "ui.inc"

RBL     = 16384                         ; the second pass's piece
NPRG    = 8                             ; .PRG names kept from the top folder
PRGL    = 40
MSGL    = 600
MAXD    = 16                            ; folders inside folders (the merge)

; errors (the message table's order)
E_OPEN  = 0
E_CUT   = 1
E_SUM   = 2
E_GNU   = 3
E_LINK  = 4
E_NAME  = 5
E_ROOT  = 6
E_LONG  = 7
E_NOINF = 8
E_NOPRG = 9
E_EMPTY = 10
E_FULL  = 11
E_WRITE = 12
E_READ  = 13
E_SIZE  = 14

        .segment "CODE"
        .a16
        .i16
start:  jsr     args_init               ; the options, then the path
        stz     z:fw
        stz     z:fy
        stz     z:fl
        stz     z:fr
@opt:   ldx     #.loword(path)
        ldy     #^path
        lda     #128
        jsr     next_arg
        jcs     usage
        lda     path
        cmp     #'-' | ('w' << 8)
        bne     :+
        inc     z:fw
        bra     @opt
:       cmp     #'-' | ('y' << 8)
        bne     :+
        inc     z:fy
        bra     @opt
:       cmp     #'-' | ('l' << 8)
        bne     :+
        inc     z:fl
        bra     @opt
:       cmp     #'-' | ('r' << 8)
        bne     :+
        inc     z:fr
        bra     @opt
:       lda     z:fw
        beq     @con
        sys     SYS_WSSTART             ; in windows
        bcc     :+
        stz     z:fw                    ; (no window system: the console)
        bra     @con
:       sta     z:wsown
        jsr     ui_init
        bra     @go
@con:   sys     SYS_ICLAIM              ; the keyboard (ours, or lent by the shell)
@go:    sys     SYS_INFO                ; this machine (for the needs)
        sta     hzver
        stx     hzrev
        lda     z:fr
        jne     remove
        jsr     scan                    ; first pass: what is it?
        bcc     :+
        jmp     fail
:       lda     z:fl
        beq     :+
        lda     #0
        jmp     quit
:       jsr     info                    ; the question
        bcs     @no
        jsr     isdest                  ; (the outcome: a new app or an update)
        lda     #.loword(o_inst)
        bcs     :+
        lda     #.loword(o_repl)
:       sta     ocx
        jsr     extract
        bcc     :+
        jmp     fail
:       jsr     m_start                 ; done
        ldx     #.loword(ui_apname)
        jsr     mcat
        ldx     #.loword(s_done)
        jsr     mcat
        lda     #AL_INFO
        ldx     #.loword(t_inst)
        jsr     say
        lda     #0
        jmp     quit
@no:    jmp     cancel

usage:  print   "install FILE.HZA     install an app (-y: no question, -l: list its files)\n"
        print   "install -r NAME      remove the app /APPS/NAME (-y: no question)\n"
        lda     #1
        jmp     quit

; the question answered no: said on the console, exit 0
cancel: ldx     #.loword(o_cancel)
        jsr     oline
        lda     #0
; A = the exit code: the window system stopped if we started it
quit:   pha
        lda     z:wsown
        beq     :+
        sys     SYS_WSSTOP
:       pla
        jmp     exit_a

; the error A (E_*) said (with the path or the entry's name) -> exit 1
fail:   pha
        jsr     m_start
        pla
        asl     a
        tax
        lda     omsg,x                  ; (the console's line)
        sta     ocx
        lda     emsg,x
        tax
        jsr     mfmt
        lda     #AL_ERROR
        ldx     #.loword(t_cant)
        jsr     say
        lda     #1
        jmp     quit

; ---------------------------------------------------------------- messages
m_start:
        stz     z:ml
        stz     msg
        rts
; string X appended to msg
mcat:   ldy     z:ml
        sep     #$20
        .a8
:       lda     a:0,x
        sta     msg,y
        beq     :+
        inx
        cpy     #MSGL - 2
        bcs     :+
        iny
        bra     :-
:       lda     #0
        sta     msg,y
        rep     #$20
        .a16
        sty     z:ml
        rts
; character A appended
mchr:   ldy     z:ml
        and     #$00FF
        sta     msg,y
        cpy     #MSGL - 2
        bcs     :+
        inc     z:ml
:       rts
; A appended in decimal
mdec:   ldy     #0                      ; the digits, lowest first, on the stack
@d:     ldx     #16                     ; A / 10: the quotient in t, the remainder in A
        sta     z:t
        lda     #0
@b:     asl     z:t
        rol     a
        cmp     #10
        bcc     :+
        sbc     #10
        inc     z:t
:       dex
        bne     @b
        pha
        iny
        lda     z:t
        bne     @d
:       pla
        clc
        adc     #'0'
        phy
        jsr     mchr
        ply
        dey
        bne     :-
        rts
; template X appended: '%' the path argument, '&' the entry's name (ename)
mfmt:   lda     a:0,x
        and     #$00FF
        beq     @out
        cmp     #'%'
        bne     :+
        phx
        ldx     #.loword(path)
        jsr     mcat
        plx
        bra     @nx
:       cmp     #'&'
        bne     :+
        phx
        ldx     #.loword(ename)
        jsr     mcat
        plx
        bra     @nx
:       phx
        jsr     mchr
        plx
@nx:    inx
        bra     mfmt
@out:   rts

; msg said: A = AL_* kind, X = the title (windows). In the console: printed (its lines),
; then the outcome line ocx. In windows: the outcome line, then an alert with OK -> A = 0
say:    sta     al
        stx     al+2
        lda     z:fw
        bne     :+
        ldx     #.loword(msg)
        ldy     #^msg
        jsr     out_str
        jsr     put_nl
        jsr     out_flush
        ldx     ocx
        jmp     oline
:       ldx     ocx
        jsr     oline
        lda     #.loword(msg)
        sta     al+4
        lda     #.loword(s_ok)
        sta     al+6
        stz     al+8
        stz     al+10
        ldx     #.loword(al)
        jmp     ui_alert

; msg asked: A = the default button's label (windows; the console: " (y/n) "), X = title.
; C clear: yes
ask:    sta     al+6
        stx     al+2
        lda     z:fw
        bne     @win
        ldx     #.loword(msg)
        ldy     #^msg
        jsr     out_str
        lda     z:fy                    ; (-y: no question)
        beq     :+
        jsr     put_nl
        jsr     out_flush
        bra     @yes
:
        print   " (y/n) "
        jsr     out_flush
        jsr     read_char
        pha
        jsr     put_char
        jsr     put_nl
        jsr     out_flush
        pla
        ora     #$20
        cmp     #'y'
        beq     @yes
        sec
        rts
@win:   lda     z:fy
        bne     @yes
        ldx     #.loword(o_ask)         ; "install: asks: Install /APPS/NAME"
        jsr     oline
        lda     #AL_QUESTION
        sta     al
        lda     #.loword(msg)
        sta     al+4
        lda     #.loword(s_cancel)
        sta     al+8
        stz     al+10
        ldx     #.loword(al)
        jsr     ui_alert
        cmp     #0
        bne     :+
@yes:   clc
        rts
:       sec
        rts

; the outcome line "install: ..." on the console, from the template X (0: none): '%' the
; path argument, '&' the entry's name, '@' dest, '#' the question's button (al+6)
oline:  cpx     #0
        beq     @out
        phx
        print   "install: "
        plx
@c:     lda     a:0,x
        and     #$00FF
        beq     @end
        phx
        ldy     #.loword(path)
        cmp     #'%'
        beq     @s
        ldy     #.loword(ename)
        cmp     #'&'
        beq     @s
        ldy     #.loword(dest)
        cmp     #'@'
        beq     @s
        ldy     al+6
        cmp     #'#'
        beq     @s
        jsr     put_char
        bra     @n
@s:     tyx
        ldy     #^path
        jsr     out_str
@n:     plx
        inx
        bra     @c
@end:   jsr     put_nl
        jmp     out_flush
@out:   rts

; ---------------------------------------------------------------- the first pass
; the archive's headers -> root, the counts, the size, APP.INF parsed (ui_ap*), the
; program found. C set: A = E_*
scan:   ldx     #.loword(path)
        ldy     #^path
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        lda     #E_OPEN
        rts
:       sta     z:fh
        stz     off
        stz     off+2
        stz     nfile
        stz     ndir
        stz     total
        stz     total+2
        stz     root
        stz     hasinf
        stz     nprg
        stz     infbuf
        stz     ename
@hdr:   lda     z:fh                    ; the header at off
        ldx     off
        ldy     off+2
        sys     SYS_SEEK
        lda     z:fh
        ldx     #.loword(hdr)
        ldy     #512
        jsr     fread
        cmp     #512
        beq     :+
        lda     #E_CUT
        jmp     @err
:       jsr     parse                   ; A = 0 end, 1 file, 2 folder, 3 skipped
        jcs     @err
        cmp     #0
        jeq     @end
        cmp     #1
        jne     @next
        inc     nfile                   ; a file: counted, its size added
        lda     size
        clc
        adc     total
        sta     total
        lda     size+2
        adc     total+2
        sta     total+2
        lda     z:fl                    ; (-l: listed)
        beq     :+
        print   "  "
        ldx     #.loword(rest)
        ldy     #^rest
        jsr     out_str
        print   "  "
        jsr     sizekb
        jsr     put_dec
        print   " KB\n"
:       ldx     #.loword(rest)          ; APP.INF: read (1023 bytes at most)
        ldy     #.loword(s_inf)
        jsr     strieq
        bcs     @prg
        lda     size+2
        bne     :+
        lda     size
        cmp     #1023
        bcc     :++
:       lda     #1023
:       tay
        lda     z:fh
        ldx     #.loword(infbuf)
        jsr     fread
        tax
        sep     #$20
        .a8
        stz     infbuf,x
        rep     #$20
        .a16
        lda     #1
        sta     hasinf
        bra     @next
@prg:   jsr     isprg                   ; a .PRG in the top folder: its name kept
        bcs     @next
        lda     nprg
        cmp     #NPRG
        bcs     :+
        jsr     prgslot
        tay
        ldx     #.loword(rest)
        jsr     ui_strcpy
:       inc     nprg
@next:  jsr     skipdata                ; off: the next header
        jmp     @hdr
@end:   lda     z:fh
        sys     SYS_CLOSE
        lda     root
        and     #$00FF
        bne     :+
        lda     #E_EMPTY
        sec
        rts
:       lda     hasinf
        bne     :+
        lda     #E_NOINF
        sec
        rts
:       ldx     #.loword(infbuf)        ; what it is
        jsr     ui_apparse
        lda     ui_apname
        and     #$00FF
        bne     :+
        ldx     #.loword(root)
        ldy     #.loword(ui_apname)
        jsr     ui_strcpy
:       jmp     findprg
@err:   pha
        lda     z:fh
        sys     SYS_CLOSE
        pla
        sec
        rts

; the program: program= (in the top folder), else ROOT.PRG, else the only .PRG. C set: none
findprg:
        lda     ui_apprg
        and     #$00FF
        beq     @def
        ldx     #.loword(ui_apprg)
        jsr     haveprg
        bcc     @ok
        lda     #E_NOPRG
        rts
@def:   ldx     #.loword(root)          ; ROOT.PRG
        ldy     #.loword(tmp)
        jsr     ui_strcpy
        clc
        adc     #.loword(tmp)
        tay
        ldx     #.loword(s_prg)
        jsr     ui_strcpy
        ldx     #.loword(tmp)
        jsr     haveprg
        bcc     @ok
        lda     nprg
        cmp     #1
        beq     @ok
        lda     #E_NOPRG
        sec
        rts
@ok:    clc
        rts
; C clear if the name X is one of the .PRG names kept
haveprg:
        stx     z:p1
        stz     z:i
:       lda     z:i
        cmp     nprg
        bcs     @no
        cmp     #NPRG
        bcs     @no
        jsr     prgslot
        tay
        ldx     z:p1
        jsr     strieq
        bcc     @yes
        inc     z:i
        bra     :-
@no:    sec
@yes:   rts
; A = n -> A = the n-th kept name's address
prgslot:
        asl     a                       ; x 40
        asl     a
        asl     a
        sta     z:t
        asl     a
        asl     a
        clc
        adc     z:t
        adc     #.loword(prgs)
        rts

; C clear if rest is "NAME.PRG" (no folder part)
isprg:  ldx     #.loword(rest)
        ldy     #0
:       lda     a:0,x
        and     #$00FF
        beq     :+
        cmp     #'/'
        beq     @no
        inx
        iny
        bra     :-
:       cpy     #5
        bcc     @no
        cpy     #PRGL
        bcs     @no
        dex
        dex
        dex
        dex
        lda     a:0,x
        cmp     #'.' | ('P' << 8)
        beq     :+
        cmp     #'.' | ('p' << 8)
        bne     @no
:       lda     a:2,x
        and     #$DFDF
        cmp     #'R' | ('G' << 8)
        bne     @no
        clc
        rts
@no:    sec
        rts

; off += 512 + the data (size rounded up to 512): the next header
skipdata:
        jsr     dsize
        lda     off
        clc
        adc     #512
        sta     off
        bcc     :+
        inc     off+2
:       lda     off
        clc
        adc     dsz
        sta     off
        lda     off+2
        adc     dsz+2
        sta     off+2
        rts
; dsz = size rounded up to 512 (0 for a folder)
dsize:  lda     size
        clc
        adc     #511
        and     #$FE00
        sta     dsz
        lda     size+2
        adc     #0
        sta     dsz+2
        rts

; A = the KB of size, rounded up (65535 at most)
sizekb: lda     size
        clc
        adc     #1023
        sta     z:t
        lda     size+2
        adc     #0
        cmp     #64
        bcc     :+
        lda     #$FFFF
        rts
:       xba                             ; (hi << 6) | (lo >> 10)
        and     #$FF00
        lsr     a
        lsr     a
        sta     z:t2
        lda     z:t
        xba
        and     #$00FF
        lsr     a
        lsr     a
        ora     z:t2
        rts

; handle A, X = buffer (this bank), Y = length -> A = bytes read (0 after an error)
fread:  sta     rw
        stx     rw+1
        lda     #^hdr
        sta     rw+3
        sty     rw+4
        ptr     rw
        sys     SYS_READ
        bcc     :+
        lda     #0
:       rts

; ---------------------------------------------------------------- a header
; hdr -> A = 0 the end (a record of zeros), 1 a file, 2 a folder, 3 skipped (a pax header,
; the top folder itself); for 1 and 2: ename the entry's name, rest its path inside the top
; folder, size its size. C set: A = E_* (ename: the name, when known)
parse:  ldx     #0                      ; zeros: the end
:       lda     hdr,x
        bne     :+
        inx
        inx
        cpx     #512
        bcc     :-
        lda     #0
        clc
        rts
:       stz     z:t                     ; the checksum: every byte, the field as spaces
        stz     z:t2
        ldx     #0
:       lda     hdr,x
        and     #$00FF
        cpx     #148
        bcc     :+
        cpx     #156
        bcs     :+
        lda     #' '
:       clc
        adc     z:t
        sta     z:t
        bcc     :+
        inc     z:t2
:       inx
        cpx     #512
        bcc     :---
        ldx     #148
        lda     #8
        jsr     octal
        bcs     @sum
        lda     num
        cmp     z:t
        bne     @sum
        lda     num+2
        cmp     z:t2
        beq     :+
@sum:   lda     #E_SUM
        sec
        rts
:       ldx     #124                    ; the size
        lda     #12
        jsr     octal
        bcc     :+
        lda     #E_SIZE
        rts
:       lda     num
        sta     size
        lda     num+2
        sta     size+2
        jsr     mkname                  ; ename ("./" or ".": the archive's own folder)
        lda     ename
        and     #$00FF
        beq     @skip
        cmp     #'.'
        bne     :+
        lda     ename+1
        and     #$00FF
        beq     @skip
:        lda     hdr+156                 ; the type
        and     #$00FF
        cmp     #'x'
        beq     @skip
        cmp     #'g'
        beq     @skip
        cmp     #'L'
        beq     @gnu
        cmp     #'K'
        bne     :+
@gnu:   lda     #E_GNU
        sec
        rts
@skip:  lda     #3
        clc
        rts
:       stz     z:isdir
        cmp     #'5'
        bne     :+
        inc     z:isdir
        bra     @typ
:       cmp     #'0'
        beq     @typ
        cmp     #'7'
        beq     @typ
        cmp     #0
        beq     @typ
        lda     #E_LINK
        sec
        rts
@typ:   jsr     names                   ; the name's checks, root, rest
        bcs     @out
        lda     z:isdir
        beq     :+
        stz     size                    ; (a folder has no data)
        stz     size+2
        lda     rest                    ; the top folder itself
        and     #$00FF
        bne     :++
        lda     #3
        clc
        rts
:       lda     rest
        and     #$00FF
        bne     :+
        lda     #E_ROOT                 ; (a file beside the top folder)
        sec
        rts
:       lda     z:isdir
        inc     a
        clc
@out:   rts

; the octal number of the field at hdr + X, A bytes -> num (32 bits). C set: not one (a
; base-256 number, a bad character, nothing)
octal:  sta     z:t3
        stz     num
        stz     num+2
        lda     hdr,x
        and     #$0080
        bne     @no
        ldy     #0                      ; digits seen
:       lda     hdr,x                   ; (leading blanks)
        and     #$00FF
        cmp     #' '
        bne     @dig
        inx
        dec     z:t3
        bne     :-
        bra     @end
@dig:   lda     hdr,x
        and     #$00FF
        beq     @end
        cmp     #' '
        beq     @end
        sec
        sbc     #'0'
        bcc     @no
        cmp     #8
        bcs     @no
        pha
        lda     num+2                   ; num * 8 + digit
        and     #$E000
        bne     @big
        asl     num
        rol     num+2
        asl     num
        rol     num+2
        asl     num
        rol     num+2
        pla
        ora     num
        sta     num
        iny
        inx
        dec     z:t3
        bne     @dig
@end:   cpy     #0
        beq     @no
        clc
        rts
@big:   pla
@no:    sec
        rts

; ename = the header's name: prefix "/" name (ustar, a prefix there), else name; "./"
; dropped at its start; z:isdir... (a '/' at its end is dropped by names)
mkname: ldy     #0
        lda     hdr+257                 ; "ustar"
        cmp     #'u' | ('s' << 8)
        bne     @nm
        lda     hdr+259
        cmp     #'t' | ('a' << 8)
        bne     @nm
        lda     hdr+345
        and     #$00FF
        beq     @nm
        ldx     #0                      ; the prefix (155 at most)
:       lda     hdr+345,x
        and     #$00FF
        beq     :+
        jsr     @put
        inx
        cpx     #155
        bcc     :-
:       lda     #'/'
        jsr     @put
@nm:    ldx     #0                      ; the name (100 at most)
:       lda     hdr,x
        and     #$00FF
        beq     :+
        jsr     @put
        inx
        cpx     #100
        bcc     :-
:       lda     #0
        jsr     @put
        ldx     #0                      ; "./" at the start dropped
:       lda     ename,x
        cmp     #'.' | ('/' << 8)
        bne     :+
        inx
        inx
        bra     :-
:       cpx     #0
        beq     @out
        txa
        clc
        adc     #.loword(ename)
        tax
        ldy     #.loword(ename)
        jmp     ui_strcpy
@out:   rts
@put:   cpy     #258
        bcs     :+
        sep     #$20
        .a8
        sta     ename,y
        rep     #$20
        .a16
        iny
:       rts

; ename checked: its parts (see the top), the top folder (root: set by the first entry,
; the same for all), rest = the path inside it. A '/' at the end: a folder (z:isdir). C set:
; A = E_*
names:  ldx     #.loword(ename)         ; a '/' at its end: a folder
        jsr     ui_strlen
        tay
        jeq     @bad
        lda     ename-1,y
        and     #$00FF
        cmp     #'/'
        bne     :+
        lda     #1
        sta     z:isdir
        lda     ename-1,y
        and     #$FF00
        sta     ename-1,y
:       stz     z:cs                    ; the parts: start, length
        ldx     #0
@part:  stx     z:cs
@ch:    lda     ename,x
        and     #$00FF
        beq     @pend
        cmp     #'/'
        beq     @pend
        cmp     #' '
        bcc     @bad
        cmp     #127
        bcs     @bad
        sta     z:t
        ldy     #0
:       lda     badch,y
        and     #$00FF
        cmp     z:t
        beq     @bad
        iny
        cpy     #9
        bcc     :-
        inx
        bra     @ch
@pend:  txa                             ; a part from cs to X: not empty, ".", ".."; not
        sec                             ; ending in '.' or ' ', not starting with ' '
        sbc     z:cs
        beq     @bad
        sta     z:cl
        ldy     z:cs
        lda     ename,y
        and     #$00FF
        cmp     #' '
        beq     @bad
        lda     ename-1,x
        and     #$00FF
        cmp     #'.'
        beq     @bad
        cmp     #' '
        beq     @bad
        lda     z:cs                    ; the first part: the top folder
        bne     @more
        lda     z:cl
        cmp     #33
        bcs     @long
        lda     ename
        and     #$00FF
        cmp     #'.'
        beq     @bad
        phx
        jsr     setroot
        plx
        bcs     @rootb
@more:  lda     ename,x
        and     #$00FF
        beq     @done
        inx
        bra     @part
@bad:   lda     #E_NAME
        sec
        rts
@long:  lda     #E_LONG
        sec
        rts
@rootb: lda     #E_ROOT
        sec
        rts
@done:  lda     ename,y                 ; rest: after "ROOT/" (Y: the end of root)
        ldx     z:rl                    ; (the top folder's length)
        lda     ename,x
        and     #$00FF
        beq     :+
        inx
:       txa
        clc
        adc     #.loword(ename)
        tax
        ldy     #.loword(rest)
        jsr     ui_strcpy
        cmp     #113                    ; the lengths: in .INSTALL and in /APPS/ROOT
        bcs     @long
        clc
        adc     z:rl
        cmp     #127 - 7 + 1
        bcs     @long
        clc
        rts

; the first part (cl characters) of ename: the top folder; the same as root (ignoring case),
; or root when there is none yet. C set: another one
setroot:
        lda     root
        and     #$00FF
        bne     @cmp
        ldx     #0
        sep     #$20
        .a8
:       lda     ename,x
        sta     root,x
        inx
        cpx     z:cl
        bcc     :-
        lda     #0
        sta     root,x
        rep     #$20
        .a16
        stx     z:rl
        clc
        rts
@cmp:   ldx     #0
:       lda     ename,x
        jsr     lowc
        sta     z:t
        lda     root,x
        jsr     lowc
        cmp     z:t
        bne     @no
        cmp     #0
        beq     @no                     ; (root ended first)
        inx
        cpx     z:cl
        bcc     :-
        lda     root,x                  ; and root ends here too
        and     #$00FF
        bne     @no
        clc
        rts
@no:    sec
        rts

lowc:   and     #$00FF
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
:       rts

; C clear if the strings X and Y are the same, ignoring case
strieq: stx     z:p1
        sty     z:p2
        ldy     #0
:       lda     (p1),y
        jsr     lowc
        sta     z:t
        lda     (p2),y
        jsr     lowc
        cmp     z:t
        bne     @no
        cmp     #0
        beq     @yes
        iny
        bra     :-
@yes:   clc
        rts
@no:    sec
        rts

; ---------------------------------------------------------------- the question
; msg: what it is; asked. C clear: install
info:   jsr     m_start
        ldx     #.loword(ui_apname)     ; "Digger 1.2"
        jsr     mcat
        lda     ui_apver
        and     #$00FF
        beq     :+
        lda     #' '
        jsr     mchr
        ldx     #.loword(ui_apver)
        jsr     mcat
:       lda     ui_apdesc
        and     #$00FF
        beq     :+
        ldx     #.loword(s_dash)
        jsr     mcat
        ldx     #.loword(ui_apdesc)
        jsr     mcat
:       lda     #10
        jsr     mchr
        lda     nfile                   ; "23 files, 412 KB, into /APPS/DIGGER."
        jsr     mdec
        ldx     #.loword(s_files)
        jsr     mcat
        lda     total
        sta     size
        lda     total+2
        sta     size+2
        jsr     sizekb
        jsr     mdec
        ldx     #.loword(s_kb)
        jsr     mcat
        jsr     mkdest
        ldx     #.loword(dest)
        jsr     mcat
        jsr     isdest                  ; an update?
        bcs     :+
        ldx     #.loword(s_upd)
        jsr     mcat
        bra     :++
:       lda     #'.'
        jsr     mchr
:       jsr     needs                   ; a warning when this machine lacks what it needs
        jsr     isdest
        lda     #.loword(s_inst)
        bcs     :+
        lda     #.loword(s_repl)
:
        ldx     #.loword(t_inst)
        jmp     ask

; dest = "/APPS/" root
mkdest: ldx     #.loword(s_apps)
        ldy     #.loword(dest)
        jsr     ui_strcpy
        ldx     #.loword(root)
        ldy     #.loword(dest + 6)
        jmp     ui_strcpy

; C clear if dest is a folder (the app is there)
isdest: ldx     #.loword(dest)
statdir:
        stx     sb
        lda     #^dest
        sta     sb+2
        lda     #.loword(st)
        sta     sb+3
        lda     #^st
        sta     sb+5
        ptr     sb
        sys     SYS_STAT
        bcs     :+
        lda     st+4
        and     #$0010
        beq     :+
        clc
        rts
:       sec
        rts

; ui_apneeds ("horizon=0.29,opl2,lau,sprites,blitter,rev=11,joystick,mem=1024K") against
; this machine: the first thing missing becomes a line of msg
needs:  ldx     #.loword(ui_apneeds)
@tok:   lda     a:0,x                   ; the next token
        and     #$00FF
        jeq     @out
        cmp     #','
        beq     :+
        cmp     #' '
        bne     @t
:       inx
        bra     @tok
@t:     stx     z:p1
        ldy     #.loword(n_hz)          ; horizon=M.m
        jsr     @is
        bcs     :+
        jsr     @ver
        sta     z:t3
        lda     hzver
        cmp     z:t3
        jcs     @next
        ldx     #.loword(w_hz)
        jsr     @warn
        lda     z:t3
        xba
        and     #$00FF
        jsr     mdec
        lda     #'.'
        jsr     mchr
        lda     z:t3
        and     #$00FF
        jsr     mdec
        ldx     #.loword(w_hz2)
        jmp     mcat
:       ldy     #.loword(n_opl)
        lda     #$0C
        jsr     @hw
        ldy     #.loword(n_lau)
        lda     #$0A
        jsr     @hw
        ldy     #.loword(n_spr)
        lda     #$0B
        jsr     @hw
        ldy     #.loword(n_bl)
        lda     #$08
        jsr     @hw
@next:  ldx     z:p1                    ; past the token
:       lda     a:0,x
        and     #$00FF
        beq     @out
        cmp     #','
        jeq     @tok
        inx
        bra     :-
@out:   rts
; the token at p1 named Y (letters up to '=', ',' or the end)? C clear: yes, X after it
@is:    ldx     z:p1
:       lda     a:0,y
        and     #$00FF
        beq     @end
        sta     z:t
        lda     a:0,x
        jsr     lowc
        cmp     z:t
        bne     @isn
        inx
        iny
        bra     :-
@end:   lda     a:0,x
        and     #$00FF
        beq     :+
        cmp     #'='
        beq     :+
        cmp     #','
        beq     :+
        cmp     #' '
        bne     @isn
:       clc
        rts
@isn:   sec
        rts
; "=M.m" at X -> A = M << 8 | m
@ver:   stz     z:t3
        lda     a:0,x
        and     #$00FF
        cmp     #'='
        bne     :+
        inx
:       jsr     @num
        xba
        sta     z:t3
        lda     a:0,x
        and     #$00FF
        cmp     #'.'
        bne     :+
        inx
        jsr     @num
        ora     z:t3
        rts
:       lda     z:t3
        rts
@num:   stz     z:t2
:       lda     a:0,x
        and     #$00FF
        sec
        sbc     #'0'
        bcc     :+
        cmp     #10
        bcs     :+
        pha
        lda     z:t2
        asl     a
        asl     a
        adc     z:t2
        asl     a
        sta     z:t2
        pla
        clc
        adc     z:t2
        sta     z:t2
        inx
        bra     :-
:       lda     z:t2
        and     #$00FF
        rts
; the hardware token Y needing revision A: when the token is it and this board is older,
; the warning, and the rest of needs is not looked at (the return address dropped)
@hw:    sta     z:t3
        jsr     @is
        bcs     @hwo
        lda     hzrev
        cmp     z:t3
        bcs     @hwo
        ldx     #.loword(w_hw)
        jsr     @warn
        ldx     z:p1
:       lda     a:0,x                   ; the token's name
        and     #$00FF
        beq     :+
        cmp     #','
        beq     :+
        phx
        jsr     mchr
        plx
        inx
        bra     :-
:       ldx     #.loword(w_hw2)
        jsr     mcat
        lda     z:t3
        jsr     mhex
        ldx     #.loword(w_hw3)
        jsr     mcat
        lda     hzrev
        jsr     mhex
        lda     #')'
        jsr     mchr
        pla                             ; (not back to the token loop: done)
@hwo:   rts
@warn:  phx
        lda     #10
        jsr     mchr
        plx
        jmp     mcat

; A appended as two hex digits
mhex:   pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @d
        pla
@d:     and     #$000F
        tax
        lda     hexd,x
        jmp     mchr

; ---------------------------------------------------------------- the second pass
; the archive unpacked into /APPS/.INSTALL, then moved to dest. C set: A = E_*
extract:
        jsr     progopen
        ptr     s_apps0                 ; /APPS (there already: an error, fine)
        sys     SYS_MKDIR
        ldx     #.loword(s_tmp)         ; a failed install's leftovers
        jsr     ui_rmtree
        ptr     s_tmp
        sys     SYS_MKDIR
        bcc     :+
        lda     #E_WRITE
        jmp     @ret
:       ldx     #.loword(path)
        ldy     #^path
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        lda     #E_OPEN
        jmp     @clean
:       sta     z:fh
        stz     z:rbp
        stz     z:rbl
        stz     ndone
@hdr:   jsr     getrec                  ; the next header
        jcs     @errc
        ldy     #0                      ; -> hdr
:       lda     rb,x
        sta     hdr,y
        inx
        inx
        iny
        iny
        cpy     #512
        bcc     :-
        jsr     parse
        jcs     @errc
        cmp     #0
        jeq     @end
        cmp     #2
        bne     :+
        jsr     mktmp                   ; a folder: made
        jsr     mkparents
        ptr     tmp
        sys     SYS_MKDIR
        bra     @hdr
:       cmp     #1
        beq     @file
        jsr     dsize                   ; skipped: its data too
        jsr     consume
        jcs     @errc
        bra     @hdr
@file:  jsr     mktmp
        jsr     mkparents
        ptr     tmp
        lda     #O_CREATE
        sys     SYS_OPEN
        bcc     :+
        lda     #E_WRITE
        jmp     @errc
:       sta     z:oh
        lda     size                    ; the data, as it comes
        sta     left
        lda     size+2
        sta     left+2
@data:  lda     left
        ora     left+2
        beq     @fend
        lda     z:rbp
        cmp     z:rbl
        bcc     :+
        jsr     refill
        jcs     @erro
:       lda     z:rbl                   ; n = min(the bytes there, left)
        sec
        sbc     z:rbp
        ldx     left+2
        bne     :+
        cmp     left
        bcc     :+
        lda     left
:       sta     z:n
        lda     z:oh
        sta     rw
        lda     z:rbp
        clc
        adc     #.loword(rb)
        sta     rw+1
        lda     #^rb
        sta     rw+3
        lda     z:n
        sta     rw+4
        ptr     rw
        sys     SYS_WRITE
        bcs     @werr
        cmp     z:n
        bne     @full
        lda     z:rbp
        clc
        adc     z:n
        sta     z:rbp
        lda     left
        sec
        sbc     z:n
        sta     left
        bcs     @data
        dec     left+2
        bra     @data
@fend:  lda     z:oh                    ; the file closed (C set: written in part)
        sys     SYS_CLOSE
        bcs     @full2
        lda     size                    ; its padding to 512 skipped
        eor     #$FFFF
        inc     a
        and     #511
        sta     dsz
        stz     dsz+2
        jsr     consume
        jcs     @errc
        inc     ndone
        jsr     progress
        jmp     @hdr
@werr:  lda     z:oh
        sys     SYS_CLOSE
        lda     #E_WRITE
        bra     @errc
@full:  lda     z:oh
        sys     SYS_CLOSE
@full2: lda     #E_FULL
        bra     @errc
@erro:  pha
        lda     z:oh
        sys     SYS_CLOSE
        pla
@errc:  pha
        lda     z:fh
        sys     SYS_CLOSE
        pla
@clean: pha                             ; what was written deleted
        jsr     progclose
        ldx     #.loword(s_tmp)
        jsr     ui_rmtree
        pla
@ret:   sec
        rts
@end:   lda     z:fh
        sys     SYS_CLOSE
        jsr     isdest                  ; an update: the old one's own files kept
        bcs     :+
        jsr     merge
        ldx     #.loword(dest)
        jsr     ui_rmtree
:       lda     #.loword(s_tmp)         ; the new folder becomes the app
        sta     rn
        lda     #^s_tmp
        sta     rn+2
        lda     #.loword(dest)
        sta     rn+3
        lda     #^dest
        sta     rn+5
        ptr     rn
        sys     SYS_RENAME
        bcc     :+
        jsr     progclose               ; (nothing deleted: /APPS/.INSTALL holds the app)
        lda     #E_WRITE
        sec
        rts
:       ptr     s_rescan                ; the Desktop: read the apps again
        lda     #O_CREATE
        sys     SYS_OPEN
        bcs     :+
        sys     SYS_CLOSE
:       jsr     progclose
        clc
        rts

; X = rb's next record (512 bytes there). C set: A = E_CUT
getrec: lda     z:rbp
        cmp     z:rbl
        bcc     :+
        jsr     refill
        bcs     @out
:       lda     z:rbl
        sec
        sbc     z:rbp
        cmp     #512
        bcc     @cut
        ldx     z:rbp
        txa
        clc
        adc     #512
        sta     z:rbp
        clc
@out:   rts
@cut:   lda     #E_CUT
        sec
        rts
; rb read again from the archive. C set: A = E_CUT (nothing more) or E_READ
refill: stz     z:rbp
        lda     z:fh
        sta     rw
        lda     #.loword(rb)
        sta     rw+1
        lda     #^rb
        sta     rw+3
        lda     #RBL
        sta     rw+4
        ptr     rw
        sys     SYS_READ
        bcs     @err
        sta     z:rbl
        cmp     #0
        beq     @cut
        clc
        rts
@cut:   lda     #E_CUT
        sec
        rts
@err:   stz     z:rbl
        lda     #E_READ
        sec
        rts
; dsz bytes of the archive passed over. C set: A = E_*
consume:
:       lda     dsz
        ora     dsz+2
        beq     @ok
        lda     z:rbp
        cmp     z:rbl
        bcc     :+
        jsr     refill
        bcs     @out
:       lda     z:rbl
        sec
        sbc     z:rbp
        ldx     dsz+2
        bne     :+
        cmp     dsz
        bcc     :+
        lda     dsz
:       sta     z:n
        clc
        adc     z:rbp
        sta     z:rbp
        lda     dsz
        sec
        sbc     z:n
        sta     dsz
        bcs     :---
        dec     dsz+2
        bra     :---
@ok:    clc
@out:   rts

; tmp = "/APPS/.INSTALL/" rest
mktmp:  ldx     #.loword(s_tmp)
        ldy     #.loword(tmp)
        jsr     ui_strcpy
        tay
        lda     #'/'
        sta     tmp,y
        tya
        clc
        adc     #.loword(tmp + 1)
        tay
        ldx     #.loword(rest)
        jmp     ui_strcpy

; the folders on tmp's way made (each '/' after "/APPS/.INSTALL/"; errors: there already)
mkparents:
        ldx     #15
@c:     lda     tmp,x
        and     #$00FF
        beq     @out
        cmp     #'/'
        bne     @nx
        phx
        sep     #$20
        .a8
        stz     tmp,x
        rep     #$20
        .a16
        ptr     tmp
        sys     SYS_MKDIR
        plx
        lda     #'/'
        sep     #$20
        .a8
        sta     tmp,x
        rep     #$20
        .a16
@nx:    inx
        bra     @c
@out:   rts

; ---------------------------------------------------------------- an update
; the old app's files that the new one does not have moved into it (a folder there in both:
; looked into; a name in both: the new one stays, the old one is deleted with its folder)
merge:  ldx     #.loword(dest)
        ldy     #.loword(po)
        jsr     ui_strcpy
        ldx     #.loword(s_tmp)
        ldy     #.loword(pn)
        jsr     ui_strcpy
        stz     z:dep
        stz     mskip
@next:  lda     z:dep                   ; the next entry of po
        asl     a
        tax
        lda     mskip,x
        jsr     rd1
        jcs     @up
        ldx     #.loword(po)            ; po/name, pn/name
        jsr     addname
        jcs     @skip
        ldx     #.loword(pn)
        jsr     addname
        bcs     @skip
        ldx     #.loword(pn)            ; in the new one?
        stx     sb
        lda     #^pn
        sta     sb+2
        lda     #.loword(st)
        sta     sb+3
        lda     #^st
        sta     sb+5
        ptr     sb
        sys     SYS_STAT
        bcs     @move
        lda     st+4                    ; both folders: into them
        and     #$0010
        beq     @skip2
        lda     dbuf+4
        and     #$0010
        beq     @skip2
        lda     z:dep
        cmp     #MAXD - 1
        bcs     @skip2
        inc     z:dep
        lda     z:dep
        asl     a
        tax
        stz     mskip,x
        bra     @next
@move:  lda     #.loword(po)            ; not in the new one: moved there
        sta     rn
        lda     #^po
        sta     rn+2
        lda     #.loword(pn)
        sta     rn+3
        lda     #^pn
        sta     rn+5
        ptr     rn
        sys     SYS_RENAME
        php
        ldx     #.loword(po)            ; (the old folder has one entry less: the same skip)
        jsr     cutname
        ldx     #.loword(pn)
        jsr     cutname
        plp
        jcc     @next
        bra     @skip3                  ; (not moved: passed over)
@skip2: ldx     #.loword(pn)
        jsr     cutname
@skip:  ldx     #.loword(po)
        jsr     cutname
@skip3: lda     z:dep
        asl     a
        tax
        inc     mskip,x
        jmp     @next
@up:    lda     z:dep
        beq     @out
        dec     z:dep
        ldx     #.loword(po)
        jsr     cutname
        ldx     #.loword(pn)
        jsr     cutname
        bra     @skip3
@out:   rts

; one entry of folder po (skip A) -> dbuf (u32 size, u8 attr), dname. C set: none
rd1:    sta     rd+8
        lda     #.loword(po)
        sta     rd
        lda     #^po
        sta     rd+2
        lda     #.loword(dbuf)
        sta     rd+3
        lda     #^dbuf
        sta     rd+5
        lda     #300
        sta     rd+6
        ptr     rd
        sys     SYS_READDIR
        bcs     @no
        cmp     #0
        beq     @no
        lda     dbuf+5
        and     #$00FF
        tay
        ldx     #0
        sep     #$20
        .a8
:       cpy     #0
        beq     :+
        lda     dbuf+6,x
        sta     dname,x
        inx
        dey
        bra     :-
:       stz     dname,x
        rep     #$20
        .a16
        clc
        rts
@no:    sec
        rts
; path X += "/" dname (127 at most). C set: too long (unchanged)
addname:
        stx     z:p1
        jsr     ui_strlen
        sta     z:t
        ldx     #.loword(dname)
        jsr     ui_strlen
        sec
        adc     z:t
        cmp     #128
        bcs     @out
        lda     z:t
        clc
        adc     z:p1
        tay
        lda     #'/'
        sta     a:0,y
        iny
        ldx     #.loword(dname)
        jsr     ui_strcpy
        clc
@out:   rts
; path X: its last part cut ("/APPS/X/Y" -> "/APPS/X"). C clear
cutname:
        stx     z:p1
        jsr     ui_strlen
        tay
:       dey
        beq     :+
        lda     (p1),y
        and     #$00FF
        cmp     #'/'
        bne     :-
        sep     #$20
        .a8
        lda     #0
        sta     (p1),y
        rep     #$20
        .a16
:       clc
        rts

; ---------------------------------------------------------------- progress (windows)
; a small window "Installing NAME..." with the files done (only with -w)
progopen:
        lda     z:fw
        beq     @out
        ldx     #.loword(s_ining)
        ldy     #.loword(pgt1)
        jsr     ui_strcpy
        clc
        adc     #.loword(pgt1)
        tay
        ldx     #.loword(ui_apname)
        jsr     ui_strcpy
        stz     pgt2
        ldx     #.loword(pdlg)
        jsr     ui_dlgopen
        bcs     @out
        lda     #1
        sta     z:pgon
@out:   rts
progress:
        lda     z:pgon
        beq     @out
        jsr     m_start                 ; "12 of 23 files"
        lda     ndone
        jsr     mdec
        ldx     #.loword(s_of)
        jsr     mcat
        lda     nfile
        jsr     mdec
        ldx     #.loword(s_files2)
        jsr     mcat
        ldx     #.loword(msg)
        ldy     #.loword(pgt2)
        jsr     ui_strcpy
        ldx     #.loword(plab2)
        jsr     ui_draw
@out:   rts
progclose:
        lda     z:pgon
        beq     :+
        stz     z:pgon
        ldx     #.loword(pdlg)
        jmp     ui_dlgclose
:       rts

; ---------------------------------------------------------------- removing an app
remove: lda     path                    ; NAME or /APPS/NAME
        and     #$00FF
        cmp     #'/'
        beq     :+
        ldx     #.loword(path)
        ldy     #.loword(tmp)
        jsr     ui_strcpy
        ldx     #.loword(s_apps)
        ldy     #.loword(dest)
        jsr     ui_strcpy
        ldx     #.loword(tmp)
        ldy     #.loword(dest + 6)
        jsr     ui_strcpy
        bra     @chk
:       ldx     #.loword(path)
        ldy     #.loword(dest)
        jsr     ui_strcpy
@chk:   ldx     #.loword(dest)          ; "/APPS/X" exactly (no other '/', not X empty)
        ldy     #.loword(s_apps)
        jsr     prefix
        jcs     @bad
        ldx     #6
        lda     dest,x
        and     #$00FF
        jeq     @bad
        cmp     #'.'
        jeq     @bad
:       lda     dest,x
        and     #$00FF
        beq     :+
        cmp     #'/'
        jeq     @bad
        inx
        bra     :-
:       jsr     isdest
        jcs     @none
        ldx     #.loword(dest)          ; its name (APP.INF)
        jsr     ui_appinf
        lda     ui_apname
        and     #$00FF
        bne     :+
        ldx     #.loword(dest + 6)
        ldy     #.loword(ui_apname)
        jsr     ui_strcpy
:       jsr     m_start                 ; "Remove the app Digger (/APPS/DIGGER)..."
        ldx     #.loword(s_rm1)
        jsr     mcat
        ldx     #.loword(ui_apname)
        jsr     mcat
        ldx     #.loword(s_rm2)
        jsr     mcat
        ldx     #.loword(dest)
        jsr     mcat
        ldx     #.loword(s_rm3)
        jsr     mcat
        lda     #.loword(s_remove)
        ldx     #.loword(t_rm)
        jsr     ask
        jcs     cancel
        ldx     #.loword(dest)
        jsr     ui_rmtree
        bcs     @err
        lda     #.loword(o_rmd)
        sta     ocx
        jsr     m_start
        ldx     #.loword(ui_apname)
        jsr     mcat
        ldx     #.loword(s_rmd)
        jsr     mcat
        lda     #AL_INFO
        ldx     #.loword(t_rm)
        jsr     say
        lda     #0
        jmp     quit
@bad:   ldx     #.loword(o_notapp)
        ldy     #.loword(m_notapp)
        bra     :+
@none:  ldx     #.loword(o_noapp)
        ldy     #.loword(m_noapp)
        bra     :+
@err:   ldx     #.loword(o_rmerr)
        ldy     #.loword(m_rmerr)
:       stx     ocx
        phy
        jsr     m_start
        plx
        jsr     mfmt
        lda     #AL_ERROR
        ldx     #.loword(t_rm)
        jsr     say
        lda     #1
        jmp     quit

; C clear if string X starts with string Y (ignoring case)
prefix: stx     z:p1
        sty     z:p2
        ldy     #0
:       lda     (p2),y
        and     #$00FF
        beq     @yes
        jsr     lowc
        sta     z:t
        lda     (p1),y
        jsr     lowc
        cmp     z:t
        bne     @no
        iny
        bra     :-
@yes:   clc
        rts
@no:    sec
        rts

        .segment "RODATA"
s_apps: .byte   "/APPS/", 0
s_apps0: .byte  "/APPS", 0
s_tmp:  .byte   "/APPS/.INSTALL", 0
s_rescan: .byte "/SYSTEM/APPS.NEW", 0
s_inf:  .byte   "APP.INF", 0
s_prg:  .byte   ".PRG", 0
s_ok:   .byte   "OK", 0
s_cancel: .byte "Cancel", 0
s_inst: .byte   "Install", 0
s_repl: .byte   "Replace", 0
s_remove: .byte "Remove", 0
s_dash: .byte   " - ", 0
s_files: .byte  " files, ", 0
s_files2: .byte " files", 0
s_of:   .byte   " of ", 0
s_kb:   .byte   " KB, into ", 0
s_upd:  .byte   " (an update: your own files there stay).", 0
s_done: .byte   " is installed: it is in the Programs menu.", 0
s_ining: .byte  "Installing ", 0
s_rm1:  .byte   "Remove the app ", 0
s_rm2:  .byte   " (", 0
s_rm3:  .byte   ")", 10, "and everything in that folder, saves too?", 0
s_rmd:  .byte   " was removed.", 0
t_inst: .byte   "Install app", 0
t_rm:   .byte   "Remove app", 0
t_cant: .byte   "Cannot install", 0
n_hz:   .byte   "horizon", 0
n_opl:  .byte   "opl2", 0
n_lau:  .byte   "lau", 0
n_spr:  .byte   "sprites", 0
n_bl:   .byte   "blitter", 0
w_hz:   .byte   "It may not run here: it needs Horizon ", 0
w_hz2:  .byte   " or later.", 0
w_hw:   .byte   "It may not run here: it needs ", 0
w_hw2:  .byte   " (hardware revision $", 0
w_hw3:  .byte   "; this board is $", 0
hexd:   .byte   "0123456789ABCDEF"
badch:  .byte   $5C, ":*?", $22, "<>|", 127
m_notapp: .byte "% is not an app's folder (/APPS/NAME).", 0
m_noapp: .byte  "There is no app % in /APPS.", 0
m_rmerr: .byte  "% could not be removed completely.", 0
emsg:   .addr   e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12, e13, e14
e0:     .byte   "% cannot be opened.", 0
e1:     .byte   "% is cut short: the archive is damaged.", 0
e2:     .byte   "% is damaged (a header's checksum is wrong).", 0
e3:     .byte   "% uses GNU tar's long names (more than 100", 10
        .byte   "characters). Pack it with hzapp.py, or with", 10
        .byte   "tar --format=ustar.", 0
e4:     .byte   "% holds a link or a device:", 10, "&", 10, "Only files and folders can be installed.", 0
e5:     .byte   "% holds a name that is not safe:", 10, "&", 0
e6:     .byte   "% must hold one folder (the app) with", 10
        .byte   "everything in it; this is outside it:", 10, "&", 0
e7:     .byte   "% holds a name too long for the card:", 10, "&", 0
e8:     .byte   "% has no APP.INF in its folder:", 10, "it is not a Horizon app.", 0
e9:     .byte   "% has no program: APP.INF must name it", 10
        .byte   "(program=NAME.PRG), or the folder must hold one.", 0
e10:    .byte   "% is empty.", 0
e11:    .byte   "The card is full. Nothing was installed", 10
        .byte   "(what was written is deleted again).", 0
e12:    .byte   "Cannot write to the card. Nothing was installed.", 0
e13:    .byte   "% could not be read to its end.", 0
e14:    .byte   "% holds a file too large (its size).", 0

; the console's lines (oline)
o_inst: .byte   "installed @", 0
o_repl: .byte   "replaced @", 0
o_rmd:  .byte   "removed @", 0
o_cancel: .byte "cancelled", 0
o_ask:  .byte   "asks: # @", 0
o_notapp: .byte "failed: % is not an app's folder (/APPS/NAME)", 0
o_noapp: .byte  "failed: there is no app %", 0
o_rmerr: .byte  "failed: % could not be removed completely", 0
omsg:   .addr   f0, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14
f0:     .byte   "failed: % cannot be opened", 0
f1:     .byte   "failed: % is cut short", 0
f2:     .byte   "failed: % is damaged (a checksum)", 0
f3:     .byte   "failed: % uses GNU tar's long names", 0
f4:     .byte   "failed: a link or a device: &", 0
f5:     .byte   "failed: a name that is not safe: &", 0
f6:     .byte   "failed: outside the app's folder: &", 0
f7:     .byte   "failed: a name too long: &", 0
f8:     .byte   "failed: no APP.INF", 0
f9:     .byte   "failed: no program", 0
f10:    .byte   "failed: % is empty", 0
f11:    .byte   "failed: the card is full", 0
f12:    .byte   "failed: cannot write to the card", 0
f13:    .byte   "failed: % could not be read", 0
f14:    .byte   "failed: % holds a file too large", 0

        .segment "DATA"
al:     .word   0, 0, 0, 0, 0, 0        ; the alert
; the progress window: two labels
pdlg:   .word   t_inst, 300, 44, plist, 0
plist:  .addr   plab1, plab2, 0
plab1:  .byte   UT_LABEL, 0
        .word   8, 8, 284, UI_LINE, 0, pgt1
plab2:  .byte   UT_LABEL, 0
        .word   8, 24, 284, UI_LINE, 0, pgt2

        .segment "BSS"
path:   .res    130                     ; the argument
ename:  .res    260                     ; an entry's name
rest:   .res    260                     ; its path inside the top folder
root:   .res    40                      ; the top folder
dest:   .res    140                     ; /APPS/ROOT
tmp:    .res    300
po:     .res    140                     ; the merge: the old folder, the new one
pn:     .res    140
dname:  .res    260
dbuf:   .res    302
mskip:  .res    MAXD * 2
hdr:    .res    512
infbuf: .res    1026
prgs:   .res    NPRG * PRGL
msg:    .res    MSGL
pgt1:   .res    64
pgt2:   .res    64
off:    .res    4
size:   .res    4
dsz:    .res    4
num:    .res    4
total:  .res    4
left:   .res    4
nfile:  .res    2
ndir:   .res    2
ndone:  .res    2
hasinf: .res    2
nprg:   .res    2
hzver:  .res    2
hzrev:  .res    2
ocx:    .res    2                       ; the outcome line's template (oline), 0: none
rw:     .res    6
rd:     .res    10
rn:     .res    6
sb:     .res    6
st:     .res    10
rb:     .res    RBL

        .segment "ZEROPAGE"
fw:     .res    2                       ; -w, -y, -l, -r
fy:     .res    2
fl:     .res    2
fr:     .res    2
wsown:  .res    2                       ; we started the window system
fh:     .res    2                       ; the archive, the file written
oh:     .res    2
rbp:    .res    2                       ; rb: the next byte, the bytes there
rbl:    .res    2
n:      .res    2
ml:     .res    2                       ; msg's length
t:      .res    2
t2:     .res    2
t3:     .res    2
i:      .res    2
p1:     .res    2
p2:     .res    2
isdir:  .res    2
cs:     .res    2
cl:     .res    2
rl:     .res    2
dep:    .res    2
pgon:   .res    2

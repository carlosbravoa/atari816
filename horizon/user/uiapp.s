; uiapp.s - controls library (0.29): apps. An app is a folder under /APPS with its program,
; its files and APP.INF, a small text file of "key=value" lines (sdk/docs/apps.md):
;   name=Digger                 the name in the Programs menu (24 characters; default: the
;                               folder's name)
;   program=DIGGER.PRG          the program file in the folder (default: FOLDER.PRG, else
;                               the only .PRG there)
;   icon=PROGRAM                a built-in icon's name, or a 32 x 32 icon file in the folder
;   types=DIG,DLV               the file types (extensions) the app opens
;   category=Games              a submenu of Programs
;   version=1.2  description=...  needs=...   shown by the installer
;   args=-fast                  (0.31) the arguments the Desktop starts it with (127
;                               characters; the user's NAME.ARG is added after them)
;   console=yes                 (0.31) started in a Terminal window (yes: kept open at the
;                               end; error: closed by itself when it ends with code 0)
; Lines starting with '#' and unknown keys are ignored; keys ignore case; blanks around the
; key and the value are dropped; CR LF or LF; only the first 1023 bytes are read.
; Uses the library's zero page (ui_p, ui_q) and ui_strcpy. See ui.inc.
        .include "horizon.inc"
        .include "ui.inc"

AP_BUFL = 1024                          ; APP.INF read at most (with its 0)
AP_DBL  = 300                           ; a READDIR buffer: the path, then one entry

        .segment "CODE"
        .a16
        .i16

; X = an app's folder ("/APPS/DIGGER", no '/' at the end) -> its APP.INF read and parsed
; (ui_apparse), ui_approg the program's full path. C clear: an app (its program file is
; there); C set: not one (no program).
ui_appinf:
        ldy     #.loword(ap_dir)
        jsr     ui_strcpy
        cmp     #96                     ; (room for "/" and a name in a path of 127)
        jcs     @no
        ldx     #.loword(ap_dir)        ; the folder's name (after the last '/')
        stx     ap_t
:       lda     a:0,x
        and     #$00FF
        beq     :++
        inx
        cmp     #'/'
        bne     :+
        stx     ap_t
:       bra     :--
:       ldx     #.loword(ap_dir)        ; the file
        ldy     #.loword(ap_path)
        jsr     ui_strcpy
        clc
        adc     #.loword(ap_path)
        tay
        ldx     #.loword(ap_sinf)
        jsr     ui_strcpy
        stz     ap_buf
        ldx     #.loword(ap_path)
        ldy     #^ap_path
        lda     #O_READ
        sys     SYS_OPEN
        bcs     @parse                  ; (none: the defaults)
        sta     ap_rw
        sta     ap_h
        lda     #.loword(ap_buf)
        sta     ap_rw+1
        lda     #^ap_buf
        sta     ap_rw+3
        lda     #AP_BUFL - 1
        sta     ap_rw+4
        ldx     #.loword(ap_rw)
        ldy     #^ap_rw
        sys     SYS_READ
        bcc     :+
        lda     #0
:       tax
        sep     #$20
        .a8
        stz     ap_buf,x
        rep     #$20
        .a16
        lda     ap_h
        sys     SYS_CLOSE
@parse: ldx     #.loword(ap_buf)
        jsr     ui_apparse
        lda     ui_apname               ; the name: the folder's by default
        and     #$00FF
        bne     :+
        ldx     ap_t
        ldy     #.loword(ui_apname)
        lda     #24
        jsr     ap_ncpy
:       ldx     #.loword(ap_dir)        ; the program: "folder/" + its name
        ldy     #.loword(ui_approg)
        jsr     ui_strcpy
        clc
        adc     #.loword(ui_approg)
        tay
        lda     #'/'
        sta     a:0,y
        iny
        sty     ap_e
        lda     ui_apprg
        and     #$00FF
        beq     @find
        ldx     #.loword(ui_apprg)        ; named in APP.INF: must be there
        ldy     ap_e
        jsr     ui_strcpy
        jsr     ap_isfile
        bcs     @no
        clc
        rts
@find:  ldx     ap_t                    ; FOLDER.PRG
        ldy     ap_e
        jsr     ui_strcpy
        clc
        adc     ap_e
        tay
        ldx     #.loword(ap_sprg)
        jsr     ui_strcpy
        jsr     ap_isfile
        bcs     :+
        rts
:       jmp     ap_only                 ; else the only .PRG
@no:    sec
        rts

; C clear if ui_approg is a file
ap_isfile:
        lda     #.loword(ui_approg)
        sta     ap_sb
        lda     #^ui_approg
        sta     ap_sb+2
        lda     #.loword(ap_st)
        sta     ap_sb+3
        lda     #^ap_st
        sta     ap_sb+5
        ldx     #.loword(ap_sb)
        ldy     #^ap_sb
        sys     SYS_STAT
        bcs     :+
        lda     ap_st+4
        and     #$0010
        beq     :+
        sec
:       rts

; the folder ap_dir's only .PRG -> ui_approg (from ap_e); C set: none, or several
ap_only:
        stz     ap_n
        stz     ap_skip
@next:  ldx     #.loword(ap_dir)
        jsr     ap_rd1
        bcs     @end
        lda     ap_dbuf+4               ; a file named *.PRG?
        and     #$0010
        bne     @next
        jsr     ap_eprg
        bcs     @next
        lda     ap_n
        bne     @two
        inc     ap_n
        ldx     #.loword(ap_dname)      ; (its name: ap_rd1 made it a string)
        ldy     ap_e
        jsr     ui_strcpy
        bra     @next
@end:   lda     ap_n
        beq     @two
        clc
        rts
@two:   sec
        rts

; C clear if the name ap_dname ends in ".PRG" (any case)
ap_eprg:
        ldx     #.loword(ap_dname)
        jsr     ui_strlen
        cmp     #5
        bcc     @no
        clc
        adc     #.loword(ap_dname - 4)
        tax
        lda     a:0,x
        and     #$FFFF
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

; one entry of folder X (READDIR with the skip ap_skip, then ap_skip + 1) -> ap_dbuf: u32
; size, u8 attr, and its name as a string in ap_dname. C set: no more.
ap_rd1: stx     ap_rd
        lda     #^ap_dir
        sta     ap_rd+2
        lda     #.loword(ap_dbuf)
        sta     ap_rd+3
        lda     #^ap_dbuf
        sta     ap_rd+5
        lda     #AP_DBL
        sta     ap_rd+6
        lda     ap_skip
        sta     ap_rd+8
        inc     ap_skip
        ldx     #.loword(ap_rd)
        ldy     #^ap_rd
        sys     SYS_READDIR
        bcs     @no
        cmp     #0
        beq     @no
        lda     ap_dbuf+5               ; the name -> ap_dname
        and     #$00FF
        tay
        ldx     #0
:       cpy     #0
        beq     :+
        lda     ap_dbuf+6,x
        sep     #$20
        .a8
        sta     ap_dname,x
        rep     #$20
        .a16
        inx
        dey
        bra     :-
:       sep     #$20
        .a8
        stz     ap_dname,x
        rep     #$20
        .a16
        clc
        rts
@no:    sec
        rts

; X = APP.INF's text (zero-terminated) -> ui_apname, ui_apcat, ui_aptypes, ui_apicon,
; ui_apver, ui_apdesc, ui_apneeds and the program's name (all "" when missing)
ui_apparse:
        stx     z:ui_p
        ldx     #0                      ; every field ""
        sep     #$20
        .a8
:       stz     ap_fields,x
        inx
        cpx     #ap_fend - ap_fields
        bcc     :-
        rep     #$20
        .a16
@line:  jsr     ap_blank                ; a line: blanks, the key
        lda     (ui_p)
        and     #$00FF
        jeq     @out
        cmp     #'#'
        jeq     @skip
        cmp     #10
        jeq     @skip
        cmp     #13
        jeq     @skip
        ldy     #0                      ; the key, lower case, -> ap_key (12 at most)
@k:     lda     (ui_p)
        and     #$00FF
        cmp     #'='
        beq     @eq
        cmp     #' ' + 1
        bcc     @eq
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
:       cpy     #12
        bcs     :+
        sep     #$20
        .a8
        sta     ap_key,y
        rep     #$20
        .a16
        iny
:       inc     z:ui_p
        bra     @k
@eq:    lda     #0
        sta     ap_key,y
        jsr     ap_blank
        lda     (ui_p)
        and     #$00FF
        cmp     #'='
        jne     @skip                   ; (no '=': not a key line)
        inc     z:ui_p
        jsr     ap_blank
        ldx     #0                      ; which key? (ap_keys: "key", 0, field, size)
@kt:    lda     ap_keys,x
        and     #$00FF
        beq     @skip                   ; (unknown: ignored)
        stx     ap_kx
        ldy     #0
:       lda     ap_keys,x
        and     #$00FF
        sta     ap_c
        lda     ap_key,y
        and     #$00FF
        cmp     ap_c
        bne     :+
        inx
        iny
        cmp     #0
        bne     :-
        lda     ap_keys,x               ; this one: the value (to the line's end, blanks at
        sta     z:ui_q                  ; its end dropped) -> the field, cut to its size
        lda     ap_keys+2,x
        and     #$00FF
        sta     ap_c
        ldy     #0
        ldx     #0                      ; (X = the length without trailing blanks)
@v:     lda     (ui_p)
        and     #$00FF
        beq     @vend
        cmp     #10
        beq     @vend
        cmp     #13
        beq     @vend
        cpy     ap_c
        bcs     @vnx
        sep     #$20
        .a8
        sta     (ui_q),y
        rep     #$20
        .a16
        iny
        cmp     #' ' + 1
        bcc     @vnx
        tyx
@vnx:   inc     z:ui_p
        bra     @v
@vend:  txy
        lda     #0
        sep     #$20
        .a8
        sta     (ui_q),y
        rep     #$20
        .a16
        bra     @skip
:       ldx     ap_kx                   ; the next key of the table
:       lda     ap_keys,x
        and     #$00FF
        beq     :+
        inx
        bra     :-
:       inx                             ; (its 0, the field, the size and 0)
        inx
        inx
        inx
        inx
        jmp     @kt
@skip:  lda     (ui_p)                  ; to the next line
        and     #$00FF
        beq     @out
        inc     z:ui_p
        cmp     #10
        bne     @skip
        jmp     @line
@out:   rts

; blanks and tabs at ap_p skipped
ap_blank:
:       lda     (ui_p)
        and     #$00FF
        cmp     #' '
        beq     :+
        cmp     #9
        bne     :++
:       inc     z:ui_p
        bra     :--
:       rts

; X -> Y, at most A characters (and its 0)
ap_ncpy:
        sta     ap_c
        stz     ap_t2
:       lda     a:0,x
        and     #$00FF
        beq     :+
        pha
        lda     ap_t2
        cmp     ap_c
        pla
        bcs     :+
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        inx
        iny
        inc     ap_t2
        bra     :-
:       lda     #0
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        rts

; X = a file's path -> the app that opens its type (its extension in an APP.INF's types=):
; C clear, ui_approg its program, ui_apname its name. The folders of /APPS are looked at in
; the I/O processor's order (the first that has the type wins). C set: none.
ui_appfind:
        stz     ap_ext                  ; the extension, upper case (at most 8)
        stz     ap_t
:       lda     a:0,x                   ; (the last '.' after the last '/')
        and     #$00FF
        beq     :+++
        cmp     #'/'
        bne     :+
        stz     ap_t
:       cmp     #'.'
        bne     :+
        stx     ap_t
:       inx
        bra     :---
:       ldx     ap_t
        beq     @no
        ldy     #0
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
        sta     ap_ext,y
        rep     #$20
        .a16
        cmp     #0
        beq     :+
        iny
        cpy     #9
        bcc     :--
@no:    sec
        rts
:       cpy     #0
        beq     @no
        stz     ap_skip2
@next:  lda     ap_skip2                ; the next folder of /APPS
        sta     ap_skip
        inc     ap_skip2
        ldx     #.loword(ap_sapps)
        jsr     ap_rd1
        bcs     @no
        lda     ap_dbuf+4
        and     #$0010
        beq     @next
        lda     ap_dname
        and     #$00FF
        cmp     #'.'
        beq     @next
        ldx     #.loword(ap_sapps)      ; "/APPS/" + its name
        ldy     #.loword(ap_dir2)
        jsr     ui_strcpy
        clc
        adc     #.loword(ap_dir2)
        tay
        lda     #'/'
        sta     a:0,y
        iny
        ldx     #.loword(ap_dname)
        jsr     ui_strcpy
        ldx     #.loword(ap_dir2)
        jsr     ui_appinf
        bcs     @next
        jsr     ap_hastype
        bcs     @next
        clc
        rts

; C clear if ui_aptypes ("DIG, dlv,...": commas or blanks between) holds ap_ext
ap_hastype:
        ldx     #.loword(ui_aptypes)
@t:     lda     a:0,x                   ; to the next type
        and     #$00FF
        beq     @no
        cmp     #','
        beq     :+
        cmp     #' '
        beq     :+
        cmp     #'.'
        bne     @cmp
:       inx
        bra     @t
@cmp:   ldy     #0
:       lda     a:0,x
        and     #$00FF
        cmp     #'a'
        bcc     :+
        cmp     #'z' + 1
        bcs     :+
        and     #$00DF
:       cmp     #','
        beq     @endt
        cmp     #' '
        beq     @endt
        cmp     #0
        beq     @endt
        sta     ap_c
        lda     ap_ext,y
        and     #$00FF
        cmp     ap_c
        bne     @skipt
        inx
        iny
        bra     :--
@endt:  lda     ap_ext,y                ; the type ended: the extension too?
        and     #$00FF
        bne     @t
        clc
        rts
@skipt: lda     a:0,x                   ; not this one
        and     #$00FF
        beq     @no
        cmp     #','
        beq     @t
        cmp     #' '
        beq     @t
        inx
        bra     @skipt
@no:    sec
        rts

        .segment "RODATA"
ap_sinf: .byte  "/APP.INF", 0
ap_sprg: .byte  ".PRG", 0
ap_sapps: .byte "/APPS", 0
; the keys: "key", 0, u16 field, u8 its size - 1, 0
ap_keys:
        .byte   "name", 0
        .addr   ui_apname
        .byte   24, 0
        .byte   "program", 0
        .addr   ui_apprg
        .byte   63, 0
        .byte   "icon", 0
        .addr   ui_apicon
        .byte   31, 0
        .byte   "types", 0
        .addr   ui_aptypes
        .byte   47, 0
        .byte   "category", 0
        .addr   ui_apcat
        .byte   15, 0
        .byte   "version", 0
        .addr   ui_apver
        .byte   15, 0
        .byte   "description", 0
        .addr   ui_apdesc
        .byte   63, 0
        .byte   "needs", 0
        .addr   ui_apneeds
        .byte   47, 0
        .byte   "args", 0               ; (0.31)
        .addr   ui_apargs
        .byte   127, 0
        .byte   "console", 0
        .addr   ui_apcons
        .byte   7, 0
        .byte   0

        .segment "BSS"
ap_fields:
ui_apname:  .res 25
ui_apprg:     .res 64
ui_apicon:  .res 32
ui_aptypes: .res 48
ui_apcat:   .res 16
ui_apver:   .res 16
ui_apdesc:  .res 64
ui_apneeds: .res 48
ui_apargs:  .res 128                    ; (0.31)
ui_apcons:  .res 8
ap_fend:
ui_approg:  .res 128
ap_dir:     .res 128
ap_dir2:    .res 128
ap_path:    .res 128
ap_buf:     .res AP_BUFL + 2
ap_dbuf:    .res AP_DBL + 2
ap_dname:   .res 100
ap_key:     .res 14
ap_ext:     .res 10
ap_rw:      .res 6
ap_rd:      .res 10
ap_sb:      .res 6
ap_st:      .res 10
ap_kx:      .res 2
ap_c:       .res 2
ap_t:       .res 2
ap_t2:      .res 2
ap_e:       .res 2
ap_h:       .res 2
ap_n:       .res 2
ap_skip:    .res 2
ap_skip2:   .res 2

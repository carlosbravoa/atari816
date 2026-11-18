; HELLOWIN - window application template for Horizon (Atari816).
;
; Shows: a window with menus (with shortcut texts), the controls library (a label, a text
; field, two buttons), the file dialog (File > Open... reads the first line of a text file
; into the field, File > Save as... writes the field to a file), an alert (Help > About),
; keyboard shortcuts, and a clean exit (close box, File > Quit, ctrl+Q, or the Desktop's
; Shut down, which sends WE_CLOSE).
;
; Build: make (links Horizon's controls library, build/ui.lib). Run: make run.
; The controls library is documented in horizon/user/ui.inc; the syscalls in
; sdk/docs/reference/.

        .include "horizon.inc"
        .include "ui.inc"

W       = 296                           ; the window's content size
H       = 112
MSGY    = 76                            ; where the greeting is drawn
NAMEMAX = 40                            ; the field's buffer
MSGLEN  = 64                            ; the greeting line

        .segment "CODE"
        .a16
        .i16

start:  sys     SYS_WSSTART             ; the window system (already running under the
        bcc     :+                      ;   Desktop: A = 0; started by us: A = 1)
        print   "hellowin: no window system (not enough memory)\n"
        exit    1
:       sta     z:wsown                 ; remember: only its starter may stop it
        jsr     ui_init                 ; the controls library, after SYS_WSSTART
        ptr     wopen
        sys     SYS_WOPEN               ; -> A = window
        jcs     quit
        sta     z:win
        ldx     #0                      ; every control lives in this window
:       ldy     ctls,x
        beq     :+
        sep     #$20
        .a8
        sta     a:CT_WIN,y              ; (CT_WIN is a byte)
        rep     #$20
        .a16
        inx
        inx
        bra     :-
:       ptr     menus                   ; the menu bar shows these while we have the focus
        lda     z:win
        sys     SYS_WMENU
        ldx     #.loword(ctls)
        jsr     ui_drawall              ; draw every control (the body is C_BODY already)
        jsr     greet

; ---- the event loop: the library first, then what it did not use
loop:   lda     #0                      ; 0 = wait for the next event
        jsr     ui_getev                ; -> ui_ev: u8 type, u8 window, u16 a, b, c
        bcs     loop
        ldx     #.loword(ctls)
        jsr     ui_event                ; -> A = UA_*, X = the control that acted
        cmp     #UA_CLICK
        bne     @own
        cpx     #.loword(b_greet)       ; Greet (also Enter: the default button)
        bne     :+
        jsr     greet
        bra     loop
:       cpx     #.loword(b_clear)       ; Clear
        bne     loop
        ldx     #.loword(f_name)
        ldy     #.loword(empty)
        jsr     ui_fdset                ; new text for the field (redrawn)
        jsr     greet
        bra     loop
@own:   cmp     #UA_NONE                ; not for a control: ours
        bne     loop
        lda     ui_ev
        and     #$00FF
        cmp     #WE_CLOSE
        jeq     quit
        cmp     #WE_MENU
        beq     menu
        cmp     #WE_KEY
        bne     loop
        lda     ui_ev+4                 ; b = modifiers | down << 8
        bit     #$0100
        beq     loop                    ; (a release)
        and     #$0011                  ; left or right ctrl
        beq     loop
        lda     ui_ev+2                 ; a = HID usage: $04 = A ... $1D = Z
        cmp     #$12                    ; ctrl+O
        beq     m_open
        cmp     #$16                    ; ctrl+S
        jeq     m_save
        cmp     #$14                    ; ctrl+Q
        jeq     quit
        bra     loop

; WE_MENU: a = menu (0 = our first), b = item (counting separators)
menu:   lda     ui_ev+2
        bne     @help
        lda     ui_ev+4
        beq     m_open                  ; File > Open...
        cmp     #1
        jeq     m_save                  ; File > Save as...
        cmp     #3
        jeq     quit                    ; File > Quit (item 2 is the separator)
        jmp     loop
@help:  ldx     #.loword(about)         ; Help > About...
        jsr     ui_alert                ; -> A = the button chosen
        jmp     loop

; ---- File > Open...: the first line of a file into the field
m_open: stz     path                    ; no suggested name
        lda     #0                      ; 0 = an Open dialog
        ldx     #.loword(path)          ; a 128-byte buffer for the full path
        ldy     #.loword(t_open)        ; the dialog's title
        jsr     ui_filedlg              ; C set: cancelled
        jcs     loop
        ptr     path
        lda     #O_READ
        sys     SYS_OPEN
        jcs     ioerr
        sta     z:fh
        lda     #NAMEMAX - 1            ; read at most what the field holds
        jsr     setio
        ptr     iob
        sys     SYS_READ                ; -> A = bytes read
        php
        pha
        lda     z:fh
        sys     SYS_CLOSE
        pla
        plp
        jcs     ioerr
        tax                             ; cut at the end, a CR or a LF
        stz     tmp,x
        ldx     #0
:       lda     tmp,x
        and     #$00FF
        beq     :+
        cmp     #13
        beq     :+
        cmp     #10
        beq     :+
        inx
        bra     :-
:       stz     tmp,x                   ; (16-bit store: the buffer has a spare byte)
        ldx     #.loword(f_name)
        ldy     #.loword(tmp)
        jsr     ui_fdset
        jsr     greet
        jmp     loop

; ---- File > Save as...: the field's text and a line feed
m_save: ldx     #.loword(sugg)          ; a suggested name
        ldy     #.loword(path)
        jsr     ui_strcpy
        lda     #1                      ; 1 = a Save dialog (asks before replacing)
        ldx     #.loword(path)
        ldy     #.loword(t_save)
        jsr     ui_filedlg
        jcs     loop
        ptr     path
        lda     #O_CREATE               ; create or truncate
        sys     SYS_OPEN
        jcs     ioerr
        sta     z:fh
        ldx     #.loword(name)
        ldy     #.loword(tmp)
        jsr     ui_strcpy               ; -> A = length
        tax
        lda     #10
        sta     tmp,x                   ; (and a 0 after it)
        inx
        txa
        jsr     setio
        ptr     iob
        sys     SYS_WRITE
        php
        pha
        lda     z:fh
        sys     SYS_CLOSE
        pla
        plp
        jcs     ioerr
        jmp     loop

; A = length: the read / write block for handle fh and the buffer tmp
setio:  sta     iob+4
        lda     z:fh
        sta     iob                     ; u8 handle (the next store covers iob+1)
        lda     #.loword(tmp)
        sta     iob+1                   ; u24 buffer: offset, then the bank byte
        sep     #$20
        .a8
        lda     #^tmp
        sta     iob+3
        rep     #$20
        .a16
        rts

ioerr:  ldx     #.loword(al_err)        ; (a real program would say which file and why)
        jsr     ui_alert
        jmp     loop

; ---- the greeting under the controls, drawn with its paper (no flicker, no clearing)
greet:  ldx     #.loword(s_hello)       ; "Hello, NAME!" into msg, padded with spaces
        ldy     #.loword(msg)
        jsr     ui_strcpy
        ldx     #.loword(name)
        lda     name
        and     #$00FF
        bne     :+
        ldx     #.loword(s_world)       ; an empty field: "world"
:       ldy     #.loword(msg + 7)
        jsr     ui_strcpy
        clc
        adc     #7
        tax
        lda     #'!' | (' ' << 8)
        sta     msg,x
        inx
        lda     #' ' | (' ' << 8)       ; (the rest of the line in spaces: covers a longer
:       inx                             ;   old greeting)
        sta     msg,x
        cpx     #MSGLEN - 3
        bcc     :-
        stz     msg + MSGLEN - 2
        lda     z:win
        sta     z:ui_win
        lda     #UI_GAP
        sta     z:ui_x
        lda     #MSGY
        sta     z:ui_y
        stz     z:ui_font               ; the UI font
        ldx     #.loword(msg)
        lda     #C_TITLE | (C_BODY << 8)   ; ink | paper << 8
        jmp     ui_text

quit:   lda     z:win                   ; (closing is optional: exit closes our windows)
        sys     SYS_WCLOSE
        lda     z:wsown
        beq     :+
        sys     SYS_WSSTOP              ; we started the window system: stop it
:       exit    0

        .segment "RODATA"
wopen:  .word   120, 60, W, H           ; {i16 x, y (outer top left), u16 content w, h,
        .faraddr t_win                  ;  u24 title, u8 flags}
        .byte   0
t_win:  .byte   "Hello", 0
menus:  .byte   "File", 0
        .byte   "Open...", 9, "Ctrl+O", 0      ; 9 = TAB: the shortcut text, right-aligned
        .byte   "Save as...", 9, "Ctrl+S", 0
        .byte   "-", 0                         ; a separator (it counts as an item)
        .byte   "Quit", 9, "Ctrl+Q", 0
        .byte   0                              ; end of the File menu
        .byte   "Help", 0
        .byte   "About...", 0
        .byte   0
        .byte   0                              ; end of the menus
t_open: .byte   "Open a text file", 0
t_save: .byte   "Save the name", 0
sugg:   .byte   "NAME.TXT", 0
s_hello: .byte  "Hello, ", 0
s_world: .byte  "world", 0
empty:  .byte   0
s_lab:  .byte   "Your name:", 0
s_greet: .byte  "Greet", 0
s_clear: .byte  "Clear", 0
s_ok:   .byte   "OK", 0
t_about: .byte  "About Hello", 0
m_about: .byte  "Hello 1.0, a window program", 10, "made from the Atari816 SDK template.", 0
t_err:  .byte   "Hello", 0
m_err:  .byte   "The file could not be read or written.", 0
about:  .word   0, t_about, m_about, s_ok, 0, 0     ; ui_alert block: kind 0 note
al_err: .word   1, t_err, m_err, s_ok, 0, 0         ; kind 1 warning (beeps)

        .segment "DATA"                 ; controls: the library writes into them
ctls:   .addr   l_name, f_name, b_greet, b_clear, 0   ; (the order is the Tab order)
l_name: .byte   UT_LABEL, 0
        .word   UI_GAP, 12, 72, UI_LINE, 0, s_lab
f_name: .byte   UT_FIELD, 0
        .word   88, 9, W - 88 - UI_GAP, UI_FLDH, UF_FOCUS, name, NAMEMAX, 0, 0, 0, 0
b_greet: .byte  UT_BUTTON, 0
        .word   W - UI_GAP - 64 - 4 - 64, 40, 64, UI_BTNH, UF_DEFAULT, s_greet
b_clear: .byte  UT_BUTTON, 0
        .word   W - UI_GAP - 64, 40, 64, UI_BTNH, 0, s_clear

        .segment "BSS"

name:   .res    NAMEMAX                 ; the field's text (zero-terminated)
path:   .res    128                     ; the file dialog's path
tmp:    .res    NAMEMAX + 2
msg:    .res    MSGLEN
iob:    .res    6                       ; {u8 handle, u24 buffer, u16 length}

        .segment "ZEROPAGE"
wsown:  .res    2
win:    .res    2
fh:     .res    2

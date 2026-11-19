; DESK - the Desktop (/SYSTEM/DESK.PRG, started by INIT; one instance only). Starts the
; window system and owns its backdrop: a borderless window under all others that holds
; the desktop picture, gets the system key (F12) and carries the system menus:
;   Horizon: About Horizon / Settings... / - / Force quit... / - / Atari (F12) / - /
;     Restart... / Shut down...
;   Programs: read from /SYSTEM/PROGRAMS, one "Title=/path" per line (# comments); an entry
;     whose program is not on the card is left out (and Settings, which is in the Horizon
;     menu), so new programs need no rebuild (a built-in list when the file is missing).
;     Read again each time the menu opens (WE_MENUOPEN): the kernel shows the new list.
;   (the kernel adds "Windows" after them)
; The menu bar's right end shows the free memory and the time: "5632K free  up 0:05" (the
; time since start) until the clock is set, then "5632K free  14:05" (every 5 s). A click
; on it (WE_STATUS) opens "Date and time": the date and the time in five fields (digits
; typed in, Up / Down or the wheel, Tab / arrows to move, Enter, Esc). The board has no
; battery clock: the last time is kept in /SYSTEM/CLOCK (ui_clksave: when it is set, and
; before a restart or shut down) and loaded at start as a provisional value (ui_clkload).
; Programs are started detached (ui_launch: an alert says why one cannot start: not enough
; memory, no task slot, not on the card, not a program). At start it runs "settings
; apply", creates /Desktop if missing and opens Files. F12 or "Atari" shows the classic
; machine; F12 there brings the desktop back exactly as it was.
; Icons (pictures from /SYSTEM/ICONS, read into a bank of their own): "SD card" (opens Files
; at the root), "Atari" (opens the Atari panel; a green mark when something is loaded),
; (0.20) "PC" while the PC volume of the PC link is there (STAT /PC: works; looked at every
; 5 s: it comes and goes with the PC; when it comes, the PC's clock sets the clock: ui_clkpc;
; opens Files at /PC:), then one per entry of /Desktop (sorted ignoring case, names starting with '.' left out;
; read again every 5 s): a folder, a file (its icon by its type: ui_ficon), or a shortcut
; (NAME.LNK, ui_lnkread: the icon of its target with an arrow, labelled by its title). They
; sit on a grid of 8 columns x 5 rows from the top right; where each one is is kept in
; /SYSTEM/LAYOUT ("col row name" lines, the fixed icons ":SD", ":ATARI" and ":PC"; the PC's
; line is kept while the PC is away); icons not in it
; take the first free cell. A click selects, a click elsewhere deselects; a double click
; (0.5 s) opens (a /Desktop entry through ui_open: by its type; a shortcut: its target); a
; click on the Atari icon opens its panel. Any icon can be dragged (the drag pointer): onto
; empty desktop it snaps to the nearest free cell; a /Desktop entry onto a Files window (it
; gets the path, SYS_WDROP: Files moves it there), onto a folder icon (moved into it), onto
; the SD card (moved to the root), onto the Atari icon (an Atari file is mounted). A path
; dropped here from Files: on the Atari icon an Atari file is mounted; on a folder icon or
; the SD card it is moved there; (0.20) onto the PC icon it is copied into /PC: (and onto the
; SD card, a path from the PC is copied: between the two volumes a volume icon copies; a
; move between them is a copy, then the source deleted: ui_mvtree); elsewhere a shortcut to it is made in /Desktop (ui_mklink)
; where it was dropped, or with Shift held it is moved into /Desktop.
; (0.15) A right press (or the menu key with an icon selected): a pop-up menu (ui_popup):
; the Atari icon's (attach, run, eject, restart, settings, the panel), another icon's (Open,
; Show original for a shortcut, Rename..., Delete), the desktop's (New folder..., Tidy up,
; Settings...); see ctxmenu. Delete (also the Delete key while the desktop has the
; keyboard) removes a shortcut or a /Desktop entry after a question. Tidy up puts every
; icon back in order.
; The Atari panel (a window of its own): what is in D1:-D4:, the executable and the
; cartridge (classic_query), an Eject button for each; (0.18) Attach disk..., Attach
; cartridge..., Run program... (as the icon's menu); Eject all, Restart Atari (classic
; boot with what is loaded), Switch to Atari (F12); a right press or the menu key in it:
; the icon's menu (without Open panel).
; (0.18) As on a real machine, attaching or ejecting a cartridge is a power cycle: the
; executable is ejected (attaching), then the classic machine is cold booted and stays
; hidden (classic_boot CB_STAY). Restart Atari with a cartridge ejects the executable first.
; (0.23) Printing: every second (the timer) the Desktop asks how many print jobs are finished
; (one STAT of "/PRN:"); when that count changed, /Printouts is read and the jobs newer than
; the newest seen (names start with the date and time) are new: "Printed: NAME" in the
; status for about 6 s instead of the clock (a click on it opens Printer, /BIN/PRINTER.PRG),
; the information chime, and, when the PC's gateway makes PDFs (STAT "/PC:": PCS_PRINT),
; /SYSTEM/PRINTD.PRG is started for each new job (detached): the notice then says "(to the
; PC)". The jobs there at start count as seen. Without the Desktop (the text shell): no
; notices, nothing sent at once.
; (0.23) "Run in Atari": a /Desktop entry (or a shortcut's target) that is a BASIC program
; (.bas .lst) has it in its pop-up menu (ulib atari_run: classic_mount CK_BASRUN, the Atari
; cold booted and shown; F12 returns). Double click still opens Horizon BASIC.
; (0.23) The folder disk: the Atari panel's "Folder disk..." (and the Atari icon's menu): a
; dialog with the folder (default /Atari, made if missing) and the drive (D1:-D4:, default
; D2:; D1: cannot boot), Mount: classic_mount CK_FOLDER (an old folder disk on another drive
; is ejected first: its changes are saved). The drive that is the folder disk (STAT "/D1:" ..
; "/D4:" answers) shows "PATH (folder)" and a Refresh button (the same folder mounted again:
; the Atari's changes saved, the disk built again from the folder); the line under the rows
; says "12 files, 3 left out, 120 free sectors" (", saving..." while the Atari's changes wait
; to be saved), looked at every second while the panel is open.
; (0.24) The screen saver: every second the Desktop compares the seconds without input (kernel
; setting 6) with the delay Settings chose (setting 5; 0 = off) and starts /SYSTEM/SAVER.PRG
; (detached) when it is reached, once until the next input (svcheck); when the saver has ended,
; the status is drawn again.
; Force quit: a dialog listing the running programs; the one chosen is killed.
; Restart / Shut down (and WE_SYSREQ, asked by a program with SYS_SYSREQ: no confirmation):
; every other window gets WE_CLOSE (SYS_WSCLOSEALL); the programs may ask to save; one that
; stays open, idle, after reading its close request, cancels (an alert says which); one
; that does not answer for 20 s: "Shut down anyway?". Then SYS_RESTART, or SYS_SYNC (every
; other program ended, the files closed, the card flushed) and a full-screen "It is now
; safe to switch off the Atari816" with a Restart button.
        .include "horizon.inc"
        .include "ui.inc"
        .include "icons.inc"
        .import ui_modal_get            ; (uialert.s: the next event of a modal window)
        .import ui_rbtn                 ; (ui.s: the right button's state, for the panel)

NICON   = 24                            ; icons at most (SD card, Atari, 22 of /Desktop)
NFIX    = 2                             ; the fixed ones: 0 SD card, 1 Atari (and 2 the PC
                                        ; while it is there: nfix = 3)
NROWS   = 5                             ; the grid: rows in a column, columns
NCOLS   = 8
NCELL   = NROWS * NCOLS
CELLW   = 72                            ; an icon's cell: the picture (32 x 32) centred at
CELLH   = 60                            ;   its top, the label (UI_LINE) under it
RIGHT   = 8                             ; the columns' distance from the right edge
TOP     = 8                             ; and the first row's from the top of the backdrop
LABW    = 64                            ; a label's widest text
LABY    = 32                            ; the label's top in the cell
LABL    = 40                            ; a label kept (with its 0)
MARKX   = 575                           ; the "Atari816" mark (below the icons; 0.16: one
                                        ; word, 3 pixels narrower, the same right edge)
MARKY   = 324
NAMEL   = 128                           ; a name kept (with its 0)
K_ATARI = 0                             ; icon kinds
K_FOLDER = 1
K_SD    = 2
K_FILE  = 3
K_PC    = 4
NPROG   = 16                            ; Programs menu entries at most
FQW     = 240                           ; the Force quit dialog's content (outer 242 wide:
                                        ;   a 256-pixel stride, one bank with little memory left)
FQH     = 196
MENUL   = 2048                          ; the menus given to win_menu (the kernel keeps 2045)
MENUMAX = 2000
ATW     = 376                           ; the Atari panel's content (0.18: wider, taller:
ATB     = 218                           ; two rows of three buttons above ATB; 0.23: the folder
ATH     = ATB + 28                      ; disk's row below them)
ATBW1   = 100                           ; its buttons' columns: Attach disk... / Eject all,
ATBW2   = 128                           ; Attach cartridge... / Restart Atari, Run
ATBW3   = ATW - 8 - (8 + ATBW1 + 8 + ATBW2 + 8)     ; program... / Switch to Atari
ATROW   = 24                            ; its rows
DTW     = 260                           ; the "Date and time" dialog's content
DTH     = 112
FDW     = 300                           ; (0.23) the "Folder disk" dialog's content
FDH     = 176
NOTICE  = 7                             ; (0.23) a print notice's seconds (+ 1)
PNAMEL  = 64                            ; (0.23) a job's name kept (with its 0)

        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_SINGLE              ; never two Desktops
        bcc     :+
        exit    0
:       sys     SYS_WSSTART
        jcs     fail
        jsr     ui_init
        lda     #0                      ; the menu bar's name for its windows
        ptr     t_desktop
        sys     SYS_TNAME
        lda     #.loword(a_apply)       ; the saved settings (/SYSTEM/CONFIG): "settings
        sta     z:u_arg                 ; apply" sets them and ends (no Settings: nothing)
        lda     #^a_apply
        sta     z:u_arg+2
        ptr     p_set
        lda     #1
        jsr     spawn
        bcs     :+
        sys     SYS_WAIT
:       ptr     p_desk                  ; /Desktop (an error: there already)
        sys     SYS_MKDIR
        jsr     ui_clkload              ; the last time saved: the clock's provisional start
        jsr     icload                  ; the icons' pictures
        lda     #$FFFF
        sta     z:atwin
        sta     z:pend
        sta     z:sel
        stz     z:tidy
        stz     z:dirty
        ptr     bblk                    ; the backdrop
        sys     SYS_WOPEN
        jcs     fail
        sta     z:back
        sta     z:ui_win
        stz     z:ui_font
        stz     z:ui_x
        stz     z:ui_y
        lda     #640
        sta     z:ui_w
        lda     #344
        sta     z:ui_h
        jsr     dither
        lda     #WD_TEXT | (C_LIGHT << 8)   ; the machine's name, bottom right: embossed
        sta     blk
        lda     #$FF
        sta     blk+2
        lda     #MARKX + 1
        sta     blk+4
        lda     #MARKY + 1
        sta     blk+6
        lda     #.loword(t_name)
        sta     blk+12
        lda     #^t_name
        sta     blk+14
        jsr     draw
        lda     #WD_TEXT | (C_DESK2 << 8)
        sta     blk
        lda     #MARKX
        sta     blk+4
        lda     #MARKY
        sta     blk+6
        jsr     draw
        jsr     atcheck                 ; (is something loaded: the Atari icon's mark)
        lda     #$FFFF                  ; (0.20) the PC icon's cell: not known yet
        sta     z:pccell
        jsr     scan                    ; the icons
        lda     z:pcon                  ; (the clock was asked already: ui_clkload)
        sta     z:pcwas
        jsr     namesum
        sta     z:sum
        jsr     load
        jsr     place
        jsr     drawall
        jsr     mkmenu                  ; the menus (the Programs list from the card)
        jsr     setmenu
        stz     prtick
        lda     #$FFFF
        sta     fdslot
        lda     z:back                  ; the timer: every second (0.23; the status, /Desktop
        ldx     #100                    ; and the Atari's mounts every 5 s, as before)
        sys     SYS_WTIMER
        sys     SYS_UPTIME              ; (its start: the 5-s work at its 5th, 10th, ... second)
        sta     tm0
        stx     tm0+2
        stz     tlast
        jsr     prinit                  ; (0.23) the print jobs there now count as seen
        jsr     clock
        ldx     #.loword(p_files)       ; Files at start
        ldy     #0
        lda     #.loword(t_files)
        jsr     ui_launch
        jsr     clock

loop:   lda     #0
        jsr     ui_getev
        bcs     loop
        lda     ui_ev+1                 ; the Atari panel's events
        and     #$00FF
        cmp     z:atwin
        bne     :+
        jsr     atevent
        jmp     loop
:       lda     ui_ev
        and     #$00FF
        cmp     #WE_TICK
        bne     :+
        jsr     tick
        jmp     loop
:       cmp     #WE_BUTTON
        jeq     onbutton
        cmp     #WE_MOTION
        jeq     onmotion
        cmp     #WE_DROP
        jeq     ondrop
        cmp     #WE_STATUS
        bne     @nost
        lda     prtick                  ; (0.23) a print notice shows: Printer
        beq     :+
        ldx     #.loword(p_printer)
        ldy     #0
        lda     #.loword(t_printer)
        jsr     ui_launch
        jmp     loop
:       jsr     datedlg
        jmp     loop
@nost:
        cmp     #WE_MENUOPEN
        bne     :+
        lda     ui_ev+2                 ; Programs opens: the list read again
        cmp     #1
        jne     loop
        jsr     mkmenu
        jsr     setmenu
        jmp     loop
:       cmp     #WE_SYSREQ
        bne     :+
        lda     ui_ev+2                 ; a program asks (no confirmation)
        jsr     sysdown
        jmp     loop
:       cmp     #WE_MENU
        jne     @key
        lda     ui_ev+2                 ; Programs: the list
        beq     @sys
        lda     ui_ev+4
        cmp     z:nprog
        jcs     loop
        asl     a
        tax
        lda     ptitle,x
        pha
        lda     ppath,x
        tax
        pla
        ldy     #0
        jsr     ui_launch
        jsr     clock
        jmp     loop
@sys:   lda     ui_ev+4                 ; Horizon: About, Settings, -, Force quit, -, Atari,
        bne     :+                      ; -, Restart, Shut down
        ldx     #.loword(p_about)
        ldy     #0
        lda     #.loword(t_about)
        jsr     ui_launch
        jmp     loop
:       cmp     #1
        bne     :+
        ldx     #.loword(p_set)
        ldy     #0
        lda     #.loword(t_settings)
        jsr     ui_launch
        jmp     loop
:       cmp     #3
        bne     :+
        jsr     forcequit
        jmp     loop
:       cmp     #5
        jeq     @atari
        cmp     #7
        bne     :+
        ldx     #.loword(al_restart)
        jsr     ui_alert
        cmp     #0
        jne     loop
        lda     #SR_RESTART
        jsr     sysdown
        jmp     loop
:       cmp     #8
        jne     loop
        ldx     #.loword(al_shut)
        jsr     ui_alert
        cmp     #0
        jne     loop
        lda     #SR_SHUTDOWN
        jsr     sysdown
        jmp     loop
@key:   cmp     #WE_KEY                 ; keys (the desktop has the keyboard)
        jne     loop
        lda     ui_ev+4
        and     #$0100
        jeq     loop
        jsr     ui_menukey              ; (0.15) the menu key: the selected icon's menu
        bcc     :+
        lda     z:sel
        cmp     #$FFFF
        jeq     loop
        lda     #1
        jsr     ctxmenu
        jmp     loop
:       lda     ui_ev+2
        lda     ui_ev+2
        cmp     #$4C                    ; Delete: the selected icon
        bne     :+
        lda     z:sel
        cmp     #$FFFF
        jeq     loop
        jsr     delicon
        jmp     loop
:       cmp     #$28                    ; Enter: open it
        bne     :+
        lda     z:sel
        cmp     #$FFFF
        jeq     loop
        jsr     openicon
        jmp     loop
:       cmp     #$FF                    ; the system key (F12, $FF, down)
        jne     loop
@atari: sys     SYS_CLASSIC             ; until F12 there
        stz     z:btn
        jsr     tcatch                  ; (0.23)
        jmp     loop

fail:   print   "desk: no window system\n"
        exit    1

draw:   lda     z:back
        ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_WDRAW
        rts

; the desktop pattern in ui_x, ui_y, ui_w, ui_h
dither: lda     #C_DESK2
        sta     z:ui_c2
        lda     #WD_DITHER | (C_DESK << 8)
        jmp     ui_rect

; ---------------------------------------------------------------- the Programs menu
; menu = the Horizon menu, then "Programs" and the titles of /SYSTEM/PROGRAMS whose program
; is on the card (ptitle / ppath: their strings in pool); Settings is left out (it is in
; the Horizon menu)
mkmenu: ldx     #.loword(m_sys)         ; the Horizon menu and the "Programs" title
        ldy     #.loword(menu)
        lda     #m_sys_end - m_sys
        jsr     memcpy
        lda     #.loword(menu)
        clc
        adc     #m_sys_end - m_sys
        sta     z:mp
        lda     #.loword(pool)
        sta     z:pp
        stz     z:nprog
        ptr     p_progs                 ; the list: the file, else the built-in one
        lda     #O_READ
        sys     SYS_OPEN
        bcs     @def
        sta     z:t
        sta     rwblk
        lda     #.loword(fbuf)
        sta     rwblk+1
        lda     #^fbuf
        sta     rwblk+3
        lda     #FBUFL - 1
        sta     rwblk+4
        ptr     rwblk
        sys     SYS_READ
        php
        pha
        lda     z:t
        sys     SYS_CLOSE
        pla
        plp
        bcc     :+
@def:   ldx     #.loword(d_progs)
        ldy     #.loword(fbuf)
        jsr     ui_strcpy
:       tax                             ; terminated
        sep     #$20
        .a8
        stz     fbuf,x
        rep     #$20
        .a16
        ldx     #.loword(fbuf)
@line:  stx     z:lp                    ; a line: "Title=/path"
        lda     a:0,x
        and     #$00FF
        jeq     @end
        cmp     #'#'
        jeq     @skip
        cmp     #' ' + 1
        jcc     @skip
        ldy     #0                      ; the title -> lbuf (24 characters at most)
:       lda     a:0,x
        and     #$00FF
        cmp     #'='
        beq     :+
        cmp     #' '
        jcc     @skip                   ; (no '=': not an entry)
        cpy     #24
        bcs     @tl
        sep     #$20
        .a8
        sta     lbuf,y
        rep     #$20
        .a16
        iny
@tl:    inx
        bra     :-
:       lda     #0
        sta     lbuf,y
        sty     z:tl
        inx                             ; the path -> pth
        ldy     #0
:       lda     a:0,x
        and     #$00FF
        cmp     #' ' + 1
        bcc     :+
        cpy     #127
        bcs     @pl
        sep     #$20
        .a8
        sta     pth,y
        rep     #$20
        .a16
        iny
@pl:    inx
        bra     :-
:       lda     #0
        sta     pth,y
        sty     z:pl
        stx     z:lp
        cpy     #0
        jeq     @skip
        lda     #.loword(pth)           ; (Settings: in the Horizon menu)
        sta     z:q
        lda     #.loword(p_set)
        sta     z:r
        jsr     streq
        jcc     @skip
        lda     z:nprog
        cmp     #NPROG
        jcs     @end
        lda     z:mp                    ; room in the menu (and the pool)?
        clc
        adc     z:tl
        adc     #2
        cmp     #.loword(menu + MENUMAX)
        jcs     @end
        lda     z:pp
        clc
        adc     z:tl
        adc     z:pl
        adc     #2
        cmp     #.loword(pool + POOLL)
        jcs     @end
        ldx     #.loword(pth)           ; on the card?
        jsr     statx
        jcs     @skip
        lda     z:nprog                 ; keep it
        asl     a
        tax
        lda     z:pp
        sta     ptitle,x
        ldx     #.loword(lbuf)
        ldy     z:pp
        jsr     ui_strcpy
        sec
        adc     z:pp
        sta     z:pp
        lda     z:nprog
        asl     a
        tax
        lda     z:pp
        sta     ppath,x
        ldx     #.loword(pth)
        ldy     z:pp
        jsr     ui_strcpy
        sec
        adc     z:pp
        sta     z:pp
        ldx     #.loword(lbuf)          ; and its menu item
        ldy     z:mp
        jsr     ui_strcpy
        sec
        adc     z:mp
        sta     z:mp
        inc     z:nprog
@skip:  ldx     z:lp                    ; to the next line
:       lda     a:0,x
        and     #$00FF
        beq     @end2
        inx
        cmp     #10
        bne     :-
        jmp     @line
@end2:  stx     z:lp
@end:   ldx     z:mp                    ; "", "" after the last menu
        stz     a:0,x
        rts

; the menus to the kernel, unless they are what it has already (mold)
setmenu:
        lda     z:mp                    ; its length (with the "", "")
        sec
        sbc     #.loword(menu - 2)
        cmp     z:mlen
        bne     @new
        tay
:       dey
        bmi     @out
        lda     menu,y
        cmp     mold,y
        beq     :-
@new:   sta     z:mlen
        lda     z:mp
        sec
        sbc     #.loword(menu - 2)
        sta     z:mlen
        ldx     #.loword(menu)
        ldy     #.loword(mold)
        jsr     memcpy
        lda     z:back
        ptr     menu
        sys     SYS_WMENU
@out:   rts

; C clear if the string at q equals the one at r (ignoring case)
streq:  ldy     #0
:       lda     (q),y
        jsr     lower
        sta     z:c
        lda     (r),y
        jsr     lower
        cmp     z:c
        bne     @no
        cmp     #0
        beq     @yes
        iny
        bra     :-
@yes:   clc
        rts
@no:    sec
        rts

; C clear if the path X exists (stat: its attributes in st+4)
statx:  stx     stblk
        lda     #^pth
        sta     stblk+2
        lda     #.loword(st)
        sta     stblk+3
        lda     #^st
        sta     stblk+5
        ptr     stblk
        sys     SYS_STAT
        rts
; (pth)
stpth:  ldx     #.loword(pth)
        bra     statx

; copy A bytes from X to Y (program bank)
memcpy: sta     z:t
        sep     #$20
        .a8
:       lda     z:t
        ora     z:t+1
        beq     :+
        lda     a:0,x
        sta     a:0,y
        inx
        iny
        rep     #$20
        .a16
        dec     z:t
        sep     #$20
        .a8
        bra     :-
:       rep     #$20
        .a16
        rts

; ---------------------------------------------------------------- icons
; the pictures: /SYSTEM/ICONS (ICO_COUNT x 1024 bytes) into a bank of their own (icbank;
; 0: none, plain frames instead)
icload: stz     z:icbank
        sys     SYS_BALLOC
        bcs     @out
        sta     z:icbank
        ptr     p_icons
        lda     #O_READ
        sys     SYS_OPEN
        bcs     @none
        sta     z:t
        sta     rwblk
        stz     rwblk+1
        lda     z:icbank
        sta     rwblk+3
        lda     #ICO_COUNT * 1024
        sta     rwblk+4
        ptr     rwblk
        sys     SYS_READ
        php
        pha
        lda     z:t
        sys     SYS_CLOSE
        pla
        plp
        bcs     @none
        cmp     #ICO_COUNT * 1024
        beq     @out
@none:  lda     z:icbank
        sys     SYS_BFREE
        stz     z:icbank
@out:   rts

; read /Desktop: SD card and Atari, then its entries (sorted, ignoring case; not those
; starting with '.') -> nic, kinds, names
scan:   lda     #K_SD                   ; the fixed icons
        sta     ic_kind
        lda     #K_ATARI
        sta     ic_kind+2
        lda     #NFIX
        sta     z:nfix
        stz     z:pcon
        ldx     #.loword(p_pc)          ; (0.20) the PC volume there: its icon
        jsr     statx
        bcs     :+
        lda     #K_PC
        sta     ic_kind+4
        inc     z:nfix
        inc     z:pcon
:       lda     z:nfix
        sta     z:nic
        stz     z:skip
@call:  lda     #.loword(p_desk)        ; block: path, buffer, length, skip
        sta     rblk
        lda     #^p_desk
        sta     rblk+2
        lda     #.loword(dbuf)
        sta     rblk+3
        lda     #^dbuf
        sta     rblk+5
        lda     #DBUFLEN
        sta     rblk+6
        lda     z:skip
        sta     rblk+8
        ptr     rblk
        sys     SYS_READDIR
        jcs     @out
        cmp     #0
        jeq     @out
        sta     z:cnt
        clc
        adc     z:skip
        sta     z:skip
        ldx     #0
@ent:   stx     z:dpos
        lda     z:nic
        cmp     #NICON
        jcs     @out
        lda     dbuf+6,x                ; (".name": left out)
        and     #$00FF
        cmp     #'.'
        beq     :+
        jsr     addname
:       ldx     z:dpos
        lda     dbuf+5,x
        and     #$00FF
        clc
        adc     #6
        adc     z:dpos
        tax
        dec     z:cnt
        bne     @ent
        jmp     @call
@out:   rts

; the timer (and after a change): read /Desktop again; when it changed, every icon again
rescan: jsr     scan
        lda     z:pcon                  ; (0.20) the PC came: its clock
        cmp     z:pcwas
        beq     :+
        sta     z:pcwas
        ldx     #$FFFF                  ; (the icons after it move: no selection)
        stx     z:sel
        cmp     #0
        beq     :+
        jsr     ui_clkpc
        bcs     :+
        jsr     clock
:       jsr     namesum
        cmp     z:sum
        beq     @out
        sta     z:sum
        jsr     load
        jsr     place
        jmp     redraw
@out:   rts

; the icons' area cleared, every icon drawn
redraw: lda     z:back
        sta     z:ui_win
        lda     #640 - RIGHT - CELLW * NCOLS
        sta     z:ui_x
        stz     z:ui_y
        lda     #CELLW * NCOLS
        sta     z:ui_w
        lda     #TOP + CELLH * NROWS
        sta     z:ui_h
        jsr     dither
        ; fall through
; all the icons (the selection kept if it is still one)
drawall:
        lda     z:sel
        cmp     z:nic
        bcc     :+
        lda     #$FFFF
        sta     z:sel
:       stz     z:i
:       lda     z:i
        cmp     z:nic
        bcs     :+
        jsr     drawicon
        inc     z:i
        bra     :-
:       rts

; a checksum of the /Desktop names, their kinds and their number -> A
namesum:
        lda     z:nfix
        jsr     nameof
        tax
        lda     z:nic
        sta     z:c
        ldy     z:nfix
@s:     cpy     z:nic
        bcs     @out
        phx
        tya
        asl     a
        tax
        lda     ic_kind,x
        clc
        adc     z:c
        sta     z:c
        plx
        phx
:       lda     a:0,x
        and     #$00FF
        beq     :+
        asl     z:c                     ; c = c * 2 + byte (rotated)
        bcc     @nc
        inc     z:c
@nc:    clc
        adc     z:c
        sta     z:c
        inx
        bra     :-
:       pla
        clc
        adc     #NAMEL
        tax
        iny
        bra     @s
@out:   lda     z:c
        rts

; the entry dpos of dbuf: its name and kind into slot nic, inserted in order
addname:
        lda     z:nic                   ; slot nic: the kind, the name
        asl     a
        tay
        ldx     z:dpos
        lda     dbuf+4,x
        and     #$0010
        beq     :+
        lda     #K_FOLDER
        bra     :++
:       lda     #K_FILE
:       sta     ic_kind,y
        lda     z:nic                   ; -> z:p (slot nic)
        jsr     nameof
        sta     z:p
        ldx     z:dpos
        lda     dbuf+5,x
        and     #$00FF
        cmp     #NAMEL - 1
        bcc     :+
        lda     #NAMEL - 1
:       sta     z:t
        ldy     #0
        sep     #$20
        .a8
:       cpy     z:t
        beq     :+
        lda     dbuf+6,x
        sta     (p),y
        inx
        iny
        bra     :-
:       lda     #0
        sta     (p),y
        rep     #$20
        .a16
        lda     z:nic                   ; insertion: move it down while the one before
        sta     z:t                     ; sorts after it (the fixed ones stay)
@ins:   lda     z:t
        dec     a
        cmp     z:nfix
        bcc     @done
        jsr     slotname                ; q = name t, r = name t - 1
        jsr     cmpname                 ; C set: q before r
        bcc     @done
        ldy     #0                      ; swap the names
        sep     #$20
        .a8
:       lda     (q),y
        pha
        lda     (r),y
        sta     (q),y
        pla
        sta     (r),y
        iny
        cpy     #NAMEL
        bne     :-
        rep     #$20
        .a16
        lda     z:t                     ; and the kinds
        asl     a
        tax
        lda     ic_kind,x
        pha
        lda     ic_kind-2,x
        sta     ic_kind,x
        pla
        sta     ic_kind-2,x
        dec     z:t
        bra     @ins
@done:  inc     z:nic
        rts

; A = slot -> A = its name's address
nameof: xba                             ; * 128 (NAMEL)
        lsr     a
        and     #$7F80
        clc
        adc     #.loword(names)
        rts
; A = slot -> A = its label's address (* 40)
labof:  asl     a
        asl     a
        asl     a
        sta     z:t
        asl     a
        asl     a
        clc
        adc     z:t
        adc     #.loword(labs)
        rts
; q = the name of slot t, r = the one of slot t - 1
slotname:
        lda     z:t
        jsr     nameof
        sta     z:q
        sec
        sbc     #NAMEL
        sta     z:r
        rts

; C set if name q sorts before name r (ignoring case)
cmpname:
        ldy     #0
:       lda     (q),y
        jsr     lower
        sta     z:c
        lda     (r),y
        jsr     lower
        cmp     z:c
        beq     :+
        rts                             ; (r > q: C set)
:       cmp     #0
        beq     @no
        iny
        bra     :--
@no:    clc
        rts

; A = character -> lower case (A-Z only)
lower:  and     #$00FF
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
:       rts

; A = icon -> X = its kind * 2 ... (A = the kind)
kindof: asl     a
        tax
        lda     ic_kind,x
        rts

; every icon's picture, label and whether it is a shortcut (after a change of /Desktop)
load:   lda     #ICO_SD
        sta     ic_ico
        lda     #ICO_ATARI
        sta     ic_ico+2
        stz     ic_lnk
        stz     ic_lnk+2
        lda     #0
        jsr     labof
        tay
        ldx     #.loword(t_sd)
        jsr     ui_strcpy
        lda     #1
        jsr     labof
        tay
        ldx     #.loword(t_atari)
        jsr     ui_strcpy
        lda     z:pcon                  ; (0.20) the PC
        beq     :+
        lda     #ICO_PC
        sta     ic_ico+4
        stz     ic_lnk+4
        lda     #2
        jsr     labof
        tay
        ldx     #.loword(t_pc)
        jsr     ui_strcpy
:       lda     z:nfix
        sta     z:i
:       lda     z:i
        cmp     z:nic
        bcs     :+
        jsr     loadent
        inc     z:i
        bra     :-
:       rts

; icon i (a /Desktop entry): its picture (ic_ico), label, shortcut flag (ic_lnk)
loadent:
        lda     z:i                     ; the label: the name
        jsr     nameof
        tax
        lda     z:i
        jsr     labof
        sta     z:p
        tay
        jsr     ui_strcpy
        lda     z:i
        asl     a
        tax
        stz     ic_lnk,x
        lda     ic_kind,x
        cmp     #K_FOLDER
        bne     :+
        lda     #ICO_FOLDER
        bra     @set
:       lda     z:i
        jsr     iconpath
        ldx     #.loword(pth)
        jsr     ui_ftype
        cmp     #FT_LINK
        beq     @lnk
        ldx     #.loword(pth)
        lda     #0
        jsr     ui_ficon
@set:   pha
        lda     z:i
        asl     a
        tax
        pla
        sta     ic_ico,x
        rts
@lnk:   lda     z:i                     ; a shortcut: the label without ".LNK"
        asl     a
        tax
        inc     ic_lnk,x
        ldy     #0
        ldx     #$FFFF
:       lda     (p),y
        and     #$00FF
        beq     :++
        cmp     #'.'
        bne     :+
        tyx
:       iny
        bra     :--
:       cpx     #$FFFF
        beq     :+
        txy
        lda     #0
        sep     #$20
        .a8
        sta     (p),y
        rep     #$20
        .a16
:       ldx     #.loword(pth)
        jsr     ui_lnkread
        bcc     :+
        lda     #ICO_DOC
        bra     @set
:       lda     ui_lktitl               ; its title, if it has one
        and     #$00FF
        beq     :+
        ldx     #.loword(ui_lktitl)
        ldy     z:p
        jsr     ui_strcpy
:       ldx     #.loword(ui_lktgt)      ; the icon of its target
        jsr     statx
        lda     #0
        bcs     :+
        lda     st+4
        and     #$0010
        beq     :+
        lda     #1
:       ldx     #.loword(ui_lktgt)
        jsr     ui_ficon
        bra     @set

; ---- the grid
; every icon a cell: from /SYSTEM/LAYOUT (not for Tidy up), the rest the first free one
; (a pending place first: where something was dropped); the layout saved when it changed
place:  ldx     #0
        lda     #$FFFF
:       sta     ic_cell,x
        inx
        inx
        cpx     #NICON * 2
        bne     :-
        lda     z:tidy
        bne     :+
        jsr     layload
:       stz     z:i
@i:     lda     z:i
        cmp     z:nic
        bcs     @pos
        asl     a
        tax
        lda     ic_cell,x
        cmp     #$FFFF
        bne     @n
        lda     #$FFFF
        sta     z:ex
        lda     z:pend                  ; where it was dropped
        cmp     #$FFFF
        beq     @first
        jsr     cellfree
        bcs     @first
        ldx     #$FFFF
        stx     z:pend
        inc     z:dirty
        bra     @set
@first: inc     z:dirty                 ; the first free cell (then saved)
        lda     #0
:       jsr     cellfree
        bcc     @set
        inc     a
        cmp     #NCELL
        bcc     :-
        bra     @n                      ; (no room: not shown)
@set:   pha
        lda     z:i
        asl     a
        tax
        pla
        sta     ic_cell,x
@n:     inc     z:i
        bra     @i
@pos:   jsr     setposall
        lda     z:tidy
        ora     z:dirty
        beq     :+
        jsr     laysave
:       stz     z:tidy
        stz     z:dirty
        rts

; C clear if no icon but icon ex has cell A (keeps A)
cellfree:
        ldx     #0
        ldy     #0
@c:     cpy     z:nic
        bcs     @yes
        cpy     z:ex
        beq     :+
        cmp     ic_cell,x
        beq     @no
:       inx
        inx
        iny
        bra     @c
@yes:   clc
        rts
@no:    sec
        rts

; every icon's place from its cell (ic_x, ic_y; no cell: off the desktop)
setposall:
        ldx     #0
:       phx
        jsr     setpos
        plx
        inx
        inx
        cpx     #NICON * 2
        bne     :-
        rts
; X = icon * 2: ic_x, ic_y from ic_cell (x = 640 - RIGHT - CELLW (col + 1), y = TOP + CELLH row)
setpos: stx     z:yy
        lda     ic_cell,x
        cmp     #$FFFF
        bne     :+
        lda     #$7000
        sta     ic_x,x
        sta     ic_y,x
        rts
:       ldx     #NROWS
        jsr     divmod                  ; A = column, X = row
        stx     z:m
        inc     a
        tay
        lda     #640 - RIGHT
:       sec
        sbc     #CELLW
        dey
        bne     :-
        ldx     z:yy
        sta     ic_x,x
        ldy     z:m
        lda     #TOP
:       dey
        bmi     :+
        clc
        adc     #CELLH
        bra     :-
:       sta     ic_y,x
        rts

; the cell nearest to the content point (X, Y) that is free (but for icon ex) -> A, C clear;
; C set: none free
cellnear:
        txa                             ; the cell under it: column, row
        cmp     #640 - RIGHT
        bcc     :+
        lda     #640 - RIGHT - 1
:       eor     #$FFFF
        sec
        adc     #640 - RIGHT
        ldx     #CELLW
        jsr     divmod
        cmp     #NCOLS
        bcc     :+
        lda     #NCOLS - 1
:       sta     z:hx
        tya
        sec
        sbc     #TOP
        bpl     :+
        lda     #0
:       ldx     #CELLH
        jsr     divmod
        cmp     #NROWS
        bcc     :+
        lda     #NROWS - 1
:       sta     z:hy
        lda     #$FFFF                  ; the best so far
        sta     z:bc
        sta     z:bd
        stz     z:cc                    ; every cell: its distance |dcol| + |drow|
@c:     lda     z:cc
        jsr     cellfree
        bcs     @n
        ldx     #NROWS
        jsr     divmod
        sec
        sbc     z:hx
        jsr     abs
        sta     z:t
        txa
        sec
        sbc     z:hy
        jsr     abs
        clc
        adc     z:t
        cmp     z:bd
        bcs     @n
        sta     z:bd
        lda     z:cc
        sta     z:bc
@n:     inc     z:cc
        lda     z:cc
        cmp     #NCELL
        bcc     @c
        lda     z:bc
        cmp     #$FFFF
        beq     :+
        clc
        rts
:       sec
        rts

; /SYSTEM/LAYOUT ("col row name" lines) -> the icons' cells (a cell only once)
layload:
        ptr     p_layout
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        rts
:       sta     z:t
        sta     rwblk
        lda     #.loword(lay)
        sta     rwblk+1
        lda     #^lay
        sta     rwblk+3
        lda     #LAYL - 1
        sta     rwblk+4
        ptr     rwblk
        sys     SYS_READ
        php
        pha
        lda     z:t
        sys     SYS_CLOSE
        pla
        plp
        bcc     :+
        rts
:       tax
        sep     #$20
        .a8
        stz     lay,x
        rep     #$20
        .a16
        ldx     #.loword(lay)
@line:  lda     a:0,x
        and     #$00FF
        jeq     @out
        jsr     @num                    ; column, row
        sta     z:hx
        jsr     @num
        sta     z:hy
        lda     a:0,x                   ; one space, then the name
        and     #$00FF
        cmp     #' '
        bne     :+
        inx
:       ldy     #0
:       lda     a:0,x
        and     #$00FF
        cmp     #' '
        bcc     :+
        cpy     #NAMEL - 1
        bcs     @nx
        sep     #$20
        .a8
        sta     lbuf,y
        rep     #$20
        .a16
        iny
@nx:    inx
        bra     :-
:       lda     #0
        sta     lbuf,y
        phx
        jsr     @match
        plx
:       lda     a:0,x                   ; to the next line
        and     #$00FF
        beq     @out
        inx
        cmp     #10
        bne     :-
        bra     @line
@out:   rts
; a decimal number at X (spaces before it skipped) -> A, X past it
@num:   lda     a:0,x
        and     #$00FF
        cmp     #' '
        bne     :+
        inx
        bra     @num
:       stz     z:t
:       lda     a:0,x
        and     #$00FF
        sec
        sbc     #'0'
        cmp     #10
        bcs     :+
        pha
        lda     z:t
        asl     a
        sta     z:t
        asl     a
        asl     a
        clc
        adc     z:t
        sta     z:t
        pla
        clc
        adc     z:t
        sta     z:t
        inx
        bra     :-
:       lda     z:t
        rts
; the icon named lbuf (":SD", ":ATARI" or a /Desktop name) gets cell hx, hy if free
@match: lda     z:hx
        cmp     #NCOLS
        bcs     @mo
        lda     z:hy
        cmp     #NROWS
        bcs     @mo
        lda     #.loword(lbuf)
        sta     z:q
        lda     #.loword(k_pc)          ; (0.20) the PC's cell, kept while it is away
        sta     z:r
        jsr     streq
        bcs     :+
        lda     z:hx
        asl     a
        asl     a
        adc     z:hx
        adc     z:hy
        sta     z:pccell
:       stz     z:i
@mi:    lda     z:i
        cmp     z:nic
        bcs     @mo
        jsr     iconkey
        sta     z:r
        jsr     streq
        bcc     @got
        inc     z:i
        bra     @mi
@got:   lda     z:i
        asl     a
        tax
        lda     ic_cell,x
        cmp     #$FFFF
        bne     @mo
        lda     z:hx                    ; cell = column * NROWS + row
        asl     a
        asl     a
        adc     z:hx
        adc     z:hy
        ldx     #$FFFF
        stx     z:ex
        jsr     cellfree
        bcs     @mo
        pha
        lda     z:i
        asl     a
        tax
        pla
        sta     ic_cell,x
@mo:    rts

; icon i's name in the layout -> A (":SD", ":ATARI", else its /Desktop name)
iconkey:
        lda     z:i
        bne     :+
        lda     #.loword(k_sd)
        rts
:       cmp     #1
        bne     :+
        lda     #.loword(k_atari)
        rts
:       jsr     kindof
        cmp     #K_PC
        bne     :+
        lda     #.loword(k_pc)
        rts
:       lda     z:i
        jmp     nameof

; the icons' cells -> /SYSTEM/LAYOUT
laysave:
        lda     z:pcon                  ; (0.20) the PC's cell kept
        beq     :+
        lda     ic_cell+4
        sta     z:pccell
:       lda     #.loword(lay)
        sta     z:wp
        stz     z:i
@i:     lda     z:i
        cmp     z:nic
        bcs     @w
        asl     a
        tax
        lda     ic_cell,x
        cmp     #$FFFF
        beq     @n
        ldx     #NROWS
        jsr     divmod
        phx
        ldy     z:wp
        jsr     putdec
        lda     #' '
        jsr     wputy
        pla
        jsr     putdec
        lda     #' '
        jsr     wputy
        sty     z:wp
        jsr     iconkey
        tax
        ldy     z:wp
        jsr     ui_strcpy
        clc
        adc     z:wp
        tay
        lda     #10
        jsr     wputy
        sty     z:wp
@n:     inc     z:i
        bra     @i
@w:     lda     z:pcon                  ; (0.20) the PC away: its line stays (its cell free)
        bne     @w2
        lda     z:pccell
        cmp     #$FFFF
        beq     @w2
        ldx     #$FFFF
        stx     z:ex
        jsr     cellfree
        bcs     @w2
        ldx     #NROWS
        jsr     divmod
        phx
        ldy     z:wp
        jsr     putdec
        lda     #' '
        jsr     wputy
        pla
        jsr     putdec
        lda     #' '
        jsr     wputy
        sty     z:wp
        ldx     #.loword(k_pc)
        jsr     ui_strcpy
        clc
        adc     z:wp
        tay
        lda     #10
        jsr     wputy
        sty     z:wp
@w2:    ptr     p_layout
        lda     #O_CREATE
        sys     SYS_OPEN
        bcs     @out
        sta     z:t
        sta     rwblk
        lda     #.loword(lay)
        sta     rwblk+1
        lda     #^lay
        sta     rwblk+3
        lda     z:wp
        sec
        sbc     #.loword(lay)
        sta     rwblk+4
        ptr     rwblk
        sys     SYS_WRITE
        lda     z:t
        sys     SYS_CLOSE
@out:   rts
; A (a byte) at Y, Y + 1
wputy:  sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
        rts

; ---- drawing
; icon picture A (ICO_*) at the backdrop's (cx + 20, cy), 255 transparent
blicon: ldx     z:icbank
        bne     :+
        rts
:       xba                             ; * 1024
        asl     a
        asl     a
        sta     blk+12
        lda     z:icbank
        sta     blk+14
        lda     #WD_KBLIT
        sta     blk
        lda     #$00FF
        sta     blk+2
        lda     z:cx
        clc
        adc     #(CELLW - 32) / 2
        sta     blk+4
        lda     z:cy
        sta     blk+6
        lda     #32
        sta     blk+8
        sta     blk+10
        jmp     draw

; draw icon i: its picture (the desktop under it first), its marks, its label (on
; C_SELECT if selected)
drawicon:
        lda     z:i
        asl     a
        tax
        lda     ic_x,x
        cmp     #$7000
        bne     :+
        rts
:       sta     z:cx
        lda     ic_y,x
        sta     z:cy
        lda     z:back
        sta     z:ui_win
        lda     z:cx
        clc
        adc     #(CELLW - 32) / 2
        sta     z:ui_x
        lda     z:cy
        sta     z:ui_y
        lda     #32
        sta     z:ui_w
        sta     z:ui_h
        jsr     dither
        lda     z:i
        asl     a
        tax
        lda     ic_ico,x
        jsr     blicon
        lda     z:i                     ; a shortcut: the arrow
        asl     a
        tax
        lda     ic_lnk,x
        beq     :+
        lda     #ICO_LINK
        jsr     blicon
:       lda     z:i                     ; the Atari with something loaded: the mark
        jsr     kindof
        cmp     #K_ATARI
        bne     drawlabel
        lda     z:atany
        beq     drawlabel
        lda     #ICO_LOADED
        jsr     blicon
        ; fall through
; the label of icon i (cx, cy set): the backdrop under it, then the text
drawlabel:
        lda     z:i                     ; the text, cut to LABW
        jsr     labof
        tax
        ldy     #.loword(lbuf)
        jsr     ui_strcpy
        ldx     #.loword(lbuf)          ; printable
:       lda     a:0,x
        and     #$00FF
        beq     :++
        cmp     #' '
        bcc     :+
        cmp     #$7F
        bcc     @pr
:       sep     #$20
        .a8
        lda     #'?'
        sta     a:0,x
        rep     #$20
        .a16
@pr:    inx
        bra     :--
:       ldx     #.loword(lbuf)
        lda     #LABW
        jsr     ui_fit
        ldx     #.loword(lbuf)
        lda     #0
        jsr     ui_twidth
        sta     z:lw
        lda     z:back
        sta     z:ui_win
        lda     z:cx                    ; the backdrop under the whole label strip
        sta     z:ui_x
        lda     z:cy
        clc
        adc     #LABY
        sta     z:ui_y
        lda     #CELLW
        sta     z:ui_w
        lda     #UI_LINE + 2
        sta     z:ui_h
        jsr     dither
        lda     #CELLW                  ; the text's x: centred
        sec
        sbc     z:lw
        lsr     a
        clc
        adc     z:cx
        sta     z:ui_x
        stz     z:ui_font
        lda     z:i
        cmp     z:sel
        bne     @plain
        dec     z:ui_x                  ; selected: on C_SELECT, 2 pixels around
        dec     z:ui_x
        lda     z:lw
        clc
        adc     #4
        sta     z:ui_w
        lda     #UI_LINE
        sta     z:ui_h
        lda     #WD_FILL | (C_SELECT << 8)
        jsr     ui_rect
        inc     z:ui_x
        inc     z:ui_x
        inc     z:ui_y
        ldx     #.loword(lbuf)
        lda     #C_WHITE | ($FF << 8)
        jmp     ui_text
@plain: inc     z:ui_x                  ; white, with a dark shadow
        inc     z:ui_y
        inc     z:ui_y
        ldx     #.loword(lbuf)
        lda     #C_SHADOW | ($FF << 8)
        jsr     ui_text
        dec     z:ui_x
        dec     z:ui_y
        ldx     #.loword(lbuf)
        lda     #C_WHITE | ($FF << 8)
        jmp     ui_text

; the icon at content (X = x, Y = y) -> A, C clear; C set: none
iconxy: stx     z:hx
        sty     z:hy
        ldx     #0
@i:     cpx     z:nic
        bcs     @no
        phx
        txa
        asl     a
        tax
        lda     z:hx
        sec
        sbc     ic_x,x
        sec
        sbc     #4
        cmp     #CELLW - 8
        bcs     @nx
        lda     z:hy
        sec
        sbc     ic_y,x
        cmp     #LABY + UI_LINE + 1
        bcs     @nx
        pla
        clc
        rts
@nx:    plx
        inx
        bra     @i
@no:    sec
        rts
; the icon under the pointer of the event (a, b)
iconat: ldx     ui_ev+2
        ldy     ui_ev+4
        bra     iconxy

; select icon A ($FFFF: none): the old and the new label redrawn
setsel: cmp     z:sel
        beq     @out
        ldx     z:sel
        sta     z:sel
        cpx     #$FFFF
        beq     :+
        stx     z:i
        jsr     lab_i
:       lda     z:sel
        cmp     #$FFFF
        beq     @out
        sta     z:i
        jsr     lab_i
@out:   rts
lab_i:  lda     z:i
        asl     a
        tax
        lda     ic_x,x
        sta     z:cx
        lda     ic_y,x
        sta     z:cy
        jmp     drawlabel
; icon A drawn again (picture and label)
icon_i: sta     z:i
        jmp     drawicon

; pth = "/Desktop/" + the name of icon A -> A = its length
iconpath:
        jsr     nameof
        pha
        ldx     #.loword(p_deskd)
        ldy     #.loword(pth)
        jsr     ui_strcpy
        sta     z:t
        plx
        lda     z:t
        clc
        adc     #.loword(pth)
        tay
        jsr     ui_strcpy
        clc
        adc     z:t
        rts

; open icon A: the SD card: Files at the root; the Atari: its panel; a /Desktop entry by its
; type (a shortcut: its target)
openicon:
        sta     z:t
        jsr     kindof
        cmp     #K_ATARI
        bne     :+
        jmp     atpanel
:       cmp     #K_SD
        bne     :+
        ldx     #.loword(p_files)
        ldy     #.loword(a_root)
        lda     #.loword(t_files)
        jmp     ui_launch
:       cmp     #K_PC                   ; (0.20) the PC: Files at /PC:
        bne     :+
        ldx     #.loword(p_files)
        ldy     #.loword(p_pc)
        lda     #.loword(t_files)
        jmp     ui_launch
:       lda     z:t
        jsr     iconpath
        ldx     #.loword(pth)
        jmp     ui_open

; a button event: a left press on an icon selects it, a second one within 0.5 s opens it;
; a press elsewhere deselects. An icon pressed and moved more than 4 pixels is dragged; its
; release drops it. A click on the Atari icon opens its panel. The right button released:
; the small menu.
onbutton:
        lda     ui_ev+6
        and     #$0007
        pha
        eor     z:btn
        sta     z:t
        pla
        sta     z:btn
        lda     z:t                     ; (0.15) the right button pressed: the pop-up menu
        and     #$0002
        beq     :+
        lda     z:btn
        and     #$0002
        beq     :+
        lda     #0
        jsr     ctxmenu
        jmp     loop
:       lda     z:t                     ; the left button changed?
        and     #$0001
        jeq     loop
        lda     z:btn
        and     #$0001
        jeq     release
        stz     z:drag                  ; a press
        lda     #$FFFF
        sta     z:dragi
        jsr     iconat
        bcc     :+
        lda     #$FFFF
        jsr     setsel
        jmp     loop
:       sta     z:t
        sys     SYS_UPTIME
        sta     z:now
        lda     z:t
        cmp     z:sel
        bne     @first
        lda     z:now
        sec
        sbc     z:lastclk
        cmp     #500
        bcs     @first
        stz     z:lastclk
        lda     z:t                     ; open it
        jsr     openicon
        stz     z:btn
        jmp     loop
@first: lda     z:now
        sta     z:lastclk
        lda     z:t                     ; any icon may be dragged
        sta     z:dragi
        jsr     setsel                  ; (it uses z:t)
        lda     ui_ev+2
        sta     z:px
        lda     ui_ev+4
        sta     z:py
        jmp     loop

; motion with the button held: a drag starts beyond 4 pixels
onmotion:
        lda     z:dragi
        cmp     #$FFFF
        jeq     loop
        lda     z:drag
        jne     loop
        lda     ui_ev+2
        sec
        sbc     z:px
        jsr     abs
        cmp     #5
        bcs     :+
        lda     ui_ev+4
        sec
        sbc     z:py
        jsr     abs
        cmp     #5
        jcc     loop
:       lda     #1
        sta     z:drag
        lda     #PTR_DRAG
        sys     SYS_WPTR
        jmp     loop

abs:    bpl     :+
        eor     #$FFFF
        inc     a
:       rts

; the left button released: a click on the Atari icon opens its panel; a drag ends
; (dropped where the pointer is)
release:
        lda     z:drag
        bne     @drop
        lda     z:dragi                 ; (a click, not a drag)
        cmp     #$FFFF
        jeq     loop
        jsr     kindof
        cmp     #K_ATARI
        jne     loop
        jsr     atpanel
        jmp     loop
@drop:  stz     z:drag
        lda     #PTR_ARROW
        sys     SYS_WPTR
        ldx     ui_ev+2                 ; the window there (screen: the backdrop at y 16)
        lda     ui_ev+4
        clc
        adc     #16
        tay
        sys     SYS_WINAT
        bcs     @no
        cmp     z:back
        beq     @here
        cmp     #$FF
        beq     @no
        pha
        lda     z:dragi                 ; another window: a /Desktop entry's path (Files
        cmp     z:nfix                  ; moves it there)
        pla
        bcc     @no
        pha
        lda     z:dragi
        jsr     iconpath
        ldx     #.loword(pth)
        ldy     #.loword(dropbuf)
        jsr     ui_strcpy
        pla
        ptr     dropbuf
        sys     SYS_WDROP
        bcs     @no
        lda     #60                     ; read /Desktop again a little later
        sys     SYS_SLEEP
        jsr     rescan
        jmp     loop
@here:  jsr     iconat                  ; on another icon: into it (a /Desktop entry)
        bcs     @move
        cmp     z:dragi
        beq     @move
        sta     z:t
        lda     z:dragi
        cmp     z:nfix
        bcc     @no
        lda     z:t
        jsr     kindof
        cmp     #K_ATARI
        bne     :+
        lda     z:dragi                 ; onto the Atari: mounted
        jsr     iconpath
        ldx     #.loword(pth)
        jsr     mount
        jmp     loop
:       lda     z:dragi
        jsr     iconpath
        ldx     #.loword(pth)
        ldy     #.loword(dropbuf)
        jsr     ui_strcpy
        lda     z:t
        jsr     moveto
        bcs     @no
        jsr     rescan
@out:   jmp     loop
@no:    jsr     ui_beep
        jmp     loop
@move:  lda     z:dragi                 ; elsewhere: the icon goes to the nearest free cell
        sta     z:ex
        ldx     ui_ev+2
        ldy     ui_ev+4
        jsr     cellnear
        bcs     @no
        pha
        lda     z:dragi
        asl     a
        tax
        pla
        sta     ic_cell,x
        jsr     setpos
        jsr     laysave
        jsr     redraw
        jmp     loop

; WE_DROP: a path dropped here: on the Atari icon mounted; on a folder icon or the SD card
; moved there; elsewhere a shortcut to it is made in /Desktop (with Shift: it is moved into
; /Desktop), placed where it was dropped
ondrop: lda     z:back
        ptr     dropbuf
        sys     SYS_WDROPGET
        jcs     @no
        lda     dropbuf
        and     #$00FF
        cmp     #'/'
        jne     @no
        jsr     iconat
        bcs     @free
        sta     z:t
        jsr     kindof
        cmp     #K_ATARI
        bne     :+
        ldx     #.loword(dropbuf)
        jsr     mount
        jmp     loop
:       lda     z:t
        jsr     moveto
        bcs     @no
        jsr     rescan
        jmp     loop
@free:  lda     #$FFFF                  ; the cell where it was dropped
        sta     z:ex
        ldx     ui_ev+2
        ldy     ui_ev+4
        jsr     cellnear
        bcc     :+
        lda     #$FFFF
:       sta     z:pend
        lda     ui_ev+6                 ; Shift: moved into /Desktop
        and     #$2200
        beq     :+
        lda     #$FFFF
        jsr     moveto
        bcs     @no
        jsr     rescan
        jmp     loop
:       ldx     #.loword(dropbuf)       ; else a shortcut
        jsr     ui_mklink
        bcs     @no
        jsr     rescan
        jmp     loop
@no:    lda     #$FFFF
        sta     z:pend
        jsr     ui_beep
        jmp     loop

; move dropbuf into the place of icon A ($FFFF: /Desktop; a folder: into it; the SD card:
; the root; (0.20) the PC: /PC:). C set: refused (another kind, a folder into itself, the
; name there already) or failed. (0.20) Onto the SD card from the PC volume, or onto the PC
; from the card: copied (ui_cptree); else moved (ui_mvtree: between the volumes a copy, then
; the source deleted). (0.21) A long copy or move shows the progress window (ui_cpwin); its
; Cancel returns C clear (nothing to report; the caller looks at the desktop again)
moveto: stz     z:mvcp
        cmp     #$FFFF
        bne     :+
        ldx     #.loword(p_deskd)       ; "/Desktop/"
        ldy     #.loword(pth)
        jsr     ui_strcpy
        bra     @dir
:       sta     z:t
        jsr     kindof
        cmp     #K_SD
        bne     :+
        ldx     #.loword(dropbuf)       ; (from the PC: copied)
        jsr     ispc
        rol     z:mvcp
        lda     #'/'                    ; "/"
        sta     pth
        lda     #1
        bra     @dir
:       cmp     #K_PC
        bne     :+
        ldx     #.loword(dropbuf)       ; (from the card: copied)
        jsr     ispc
        rol     z:mvcp
        lda     z:mvcp
        eor     #1
        sta     z:mvcp
        ldx     #.loword(p_pcd)         ; "/PC:/"
        ldy     #.loword(pth)
        jsr     ui_strcpy
        bra     @dir
:       cmp     #K_FOLDER
        beq     :+
        sec
        rts
:       lda     z:t                     ; "/Desktop/name/"
        jsr     iconpath
        tax
        lda     #'/'                    ; ('/', 0)
        sta     pth,x
        inx
        txa
@dir:   sta     z:p                     ; (the folder's length, with its '/')
        ldy     #0                      ; the folder inside what is moved (or itself)?
:       lda     dropbuf,y
        jsr     lower
        sta     z:c
        cmp     #0
        beq     @pre
        lda     pth,y
        jsr     lower
        cmp     z:c
        bne     @ok
        iny
        bra     :-
@pre:   lda     pth,y
        and     #$00FF
        cmp     #'/'
        jeq     @bad
@ok:    ldx     #.loword(dropbuf)       ; + the last part of the path
        ldy     #.loword(dropbuf)
:       lda     a:0,y
        and     #$00FF
        beq     :+
        iny
        cmp     #'/'
        bne     :-
        tyx
        bra     :-
:       lda     z:p
        clc
        adc     #.loword(pth)
        tay
        jsr     ui_strcpy
        clc
        adc     z:p
        cmp     #128
        bcs     @bad
        lda     #.loword(dropbuf)       ; rename dropbuf -> pth (refused if pth exists)
        sta     sblk
        lda     #^dropbuf
        sta     sblk+2
        lda     #.loword(pth)
        sta     sblk+3
        lda     #^pth
        sta     sblk+5
        jsr     stpth                   ; (there already?)
        bcc     @bad
        ldx     #.loword(dropbuf)       ; (0.27) between the card and the PC: always a copy
        jsr     ispc
        lda     #0
        rol     a
        pha
        ldx     #.loword(pth)
        jsr     ispc
        lda     #0
        rol     a
        eor     1,s
        beq     @samev
        sta     z:mvcp
@samev: pla
        lda     z:mvcp                  ; (0.21) a long copy or move: the progress window
        eor     #1
        jsr     ui_cpwin
        ldx     #.loword(dropbuf)
        ldy     #.loword(pth)
        lda     z:mvcp
        beq     :+
        jsr     ui_cptree
        bra     :++
:       jsr     ui_mvtree
:       jsr     ui_cpdone
        bcc     :+
        cmp     #ECANCELED              ; cancelled there: no error (what was copied stays)
        bne     @bad
        clc
:       rts
@bad:   sec
        rts

; (0.20) C set if the path X is on the PC volume ("/PC:", then the end or '/'; any case)
ispc:   ldy     #0
:       lda     a:0,x
        jsr     lower
        cmp     p_pclc,y
        bne     @no
        inx
        iny
        cpy     #4
        bcc     :-
        lda     a:0,x
        and     #$00FF
        beq     @yes
        cmp     #'/'
        beq     @yes
@no:    clc
        rts
@yes:   sec
        rts

; ---------------------------------------------------------------- the pop-up menus (0.15)
; A right press (or the menu key / Shift+F10 with an icon selected): a pop-up menu
; (ui_popup, the kernel's SYS_WPOPUP) for the icon there, or for the desktop:
;   the Atari icon: Attach disk..., Attach cartridge..., Run program..., -, one "Eject ..."
;     line per thing loaded, Eject all, -, Restart Atari, Switch to Atari, -, (0.23) Folder
;     disk..., Atari settings..., Open panel
;   the SD card: Open
;   a /Desktop entry: Open, ((0.23) a BASIC program: Run in Atari), (a shortcut: Show
;     original), -, Rename..., Delete
;   the desktop: New folder..., Tidy up, -, Settings...
; A = 0: at the pointer (the event's a, b; the icon there is selected), 1: from the
; keyboard (the selected icon; the menu below it)
ctxmenu:
        sta     z:pkey
        cmp     #0
        bne     :++
        jsr     iconat
        bcc     :+
        lda     #$FFFF
:       sta     z:pui
        jsr     setsel
        bra     :++
:       lda     z:sel
        sta     z:pui
:       lda     z:pui
        cmp     #$FFFF
        jeq     @desk
        jsr     kindof
        cmp     #K_ATARI
        jeq     atmenu
        cmp     #K_PC                   ; (0.20) the PC: as the SD card
        beq     :+
        cmp     #K_SD
        bne     @ent
:       ldx     #.loword(pu_sd)         ; the SD card: Open
        jsr     popup
        cmp     #0
        bne     @out
        lda     z:pui
        jmp     openicon
@out:   rts
@ent:   lda     z:pui                   ; a /Desktop entry: Open, ((0.23) a BASIC program:
        asl     a                       ; Run in Atari), (Show original), -, Rename..., Delete
        tax
        lda     ic_lnk,x
        sta     z:plnk
        jsr     prunq                   ; (0.23) prun: a BASIC program (its path in pth)
        lda     prun
        asl     a
        ora     z:plnk
        asl     a
        tax
        lda     pu_tab,x
        tax
        jsr     popup
        cmp     #$FFFF
        beq     @out
        ldx     prun                    ; (0.23) Run in Atari: item 1; the others after it
        beq     :+                      ; as without it
        cmp     #1
        jeq     runat
        bcc     :+
        dec     a
:       ldx     z:plnk                  ; (not a shortcut: no Show original)
        bne     :+
        cmp     #1
        bcc     :+
        inc     a
:       cmp     #0
        bne     :+
        lda     z:pui
        jmp     openicon
:       cmp     #1
        bne     :+
        jmp     showorig
:       cmp     #3
        bne     :+
        jmp     renicon
:       cmp     #4
        bne     @out
        lda     z:pui
        jmp     delicon
@desk:  ldx     #.loword(pu_desk)       ; the desktop: New folder..., Tidy up, -,
        jsr     popup                   ; Settings...
        cmp     #0
        bne     :+
        jmp     newfolder
:       cmp     #1
        bne     :+
        lda     #1
        sta     z:tidy
        jsr     place
        jmp     redraw
:       cmp     #3
        jne     @out
        ldx     #.loword(p_set)
        ldy     #0
        lda     #.loword(t_settings)
        jmp     ui_launch

; the pop-up menu X on the backdrop: at the pointer (pkey 0), or (from the keyboard, 1)
; below the selected icon; (0.18) in the Atari panel: at the pointer (2), or (from the
; keyboard, 3) at its top left -> A = the item ($FFFF: none)
popup:  lda     z:pkey
        cmp     #2
        bcc     @desk
        bne     @pk
        lda     z:atwin
        jsr     ui_popup
        bra     :++
@pk:    lda     #8
        sta     z:ui_x
        sta     z:ui_y
        lda     z:atwin
        jsr     ui_popat
        bra     :++
@desk:  cmp     #0
        bne     :+
        lda     z:back
        jsr     ui_popup
        bra     :++
:       phx
        lda     z:pui
        asl     a
        tax
        lda     ic_x,x
        clc
        adc     #CELLW / 2 - 16
        sta     z:ui_x
        lda     ic_y,x
        clc
        adc     #LABY + UI_LINE
        sta     z:ui_y
        plx
        lda     z:back
        jsr     ui_popat
:       stz     z:btn                   ; (the menu took the button's release)
        rts

; the Atari icon's menu: what can be loaded, what is loaded (an Eject line each), the
; machine, the panel
atmenu: ldx     #.loword(pu_at1)        ; the fixed start
        ldy     #.loword(pbuf)
        jsr     memcpyz
        sty     z:pw
        stz     z:pn                    ; Eject lines
        stz     z:c
@q:     lda     z:c                     ; each slot loaded: "Eject D1: NAME"
        ptr     qbuf
        sys     SYS_CQUERY
        bcs     @nq
        cmp     #0
        beq     @nq
        lda     z:c
        ldx     z:pn
        sta     pslot,x
        inc     z:pn
        inc     z:pn
        asl     a
        tax
        lda     at_ek,x                 ; "Eject D1: ", "Eject program: ", ...
        tax
        ldy     z:pw
        jsr     memcpy0
        sty     z:pw
        jsr     qname                   ; X = the name in qbuf (after the last '/')
        stx     z:t
        ldy     #0                      ; (32 characters at most)
:       lda     (t),y
        and     #$00FF
        beq     :+
        cpy     #32
        bcs     :+
        sep     #$20
        .a8
        sta     (pw),y
        rep     #$20
        .a16
        iny
        bra     :-
:       lda     #0
        sep     #$20
        .a8
        sta     (pw),y
        rep     #$20
        .a16
        iny
        tya
        clc
        adc     z:pw
        sta     z:pw
@nq:    inc     z:c
        lda     z:c
        cmp     #6
        bcc     @q
        ldx     #.loword(pu_at2)        ; Eject all (dimmed with nothing loaded), the rest
        ldy     z:pw
        jsr     memcpyz
        lda     z:pkey                  ; (0.18) the panel's own menu: no "Open panel"
        cmp     #2
        bcc     :+
        tya
        sec
        sbc     #.strlen("Open panel") + 1
        tax
        lda     #0
        sep     #$20
        .a8
        sta     a:0,x
        rep     #$20
        .a16
:       lda     z:pn
        bne     :+
        ldx     z:pw
        lda     #MS_STATE | MS_DIM
        sep     #$20
        .a8
        sta     a:0,x
        rep     #$20
        .a16
:       ldx     #.loword(pbuf)
        jsr     popup
        cmp     #$FFFF
        jeq     @out
        cmp     #3                      ; 0 Attach disk, 1 Attach cartridge, 2 Run program
        bcs     @ej
        jmp     atattach
@ej:    sec                             ; 4 ..: an Eject line
        sbc     #4
        asl     a
        cmp     z:pn
        bcs     :+
        tax
        lda     pslot,x
        asl     a
        tay
        jmp     ejrow
:       sec                             ; after them: Eject all, -, Restart Atari, Switch to
        sbc     z:pn                    ; Atari, -, (0.23) Folder disk..., Atari settings...,
                                        ; Open panel
        lsr     a
        bne     :+
        jmp     ejectall
:       cmp     #2
        bne     :+
        jmp     atboot
:       cmp     #3
        bne     :+
        sys     SYS_CLASSIC
        stz     z:btn
        jmp     tcatch                  ; (0.23)
:       cmp     #5
        bne     :+
        jmp     fdlg                    ; (0.23)
:       cmp     #6
        bne     :+
        ldx     #.loword(p_set)         ; Settings on its Classic Atari page
        ldy     #.loword(a_atari)
        lda     #.loword(t_settings)
        jmp     ui_launch
:       cmp     #7
        bne     @out
        jmp     atpanel
@out:   rts

; A = 0 Attach disk..., 1 Attach cartridge..., 2 Run program... (the Atari icon's menu, the
; panel's buttons and menu): the file dialog (listing only those), then a disk attached (no
; boot), a cartridge attached (a power cycle: see mount), a program started ("this, and
; only this": the Atari shown until F12)
atattach:
        tax
        lda     at_kinds,x
        and     #$00FF
        sta     ui_dlfilt               ; (the dialog lists only those)
        pha
        txa
        asl     a
        tax
        lda     at_dtit,x
        tay
        stz     pth
        lda     #0
        ldx     #.loword(pth)
        jsr     ui_filedlg
        pla
        bcs     @out
        cmp     #CK_XEX
        beq     @run
        ldx     #.loword(pth)
        jmp     mount
@run:   ldx     #.loword(pth)           ; a program: started (an alert if it cannot be)
        jsr     ui_open
        stz     z:btn
        jmp     atupdate
@out:   rts

; X = the name of the path in qbuf (after its last '/')
qname:  ldx     #.loword(qbuf)
        ldy     #.loword(qbuf)
:       lda     a:0,y
        and     #$00FF
        beq     :+
        iny
        cmp     #'/'
        bne     :-
        tyx
        bra     :-
:       rts

; copy the zero-terminated strings at X up to "" (included) to Y -> Y = the end's ""
memcpyz:
:       lda     a:0,x
        and     #$00FF
        beq     :++
:       jsr     memcpy1
        bra     :--
:       sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        rts
; copy one zero-terminated string X to Y, without its 0 -> Y past it, X past its 0
memcpy0:
:       lda     a:0,x
        and     #$00FF
        beq     :+
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       inx
        rts
; copy one zero-terminated string X to Y, with its 0 -> X, Y past it
memcpy1:
        jsr     memcpy0
        lda     #0
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
        rts

; eject everything (the panel's Eject all, the menu's); (0.18) with a cartridge in it, then
; a power cycle (cstay)
ejectall:
        jsr     cartin
        php
        ldy     #10
:       phy
        jsr     eject
        ply
        dey
        dey
        bpl     :-
        jsr     atupdate
        plp
        bcs     cstay
        rts

; eject row Y / 2 (as eject), then the icon and the panel; (0.18) the cartridge: then a
; power cycle (cstay), as pulling it out of a real machine
ejrow:  phy
        jsr     eject
        jsr     atupdate
        pla
        cmp     #10
        beq     cstay
        rts

; (0.18) a power cycle: the classic machine cold booted with what is loaded, not shown
; (classic_boot CB_STAY); an alert if it fails
cstay:  lda     #CB_STAY
        sys     SYS_CBOOT
        bcc     :+
        sta     z:err
        ldx     #.loword(al_boot)
        jmp     ui_alert
:       rts

; C set if a cartridge is loaded (classic_query)
cartin: lda     #5
        ptr     qbuf
        sys     SYS_CQUERY
        bcs     :+
        cmp     #1                      ; (a length: C set if not 0)
        rts
:       clc
        rts

; restart the Atari with what is loaded (F12 comes back); an alert if it fails. (0.18) A
; true cold start: with a cartridge loaded, no executable stays mounted (the firmware
; boots an executable in preference to the cartridge)
atboot: jsr     cartin
        bcc     :+
        lda     #4
        ptr     qbuf
        sys     SYS_CQUERY
        bcs     :+
        cmp     #0
        beq     :+
        lda     #CK_XEX
        sys     SYS_CEJECT
        jsr     atupdate
:       lda     #0                      ; (not CB_STAY: shown)
        sys     SYS_CBOOT
        php
        pha
        jsr     tcatch                  ; (0.23)
        pla
        plp
        stz     z:btn
        bcc     :+
        sta     z:err
        ldx     #.loword(al_boot)
        jmp     ui_alert
:       rts

; the desktop's New folder...: a name asked, the folder made in /Desktop
newfolder:
        ldx     #.loword(t_newf)
        ldy     #.loword(lbuf)
        jsr     ui_strcpy
        ldx     #.loword(ak_new)
        jsr     ui_ask
        bcs     @out
        lda     lbuf
        and     #$00FF
        beq     @out
        jsr     lbpath                  ; pth = "/Desktop/" + lbuf
        ptr     pth
        sys     SYS_MKDIR
        bcc     :+
        sta     z:err
        ldx     #.loword(al_nonew)
        jmp     ui_alert
:       jmp     rescan
@out:   rts

; pth = "/Desktop/" + lbuf
lbpath: ldx     #.loword(p_deskd)
        ldy     #.loword(pth)
        jsr     ui_strcpy
        clc
        adc     #.loword(pth)
        tay
        ldx     #.loword(lbuf)
        jmp     ui_strcpy

; Rename... (icon pui, a /Desktop entry): its label asked; a file or folder is renamed; a
; shortcut with a title gets the new title, one without is renamed (NAME.LNK)
renicon:
        lda     z:pui                   ; (a shortcut: its label; else its name)
        asl     a
        tax
        lda     ic_lnk,x
        php
        lda     z:pui
        plp
        beq     :+
        jsr     labof
        bra     :++
:       jsr     nameof
:       tax
        ldy     #.loword(lbuf)
        jsr     ui_strcpy
        ldx     #.loword(ak_ren)
        jsr     ui_ask
        bcs     @out
        lda     lbuf
        and     #$00FF
        beq     @out
        lda     z:pui
        jsr     iconpath                ; pth = the old path
        lda     z:pui
        asl     a
        tax
        lda     ic_lnk,x
        beq     @file
        ldx     #.loword(pth)           ; a shortcut: its title?
        jsr     ui_lnkread
        bcs     @file
        lda     ui_lktitl
        and     #$00FF
        beq     @lnk
        jsr     lnkwrite                ; the title rewritten (pth: the file)
        bcs     @bad
        jmp     rescan
@lnk:   ldx     #.loword(t_lnk)         ; no title: NAME.LNK
        jsr     lbcat
@file:  ldx     #.loword(pth)           ; renamed: pth -> /Desktop/lbuf
        ldy     #.loword(abuf)
        jsr     ui_strcpy
        jsr     lbpath
        lda     #.loword(abuf)
        sta     rnblk
        lda     #^abuf
        sta     rnblk+2
        lda     #.loword(pth)
        sta     rnblk+3
        lda     #^pth
        sta     rnblk+5
        ptr     rnblk
        sys     SYS_RENAME
        bcs     @bad
        jmp     rescan
@bad:   sta     z:err
        ldx     #.loword(al_noren)
        jmp     ui_alert
@out:   rts

; lbuf += string X
lbcat:  phx
        ldx     #.loword(lbuf)
        jsr     ui_strlen
        clc
        adc     #.loword(lbuf)
        tay
        plx
        jmp     ui_strcpy

; the shortcut pth written again with the title lbuf (its target and arguments kept)
lnkwrite:
        ldx     #.loword(ui_lktgt)      ; abuf = "target", 10, "title=", lbuf, 10,
        ldy     #.loword(abuf)          ;   ("args=", args, 10)
        jsr     memcpy0
        lda     #10
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
        ldx     #.loword(t_tl)
        jsr     memcpy0
        ldx     #.loword(lbuf)
        jsr     memcpy0
        lda     #10
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
        lda     ui_lkargs
        and     #$00FF
        beq     :+
        ldx     #.loword(t_ar)
        jsr     memcpy0
        ldx     #.loword(ui_lkargs)
        jsr     memcpy0
        lda     #10
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
:       tya                             ; the length
        sec
        sbc     #.loword(abuf)
        pha
        ptr     pth
        lda     #O_CREATE
        sys     SYS_OPEN
        bcs     @bad
        sta     rwblk                   ; {handle, u24 buffer, u16 length}
        lda     #.loword(abuf)
        sta     rwblk+1
        lda     #^abuf
        sta     rwblk+3
        pla
        sta     rwblk+4
        ptr     rwblk
        sys     SYS_WRITE
        lda     rwblk
        and     #$00FF
        sys     SYS_CLOSE
        clc
        rts
@bad:   pla
        sec
        rts

; Show original (a shortcut, icon pui): Files where its target is, the target selected
showorig:
        lda     z:pui
        jsr     iconpath
        ldx     #.loword(pth)
        jsr     ui_lnkread
        bcc     :+
        jmp     ui_beep
:       ldx     #.loword(ui_lktgt)      ; the argument: the target, quoted
        ldy     #.loword(abuf)
        lda     #'"'
        sta     abuf
        iny
        jsr     ui_strcpy
        clc
        adc     #.loword(abuf + 1)
        tay
        lda     #'"'
        sta     a:0,y
        ldx     #.loword(p_files)
        ldy     #.loword(abuf)
        lda     #.loword(t_files)
        jmp     ui_launch

; delete icon A (a /Desktop entry) after a question
delicon:
        sta     z:t
        cmp     z:nfix
        bcs     :+
        jmp     ui_beep
:       sta     z:dl
        jsr     labof                   ; the message: its label
        tax
        ldy     #.loword(lbuf)
        jsr     ui_strcpy
        ldx     #.loword(lbuf)
        lda     #200
        jsr     ui_fit
        ldx     #.loword(t_delf)        ; "Delete NAME from the card?" / "Remove the
        ldy     #.loword(t_delf2)       ; shortcut NAME? The file it opens stays."
        lda     z:dl
        asl     a
        tax
        lda     ic_lnk,x
        beq     :+
        ldx     #.loword(t_dell)
        ldy     #.loword(t_dell2)
        bra     :++
:       ldx     #.loword(t_delf)
:       jsr     mkmsg
        ldx     #.loword(al_del)
        jsr     ui_alert
        cmp     #0
        bne     @out
        lda     z:dl
        jsr     iconpath
        ptr     pth
        sys     SYS_DELETE
        bcc     :+
        ldx     #.loword(al_nodel)
        jsr     ui_alert
        rts
:       lda     #$FFFF
        sta     z:sel
        jsr     rescan
@out:   rts

; abuf = string X + lbuf + string Y
mkmsg:  phy
        ldy     #.loword(abuf)
        jsr     ui_strcpy
        clc
        adc     #.loword(abuf)
        sta     z:t
        tay
        ldx     #.loword(lbuf)
        jsr     ui_strcpy
        clc
        adc     z:t
        tay
        plx
        jmp     ui_strcpy

; ---------------------------------------------------------------- the Atari panel
; C set if what is loaded changed from at_any (atany: 1 when anything is mounted)
atcheck:
        stz     z:t
        lda     #5
        sta     z:c
:       lda     z:c
        ptr     qbuf
        sys     SYS_CQUERY
        bcs     :+
        cmp     #0
        beq     :+
        inc     z:t
:       dec     z:c
        bpl     :--
        lda     z:t
        beq     :+
        lda     #1
:       cmp     z:atany
        beq     :+
        sta     z:atany
        sec
        rts
:       clc
        rts

; something was mounted or ejected: the Atari icon's mark, the panel
atchanged:
        lda     #1
        jsr     icon_i
        lda     z:atwin
        cmp     #$FFFF
        beq     :+
        jsr     atfill
        ldx     #.loword(at_ctl)
        jsr     ui_drawall
:       rts

; after a mount / eject: both drawn again
atupdate:
        jsr     atcheck
        lda     #1
        jsr     icon_i
        lda     z:atwin
        cmp     #$FFFF
        beq     :+
        jsr     atfill
        ldx     #.loword(at_ctl)
        jsr     ui_drawall
:       rts

; the panel opened (or, open already, opened again on top)
atpanel:
        lda     z:atwin
        cmp     #$FFFF
        beq     :+
        sys     SYS_WCLOSE
:       ptr     atblk
        sys     SYS_WOPEN
        bcc     :+
        lda     #$FFFF
        sta     z:atwin
        jmp     ui_beep
:       sta     z:atwin
        sep     #$20                    ; (0.23) the Refresh button (not always in the list)
        .a8
        sta     bt_fref+CT_WIN
        rep     #$20
        .a16
        ldx     #$FFFF                  ; (no Refresh drawn yet)
        stx     fdold
        ldx     #0                      ; the controls' window
:       lda     at_ctl,x
        beq     :+
        phx
        tax
        sep     #$20
        .a8
        lda     z:atwin
        sta     a:CT_WIN,x
        rep     #$20
        .a16
        plx
        inx
        inx
        bra     :-
:       jsr     atfill
        ldx     #.loword(at_ctl)
        jmp     ui_drawall

; the rows' texts from classic_query: the file's name, or "(empty)" dimmed (and its Eject)
atfill: stz     z:c
@r:     lda     z:c
        asl     a
        tax
        lda     at_nl,x
        sta     z:p                     ; the name's label
        lda     at_eb,x
        sta     z:q                     ; its button
        lda     z:c
        asl     a                       ; its buffer: at_nm + row * 48
        asl     a
        asl     a
        asl     a
        sta     z:t
        asl     a
        adc     z:t
        adc     #.loword(at_nm)
        sta     z:r
        ldx     z:p
        sta     a:LB_TEXT,x
        lda     z:c
        ptr     qbuf
        sys     SYS_CQUERY
        bcs     @empty
        cmp     #0
        beq     @empty
        ldx     #.loword(qbuf)          ; its name (after the last '/')
        ldy     #.loword(qbuf)
:       lda     a:0,y
        and     #$00FF
        beq     :+
        iny
        cmp     #'/'
        bne     :-
        tyx
        bra     :-
:       stx     z:t                     ; (40 characters at most)
        ldy     #0
:       lda     (t),y
        and     #$00FF
        beq     :+
        cpy     #40
        bcs     :+
        sep     #$20
        .a8
        sta     (r),y
        rep     #$20
        .a16
        iny
        bra     :-
:       lda     #0
        sep     #$20
        .a8
        sta     (r),y
        rep     #$20
        .a16
        ldx     z:p
        lda     #0
        sta     a:CT_FLAGS,x
        ldx     z:q
        sta     a:CT_FLAGS,x
        bra     @n
@empty: ldx     #.loword(t_empty)
        ldy     z:r
        jsr     ui_strcpy
        ldx     z:p
        lda     #UF_DIM
        sta     a:CT_FLAGS,x
        ldx     z:q
        sta     a:CT_FLAGS,x
@n:     inc     z:c
        lda     z:c
        cmp     #6
        jcc     @r
        jmp     atfold                  ; (0.23) the folder disk

; an event of the panel: its close box, its buttons; (0.18) a right press or the menu key:
; the Atari icon's menu (without Open panel)
atevent:
        lda     ui_ev
        and     #$00FF
        cmp     #WE_CLOSE
        bne     :+
        lda     z:atwin
        sys     SYS_WCLOSE
        lda     #$FFFF
        sta     z:atwin
        rts
:       cmp     #WE_BUTTON
        bne     :+
        lda     ui_ev+6                 ; the right button pressed (ui_rbtn: it was up)
        and     #$0002
        beq     :+
        lda     ui_rbtn
        bne     :+
        lda     #2                      ; at the pointer
        sta     z:pkey
        jmp     atmenu
:       jsr     ui_menukey
        bcc     :+
        lda     #3                      ; at the panel's top left, from the keyboard
        sta     z:pkey
        jmp     atmenu
:       ldx     #.loword(at_ctl)
        jsr     ui_event
        cmp     #UA_CLICK
        beq     :+
        rts
:       stx     z:t
        ldy     #0                      ; an Eject: that row
@e:     lda     at_eb,y
        cmp     z:t
        beq     @ej
        iny
        iny
        cpy     #12
        bne     @e
        ldy     #0                      ; (0.18) Attach disk..., Attach cartridge...,
@a:     lda     at_ab,y                 ; Run program...: as the menu's
        cmp     z:t
        beq     @at
        iny
        iny
        cpy     #6
        bne     @a
        cpx     #.loword(bt_fdk)        ; (0.23) Folder disk..., Refresh
        bne     :+
        jmp     fdlg
:       cpx     #.loword(bt_fref)
        bne     :+
        jmp     fdref
:       cpx     #.loword(bt_eja)
        bne     @sw
        jmp     ejectall
@sw:    cpx     #.loword(bt_switch)
        bne     @bt
        sys     SYS_CLASSIC
        stz     z:btn
        jmp     tcatch                  ; (0.23)
@bt:    cpx     #.loword(bt_boot)
        bne     @out
        jmp     atboot                  ; with what is loaded; F12 comes back
@out:   rts
@ej:    jmp     ejrow
@at:    tya
        lsr     a
        jmp     atattach

; eject row Y / 2 (0-3 D1:-D4:, 4 the executable, 5 the cartridge)
eject:  tya
        lsr     a
        cmp     #4
        bcs     :+
        xba                             ; a disk: kind 1, slot << 8
        ora     #1
        bra     :+++
:       bne     :+
        lda     #2
        bra     :++
:       lda     #3
:       sys     SYS_CEJECT
        rts

; mount the file X (a shortcut: its target) by its kind (ui_atload): a disk on the first
; empty drive (D1: is taken while an executable is loaded; all taken: D1:), an executable;
; (0.18) a cartridge: a power cycle (the executable ejected, the cartridge mounted, the
; classic machine cold booted and not shown). The panel and the icon follow. Not an Atari
; file, or an error: an alert.
mount:  stx     z:p
        jsr     ui_ftype
        cmp     #FT_LINK
        bne     :+
        ldx     z:p
        jsr     ui_lnkread
        bcs     @not
        lda     #.loword(ui_lktgt)
        sta     z:p
:       ldx     z:p
        jsr     ui_atload
        bcc     @ok
        cmp     #0
        beq     @not
        sta     z:err
        ldx     #.loword(al_mount)
        cmp     #ENOMEM                 ; (0.18) no room for the cartridge's banks
        bne     :+
        ldx     #.loword(al_nocart)
:       jsr     ui_alert
@ok:    jmp     atupdate
@not:   ldx     #.loword(al_notat)
        jmp     ui_alert

; (0.23) Run in Atari (a /Desktop entry's menu): the BASIC program in pth (prunq) as the
; Atari's boot disk, the Atari cold booted and shown (ulib atari_run); an alert if it fails
runat:  ldx     #.loword(pth)
        ldy     #^pth
        jsr     atari_run
        php
        pha
        jsr     tcatch
        pla
        plp
        stz     z:btn
        bcc     :+
        sta     z:err
        ldx     #.loword(al_norun)
        jsr     ui_alert
:       jmp     atupdate

; (0.23) prun = 1 if icon pui (a /Desktop file, or a shortcut's target) is a BASIC program
; (.bas .lst: atari_rkind); its path in pth
prunq:  stz     prun
        lda     z:pui
        jsr     kindof
        cmp     #K_FILE
        bne     @out
        lda     z:pui
        jsr     iconpath                ; pth
        lda     z:plnk
        beq     :+
        ldx     #.loword(pth)           ; a shortcut: its target
        jsr     ui_lnkread
        bcs     @out
        ldx     #.loword(ui_lktgt)
        ldy     #.loword(pth)
        jsr     ui_strcpy
:       ldx     #.loword(pth)
        ldy     #^pth
        jsr     atari_rkind
        cmp     #CK_BASRUN
        bne     @out
        inc     prun
@out:   rts

; ---------------------------------------------------------------- the folder disk (0.23)
; fdslot = the drive (0-3) that is the folder disk ($FFFF: none): STAT "/D1:" .. "/D4:"
; answers only for it (st: its numbers)
atfind: lda     #$FFFF
        sta     fdslot
        stz     z:c
:       jsr     fdstat
        bcc     :+
        inc     z:c
        lda     z:c
        cmp     #4
        bcc     :-
        rts
:       lda     z:c
        sta     fdslot
        rts

; STAT of drive z:c ("/D1:" ..) -> C clear: the folder disk (st: size, attributes)
fdstat: lda     z:c
        clc
        adc     #'1'
        sep     #$20
        .a8
        sta     fdq+2
        rep     #$20
        .a16
        ldx     #.loword(fdq)
        jmp     statx

; after atfill (the rows): the folder disk's row says "PATH (folder)" and has a Refresh
; button next to its Eject (the other rows as wide as before); the line under the rows
; gives its numbers, or "No folder disk"
atfold: jsr     atfind
        ldx     #$FFFF                  ; rows 0-3: their width (* 2: the folder's row)
        lda     fdslot
        cmp     #$FFFF
        beq     :+
        asl     a
        tax
:       stx     z:t
        ldx     #0
:       lda     at_nl,x
        tay
        lda     #ATW - 84 - 76
        cpx     z:t
        bne     :+
        lda     #ATW - 84 - 76 - 68
:       sta     a:CT_W,y
        inx
        inx
        cpx     #8
        bcc     :--
        lda     fdslot
        cmp     #$FFFF
        bne     @f
        stz     at_fslot                ; none: no Refresh
        ldx     #.loword(t_nofd)
        ldy     #.loword(fdnum)
        jsr     ui_strcpy
        lda     #UF_DIM
        sta     lb_fdn+CT_FLAGS
        jmp     @clr
@f:     ldy     #.loword(fdnum)         ; its numbers (st, from atfind)
        jsr     fdtext
        stz     lb_fdn+CT_FLAGS
        lda     fdslot                  ; Refresh on its row
        asl     a
        tax
        lda     fd_rowy,x
        sta     bt_fref+CT_Y
        lda     #.loword(bt_fref)
        sta     at_fslot
        lda     fdslot                  ; its row's text: at_nm + row * 48
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:t
        asl     a
        adc     z:t
        adc     #.loword(at_nm)
        sta     z:r
        lda     fdslot                  ; the folder (as recorded by classic_mount; (0.25)
        jsr     fdqry                   ; after a restart of Horizon: /atari.ini's)
        ldy     #0                      ; (32 characters at most)
:       lda     qbuf,y
        and     #$00FF
        beq     :+
        cpy     #32
        bcs     :+
        sep     #$20
        .a8
        sta     (r),y
        rep     #$20
        .a16
        iny
        bra     :-
:       tya                             ; " (folder)", or "(folder)" alone
        clc
        adc     z:r
        tay
        ldx     #.loword(t_fdin)
        lda     qbuf
        and     #$00FF
        bne     :+
        inx
:       jsr     ui_strcpy
        lda     #UF_DIM                 ; Refresh needs the path
        ldx     qbuf
        cpx     #0
        beq     :+
        lda     #0
:       sta     bt_fref+CT_FLAGS
        lda     fdslot                  ; its label and Eject not dimmed
        asl     a
        tax
        lda     at_nl,x
        tay
        lda     #0
        sta     a:CT_FLAGS,y
        lda     at_eb,x
        tay
        lda     #0
        sta     a:CT_FLAGS,y
@clr:   lda     fdslot                  ; the Refresh column cleared when it moved or went
        cmp     fdold
        beq     @out
        sta     fdold
        lda     z:atwin
        sta     z:ui_win
        lda     #ATW - 136
        sta     z:ui_x
        lda     #8
        sta     z:ui_y
        lda     #64
        sta     z:ui_w
        lda     #ATROW * 4
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jmp     ui_rect
@out:   rts

; Y = buffer: "12 files, 3 left out, 120 free sectors" (", saving..." while the Atari's
; changes wait to be saved into the folder) from st (STAT of the folder disk's drive)
fdtext: lda     st
        and     #$00FF
        pha
        jsr     putdec
        ldx     #.loword(t_fdf)
        pla
        cmp     #1
        bne     :+
        ldx     #.loword(t_fdf1)
:       jsr     memcpy0
        lda     st+1
        and     #$00FF
        jsr     putdec
        ldx     #.loword(t_fdlo)
        jsr     memcpy0
        lda     st+2
        jsr     putdec
        ldx     #.loword(t_fds)
        jsr     memcpy0
        lda     st+4
        and     #FD_SAVING
        beq     :+
        ldx     #.loword(t_fdsv)
        jsr     memcpy0
:       lda     #0
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        rts

; every second while the panel is open: the folder disk's numbers again (they change when
; the Atari writes; "saving..."); the line drawn when it changed
atfnum: lda     z:atwin
        cmp     #$FFFF
        beq     @out
        lda     fdslot
        cmp     #$FFFF
        beq     @out
        sta     z:c
        jsr     fdstat
        bcs     @out                    ; (gone: the look at the mounts every 5 s redraws)
        ldy     #.loword(fdtmp)
        jsr     fdtext
        lda     #.loword(fdtmp)
        sta     z:q
        lda     #.loword(fdnum)
        sta     z:r
        jsr     streq
        bcc     @out
        ldx     #.loword(fdtmp)
        ldy     #.loword(fdnum)
        jsr     ui_strcpy
        ldx     #.loword(lb_fdn)
        jmp     ui_draw
@out:   rts

; "Folder disk": a folder of the card as an Atari DOS disk on a drive (classic_mount
; CK_FOLDER). The folder (default /Atari, else the folder disk's) and the drive (D1:-D4:;
; default D2:, else the folder disk's; D1: cannot boot), Mount (the same folder and drive:
; a refresh; another drive: the old one ejected first, its changes saved)
fdlg:   jsr     atfind
        ldx     #.loword(t_fddef)
        lda     fdslot
        cmp     #$FFFF
        beq     :+
        jsr     fdqry
        ldx     #.loword(t_fddef)
        cmp     #0
        beq     :+
        ldx     #.loword(qbuf)
:       ldy     #.loword(fdpath)
        jsr     ui_strcpy
        sta     fd_fld+FD_LEN           ; all of it selected, the cursor at its end
        sta     fd_fld+FD_CUR
        stz     fd_fld+FD_ANC
        stz     fd_fld+FD_SCR
        lda     #UF_FOCUS
        sta     fd_fld+CT_FLAGS
        lda     fdslot
        cmp     #$FFFF
        bne     :+
        lda     #1                      ; D2:
:       sta     fd_list+LS_SEL
        stz     fd_list+LS_TOP
        stz     fd_list+CT_FLAGS
        ldx     #.loword(dg_fd)
        jsr     ui_dlgopen
        bcc     @run
        jmp     ui_beep
@run:   ldx     #.loword(dg_fd)
        jsr     ui_dlgrun
        cpx     #.loword(bt_fdok)
        bne     @close
        lda     fdpath
        and     #$00FF
        beq     @bad
        lda     fd_list+LS_SEL
        cmp     #4
        bcc     :+
@bad:   jsr     ui_beep
        bra     @run
:       sta     fdnew
        ldx     #.loword(dg_fd)
        jsr     ui_dlgclose
        stz     z:btn
        bra     fdmount
@close: ldx     #.loword(dg_fd)
        stz     z:btn
        jmp     ui_dlgclose

; Refresh: the folder disk's folder mounted again on its drive
fdref:  lda     fdslot
        cmp     #$FFFF
        beq     @out
        sta     fdnew
        jsr     fdqry
        beq     @out
        ldx     #.loword(qbuf)
        ldy     #.loword(fdpath)
        jsr     ui_strcpy
        bra     fdmount
@out:   rts

; fdpath on drive fdnew as the folder disk (a folder disk on another drive is ejected first,
; so the kernel's record of that drive goes too); an alert if it fails
fdmount:
        lda     fdslot
        cmp     #$FFFF
        beq     :+
        cmp     fdnew
        beq     :+
        xba
        ora     #CK_DISK
        sys     SYS_CEJECT
:       lda     fdnew
        xba
        ora     #CK_FOLDER
        ldx     #.loword(fdpath)
        ldy     #^fdpath
        sys     SYS_CMOUNT
        bcc     :+
        sta     z:err
        ldx     #.loword(al_nofd)
        jsr     ui_alert
:       jmp     atupdate

; (0.25) the folder of drive A (0-3) -> qbuf, A = its first character (0: not known, Z set):
; classic_query (the kernel's record of the mount), else (after a restart of Horizon the
; kernel has none) /atari.ini's "folder=" when its "folderdrive=" is that drive (the I/O
; processor keeps both there while the folder disk is mounted)
fdqry:  sta     in_drv
        ptr     qbuf
        sys     SYS_CQUERY
        bcs     :+
        cmp     #0
        jne     @ok
:       stz     qbuf
        stz     in_fd
        stz     in_fold
        stz     in_ll
        ptr     p_ini
        lda     #O_READ
        sys     SYS_OPEN
        jcs     @ok
        sta     in_h
@rd:    lda     in_h                    ; a piece of it (the lines put together in in_ln)
        sta     rwblk
        lda     #.loword(fbuf)
        sta     rwblk+1
        lda     #^fbuf
        sta     rwblk+3
        lda     #FBUFL
        sta     rwblk+4
        ptr     rwblk
        sys     SYS_READ
        bcs     @eof
        cmp     #0
        beq     @eof
        sta     in_n
        ldx     #0
@ch:    lda     fbuf,x
        and     #$00FF
        cmp     #10
        bne     :+
        phx
        jsr     inline
        plx
        bra     @nx
:       ldy     in_ll                   ; (a longer line: the rest left out)
        cpy     #126
        bcs     @nx
        sep     #$20
        .a8
        sta     in_ln,y
        rep     #$20
        .a16
        iny
        sty     in_ll
@nx:    inx
        cpx     in_n
        bcc     @ch
        bra     @rd
@eof:   jsr     inline                  ; (the last line, without its LF)
        lda     in_h
        sys     SYS_CLOSE
        lda     in_fd
        dec     a
        cmp     in_drv
        bne     @ok
        ldx     #.loword(in_fold)
        ldy     #.loword(qbuf)
        jsr     ui_strcpy
@ok:    lda     qbuf
        and     #$00FF
        rts

; one line of /atari.ini (in_ln, in_ll long; then empty): "folder" or "folderdrive", spaces,
; "=", spaces, the value (spaces and a CR at its end left out)
inline: ldy     in_ll
        stz     in_ll
:       cpy     #0                      ; (the end: CR, spaces, tabs left out)
        beq     :+
        lda     in_ln-1,y
        and     #$00FF
        cmp     #13
        beq     @cut
        cmp     #' '
        beq     @cut
        cmp     #9
        bne     :+
@cut:   dey
        bra     :-
:       lda     #0
        sep     #$20
        .a8
        sta     in_ln,y
        rep     #$20
        .a16
        ldx     #0
        jsr     inspc
        ldy     #0                      ; "folder"
:       lda     t_inkey,y
        and     #$00FF
        beq     :+
        sta     in_t
        lda     in_ln,x
        and     #$00FF
        cmp     in_t
        bne     @no
        inx
        iny
        bra     :-
:       stz     in_t                     ; "drive" after it?
        ldy     #0
:       lda     t_indrv,y
        and     #$00FF
        beq     :+
        sta     in_c
        lda     in_ln,x
        and     #$00FF
        cmp     in_c
        bne     @eq
        inx
        iny
        bra     :-
:       inc     in_t
@eq:    lda     in_t                     ; ("folderd..." that is not "folderdrive": no key)
        bne     :+
        cpy     #0
        bne     @no
:       jsr     inspc
        lda     in_ln,x
        and     #$00FF
        cmp     #'='
        bne     @no
        inx
        jsr     inspc
        lda     in_t
        bne     @drv
        txa                             ; folder=: the path
        clc
        adc     #.loword(in_ln)
        tax
        ldy     #.loword(in_fold)
        jmp     ui_strcpy
@drv:   lda     in_ln,x                 ; folderdrive=: 1-4
        and     #$00FF
        sec
        sbc     #'0'
        sta     in_fd
@no:    rts
; X past the spaces and tabs at in_ln + X
inspc:  lda     in_ln,x
        and     #$00FF
        cmp     #' '
        beq     :+
        cmp     #9
        bne     :++
:       inx
        bra     inspc
:       rts

; the drive list's rows (ui list callback: A = row -> X = its text)
fd_row: asl     a
        tax
        lda     fd_rows,x
        tax
        rts

; ---------------------------------------------------------------- printing (0.23)
; The timer, every second: prcheck (new print jobs), the notice's end, the folder disk's
; numbers; every 5 s (as before 0.23: at the timer's 5th, 10th, ... second, by the uptime,
; so a tick lost while a dialog was open does not move them) the status, /Desktop and what
; the Atari has loaded
tick:   jsr     svcheck                 ; (0.24) the screen saver
        sys     SYS_UPTIME              ; the timer's second this tick belongs to (first:
        sec                             ; the uptime before anything waits for the I/O
        sbc     tm0                     ; processor)
        sta     z:lo
        txa
        sbc     tm0+2
        sta     z:hi
        lda     #1000
        jsr     div32
        lda     z:lo
        sta     tsec
        jsr     prcheck
        lda     prtick
        beq     :+
        dec     prtick
        bne     :+
        jsr     clock                   ; the notice is over: the clock again
:       jsr     atfnum
        lda     tsec
        sta     z:lo
        cmp     tlast
        beq     @out
        ldx     #5
        jsr     divmod
        cpx     #0
        bne     @out
        lda     z:lo
        sta     tlast
        bra     five
@out:   rts
five:   jsr     clock                   ; the 5-s work
        jsr     rescan
        jsr     atcheck
        bcc     :+
        jmp     atchanged
:       rts

; (0.24, every second) the screen saver: when the seconds without input (kernel setting 6)
; reach its delay (setting 5, 0 = off), /SYSTEM/SAVER.PRG is started (detached), once until
; the next input. The kernel does not count while the classic Atari is shown, a program is in
; full-screen mode (the saver itself too), a mouse button is held or a menu is open. When the
; saver has ended, the status is drawn again (the free memory it took while it ran).
svcheck:
        lda     svtid                   ; the saver ended?
        beq     @idle
        stz     z:t
@s:     lda     z:t
        ptr     info
        sys     SYS_TINFO
        lda     info
        and     #$00FF
        cmp     svtid
        bne     :+
        lda     info+1
        and     #$00FF
        cmp     #4                      ; (a zombie)
        bne     @idle
:       inc     z:t
        lda     z:t
        cmp     #16
        bcc     @s
        stz     svtid
        jsr     clock
@idle:  lda     #6
        ldx     #$FFFF
        sys     SYS_SETTING
        sta     z:t
        lda     #5
        ldx     #$FFFF
        sys     SYS_SETTING
        cmp     #0
        beq     @clr
        cmp     z:t
        beq     :+
        bcs     @clr                    ; not yet
:       lda     svdone
        bne     @out
        inc     svdone
        stz     z:u_arg
        stz     z:u_arg+2
        ldx     #.loword(p_saver)
        ldy     #^p_saver
        lda     #1 | SP_DETACH
        jsr     spawn
        bcs     @out
        sta     svtid
        rts
@clr:   stz     svdone
@out:   rts

; after the classic Atari was shown (SYS_CLASSIC, SYS_CBOOT: the Desktop waited there, its
; timer's events queued): when one of the timer's 5-s seconds passed meanwhile, its work now
; (as the 5-s timer's queued event did before 0.23; the 1-s events that follow come late and
; would miss it)
tcatch: sys     SYS_UPTIME
        sec
        sbc     tm0
        sta     z:lo
        txa
        sbc     tm0+2
        sta     z:hi
        lda     #1000
        jsr     div32
        lda     z:lo
        ldx     #5
        jsr     divmod                  ; A = the 5-s periods passed
        sta     z:t
        asl     a
        asl     a
        clc
        adc     z:t
        beq     @out
        cmp     tlast
        beq     @out
        bcc     @out
        sta     tlast
        jmp     five
@out:   rts

; at start: the count of finished jobs and the newest name there now (no notice). prok = 0
; when the I/O processor does not know "/PRN:" (an older firmware): never asked again
prinit: stz     prok
        stz     prmax
        stz     prnew
        ldx     #.loword(p_prn)
        jsr     statx
        bcs     :+
        sta     prcnt
        inc     prok
        stz     prnoti
        jsr     prscan
:       rts

; one STAT of "/PRN:": when the count changed, /Printouts is read (prscan, with notices)
prcheck:
        lda     prok
        beq     @out
        ldx     #.loword(p_prn)
        jsr     statx
        bcs     @out
        cmp     prcnt
        beq     @out
        sta     prcnt
        lda     #1
        sta     prnoti
        jsr     prscan
@out:   rts

; read /Printouts (jobs: files whose names do not start with '.'): prmax = the greatest name
; (without ".txt"; names start with the date and time). With prnoti: each name greater than
; the greatest before is a new job (prnewjob); then the notice for the greatest new one: the
; status, the information chime
prscan: ldx     #.loword(prmax)
        ldy     #.loword(prold)
        jsr     ui_strcpy
        stz     prnw                    ; the greatest new one
        stz     prpc                    ; the PC not asked yet
        stz     prsnt
        stz     z:skip
@call:  lda     #.loword(p_prd)         ; block: path, buffer, length, skip
        sta     rblk
        lda     #^p_prd
        sta     rblk+2
        lda     #.loword(dbuf)
        sta     rblk+3
        lda     #^dbuf
        sta     rblk+5
        lda     #DBUFLEN
        sta     rblk+6
        lda     z:skip
        sta     rblk+8
        ptr     rblk
        sys     SYS_READDIR
        jcs     @end
        cmp     #0
        jeq     @end
        sta     z:cnt
        clc
        adc     z:skip
        sta     z:skip
        ldx     #0
@ent:   stx     z:dpos
        lda     dbuf+4,x                ; a folder, or ".name": not a job
        and     #$0010
        bne     @nx
        lda     dbuf+6,x
        and     #$00FF
        cmp     #'.'
        beq     @nx
        jsr     prname                  ; prcand
        ldx     #.loword(prmax)
        jsr     prcmp
        bcc     :+
        ldx     #.loword(prcand)
        ldy     #.loword(prmax)
        jsr     ui_strcpy
:       lda     prnoti
        beq     @nx
        ldx     #.loword(prold)
        jsr     prcmp
        bcc     @nx
        jsr     prnewjob
@nx:    ldx     z:dpos
        lda     dbuf+5,x
        and     #$00FF
        clc
        adc     #6
        adc     z:dpos
        tax
        dec     z:cnt
        bne     @ent
        jmp     @call
@end:   lda     prnw
        and     #$00FF
        beq     @out
        ldx     #.loword(prnw)          ; the notice
        ldy     #.loword(prnew)
        jsr     ui_strcpy
        lda     prsnt
        sta     prsent
        lda     #NOTICE
        sta     prtick
        lda     #CH_INFO
        jsr     ui_chime
        jmp     clock                   ; (it shows the notice)
@out:   rts

; prcand = the name of entry dpos of dbuf without ".txt" (PNAMEL - 1 characters at most)
prname: ldx     z:dpos
        lda     dbuf+5,x
        and     #$00FF
        sta     z:t
        ldy     #0
:       cpy     z:t
        bcs     :+
        cpy     #PNAMEL - 1
        bcs     :+
        lda     dbuf+6,x
        sep     #$20
        .a8
        sta     prcand,y
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       lda     #0
        sep     #$20
        .a8
        sta     prcand,y
        rep     #$20
        .a16
        cpy     #5
        bcc     @out
        lda     prcand-4,y              ; ".txt" (any case) at the end: left out
        and     #$DFFF
        cmp     #'.' | ('T' << 8)
        bne     @out
        lda     prcand-2,y
        and     #$DFDF
        cmp     #'X' | ('T' << 8)
        bne     @out
        lda     #0
        sep     #$20
        .a8
        sta     prcand-4,y
        rep     #$20
        .a16
@out:   rts

; C set if prcand is greater than the string X (byte by byte; a longer one with the same
; start is greater)
prcmp:  stx     z:t
        ldy     #0
:       lda     prcand,y
        and     #$00FF
        sta     z:t0
        lda     (t),y
        and     #$00FF
        cmp     z:t0
        bne     :+
        cmp     #0
        beq     @no
        iny
        bra     :-
:       bcc     @yes                    ; (X's byte below prcand's)
@no:    clc
        rts
@yes:   sec
        rts

; a new job (entry dpos of dbuf, its name in prcand): the greatest new one is the notice's;
; when the PC's gateway makes PDFs (asked once a scan), PRINTD started for it (detached)
prnewjob:
        ldx     #.loword(prnw)
        jsr     prcmp
        bcc     :+
        ldx     #.loword(prcand)
        ldy     #.loword(prnw)
        jsr     ui_strcpy
:       lda     prpc
        bne     :+
        lda     #1                      ; asked: 1 no, 2 it makes PDFs
        sta     prpc
        ldx     #.loword(p_pc)
        jsr     statx
        bcs     :+
        and     #PCS_PRINT
        beq     :+
        lda     #2
        sta     prpc
:       lda     prpc
        cmp     #2
        bne     @out
        ldx     #.loword(p_prdd)        ; its path: "/Printouts/" + the name
        ldy     #.loword(prarg)
        jsr     memcpy0
        ldx     z:dpos
        lda     dbuf+5,x
        and     #$00FF
        sta     z:t
:       lda     z:t
        beq     :+
        cpy     #.loword(prarg + 127)
        bcs     :+
        lda     dbuf+6,x
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        inx
        iny
        dec     z:t
        bra     :-
:       lda     #0
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        lda     #.loword(prarg)
        sta     z:u_arg
        lda     #^prarg
        sta     z:u_arg+2
        ldx     #.loword(p_printd)
        ldy     #^p_printd
        lda     #1 | SP_DETACH
        jsr     spawn
        bcs     @out
        lda     #1                      ; (the notice: "(to the PC)")
        sta     prsnt
@out:   rts

; the status during a notice: "Printed: NAME" (NAME: the job's name after its date and
; time), " (to the PC)" when PRINTD was started
notice: ldx     #.loword(t_prd)
        ldy     #.loword(stat)
        jsr     memcpy0
        ldx     #.loword(prnew)         ; "YYYY-MM-DD HH.MM.SS NAME": NAME
        lda     prnew+4
        and     #$00FF
        cmp     #'-'
        bne     :+
        lda     prnew+19
        and     #$00FF
        cmp     #' '
        bne     :+
        lda     prnew+20
        and     #$00FF
        beq     :+
        ldx     #.loword(prnew + 20)
:       lda     #31 - 9                 ; room: 31 characters in all
        sta     z:t
        lda     prsent
        beq     :+
        lda     #31 - 9 - 12
        sta     z:t
:       lda     a:0,x
        and     #$00FF
        beq     :+
        dec     z:t
        bmi     :+
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       lda     prsent
        beq     :+
        ldx     #.loword(t_topc)
        jsr     memcpy0
:       lda     #0
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        ptr     stat
        sys     SYS_WSTATUS
        rts

; ---------------------------------------------------------------- the date and time
; "Date and time": the date (year, month, day) and the time (hour, minute) in five fields,
; from the clock now; OK sets the clock (seconds 0) and saves it
datedlg:
        sys     SYS_TGET
        jsr     ui_clksplit
        ldx     #0
:       lda     ui_clk,x
        sta     dt_v,x
        inx
        inx
        cpx     #10
        bne     :-
        stz     z:dtf
        stz     z:dtn
        ldx     #.loword(dg_dt)
        jsr     ui_dlgopen
        bcc     :+
        jmp     ui_beep
:       lda     dg_dt+DG_WIN
        sta     z:ui_win
        stz     z:ui_font
        lda     #8                      ; the labels
        sta     z:ui_x
        lda     #DTY0 + 3
        sta     z:ui_y
        ldx     #.loword(t_date)
        lda     #C_BLACK | (C_BODY << 8)
        jsr     ui_text
        lda     #DTY1 + 3
        sta     z:ui_y
        ldx     #.loword(t_time)
        lda     #C_BLACK | (C_BODY << 8)
        jsr     ui_text
        lda     #DTY0 + 3               ; the separators
        sta     z:ui_y
        lda     #DTX0 + 44
        sta     z:ui_x
        ldx     #.loword(t_dash)
        lda     #C_BLACK | (C_BODY << 8)
        jsr     ui_text
        lda     #DTX0 + 84
        sta     z:ui_x
        ldx     #.loword(t_dash)
        lda     #C_BLACK | (C_BODY << 8)
        jsr     ui_text
        lda     #DTY1 + 3
        sta     z:ui_y
        lda     #DTX0 + 33
        sta     z:ui_x
        ldx     #.loword(t_colon)
        lda     #C_BLACK | (C_BODY << 8)
        jsr     ui_text
        jsr     dt_all
@run:   lda     dg_dt+DG_WIN
        jsr     ui_modal_get
        cmp     #WE_CLOSE
        jeq     @cancel
        cmp     #WE_KEY
        bne     @wheel
        lda     ui_ev+4
        and     #$0100
        beq     @run
        jsr     dt_key                  ; A = 0 used, 1 OK, 2 Cancel, 3 not mine
        cmp     #1
        beq     @ok
        cmp     #2
        jeq     @cancel
        cmp     #0
        beq     @run
        bra     @ctl
@wheel: cmp     #WE_WHEEL
        bne     @press
        lda     ui_ev+2
        jsr     dt_add
        bra     @run
@press: cmp     #WE_BUTTON              ; a press on a field: that one
        bne     @ctl
        lda     ui_ev+6
        and     #$0001
        beq     @ctl
        jsr     dt_hit
        bcs     @ctl
        jsr     dt_focus
        bra     @run
@ctl:   ldx     #.loword(dt_ctl)
        jsr     ui_event
        cmp     #UA_CLICK
        bne     @run
        cpx     #.loword(bt_dtok)
        bne     @cancel
@ok:    jsr     dt_fix                  ; the clock set and saved
        ldx     #0
:       lda     dt_v,x
        sta     ui_clk,x
        inx
        inx
        cpx     #10
        bne     :-
        stz     ui_clk + CK_SEC
        jsr     ui_clkcheck
        bcc     :+
        jsr     ui_beep
        jmp     @run
:       jsr     ui_clkjoin
        ldy     #CLK_SET
        sys     SYS_TSET
        jsr     ui_clksave
@cancel:
        ldx     #.loword(dg_dt)
        jsr     ui_dlgclose
        jmp     clock

DTX0    = 56                            ; the fields: year, month, day on the first row,
DTY0    = 32                            ; hour, minute on the second
DTY1    = 58

; a key down (ui_ev) -> A: 0 used, 1 OK (Enter), 2 Cancel (Esc), 3 not used
dt_key: lda     ui_ev+2
        cmp     #$28                    ; Enter (and the keypad's)
        beq     @ok
        cmp     #$58
        beq     @ok
        cmp     #$29
        bne     :+
        lda     #2
        rts
@ok:    lda     #1
        rts
:       cmp     #$2B                    ; Tab, Shift+Tab
        bne     :++
        lda     ui_ev+4
        and     #$0022
        beq     @next
@prev:  lda     z:dtf
        dec     a
        bpl     :+
        lda     #4
:       jsr     dt_focus
        lda     #0
        rts
:       cmp     #$4F                    ; Right, Left
        beq     @next
        cmp     #$50
        beq     @prev
        cmp     #$52                    ; Up, Down
        bne     :+
        lda     #1
        jsr     dt_add
        lda     #0
        rts
:       cmp     #$51
        bne     :+
        lda     #$FFFF
        jsr     dt_add
        lda     #0
        rts
:       cmp     #$27                    ; a digit (the row of digits, the keypad)
        beq     @dig0
        cmp     #$62
        beq     @dig0
        cmp     #$1E
        bcc     @none
        cmp     #$27
        bcs     :+
        sec
        sbc     #$1D
        bra     @d
:       cmp     #$59
        bcc     @none
        cmp     #$62
        bcs     @none
        sec
        sbc     #$58
        bra     @d
@dig0:  lda     #0
@d:     jsr     dt_digit
        lda     #0
        rts
@none:  lda     #3
        rts
@next:  lda     z:dtf
        inc     a
        cmp     #5
        bcc     :+
        lda     #0
:       jsr     dt_focus
        lda     #0
        rts

; digit A typed into the focused field: the first one starts it, then they add up; a full
; field goes on to the next
dt_digit:
        sta     z:t
        lda     z:dtf
        asl     a
        tax
        lda     z:dtn
        bne     :+
        lda     z:t
        bra     @st
:       lda     dt_v,x                  ; * 10 + digit
        asl     a
        sta     z:c
        asl     a
        asl     a
        clc
        adc     z:c
        adc     z:t
@st:    sta     dt_v,x
        inc     z:dtn
        lda     dt_wid,x
        cmp     z:dtn
        bne     :+
        lda     z:dtf                   ; full: the next field
        inc     a
        cmp     #5
        bcs     @last
        jmp     dt_focus
@last:  jsr     dt_fix
        stz     z:dtn
:       jmp     dt_all

; the focused field + A (+1, -1, or wheel steps), wrapping in its range
dt_add: sta     z:t
        jsr     dt_fix
        lda     z:dtf
        asl     a
        tax
        lda     dt_v,x
        clc
        adc     z:t
        sta     dt_v,x
        jsr     dt_rng                  ; X = field * 2 -> z:lo .. z:hi
        lda     dt_v,x
        bmi     @under
        cmp     z:lo
        bcc     @under
        lda     z:hi
        cmp     dt_v,x
        bcs     @ok
        lda     z:lo                    ; over: the lowest
        bra     :+
@under: lda     z:hi
:       sta     dt_v,x
@ok:    stz     z:dtn
        jsr     dt_fix
        jmp     dt_all

; field X (* 2) -> its range z:lo .. z:hi (the day: the month's days)
dt_rng: lda     dt_lo,x
        sta     z:lo
        lda     dt_hi,x
        sta     z:hi
        cpx     #4
        bne     :+
        phx
        lda     dt_v                    ; (ui_clkmdays reads ui_clk's year)
        sta     ui_clk + CK_YEAR
        lda     dt_v+2
        jsr     ui_clkmdays
        sta     z:hi
        plx
:       rts

; every field inside its range (the day too, after a change of month or year)
dt_fix: ldx     #0
:       jsr     dt_rng
        lda     dt_v,x
        cmp     z:lo
        bcs     :+
        lda     z:lo
:       cmp     z:hi
        bcc     :+
        lda     z:hi
:       sta     dt_v,x
        inx
        inx
        cpx     #10
        bne     :---
        rts

; field A gets the focus (the one it leaves made valid)
dt_focus:
        sta     z:dtf
        stz     z:dtn
        jsr     dt_fix
        ; fall through
; the five fields and the long date drawn
dt_all: lda     dg_dt+DG_WIN
        sta     z:ui_win
        stz     z:ui_font
        ldx     #0                      ; the long date of what the fields hold
:       lda     dt_v,x
        sta     ui_clk,x
        inx
        inx
        cpx     #10
        bne     :-
        stz     ui_clk + CK_SEC
        stz     lbuf
        jsr     ui_clkcheck             ; (while a year is typed: no line)
        bcs     :+
        jsr     ui_clkjoin
        ldy     #.loword(lbuf)
        jsr     ui_clklong
:       lda     #8
        sta     z:ui_x
        sta     z:ui_y
        lda     #DTW - 16
        sta     z:ui_w
        lda     #UI_LINE
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        ldx     #.loword(lbuf)
        lda     #C_BLACK | (C_BODY << 8)
        jsr     ui_text
        stz     z:c
@f:     lda     z:c                     ; a field: sunken, its number (C_SELECT if focused)
        asl     a
        tax
        lda     dt_fx,x
        sta     z:ui_x
        lda     dt_fy,x
        sta     z:ui_y
        lda     dt_fw,x
        sta     z:ui_w
        lda     #UI_FLDH
        sta     z:ui_h
        lda     #1
        jsr     ui_bevel
        inc     z:ui_x
        inc     z:ui_y
        dec     z:ui_w
        dec     z:ui_w
        dec     z:ui_h
        dec     z:ui_h
        lda     #WD_FILL | (C_WHITE << 8)
        ldx     z:c
        cpx     z:dtf
        bne     :+
        lda     #WD_FILL | (C_SELECT << 8)
:       jsr     ui_rect
        lda     z:c                     ; the number: 4 or 2 digits
        asl     a
        tax
        lda     #.loword(lbuf)
        sta     z:wp
        lda     dt_v,x
        ldy     dt_wid,x
        cpy     #4
        bne     :+
        ldx     #1000
        jsr     dt_dig
        ldx     #100
        jsr     dt_dig
:       ldx     #10
        jsr     dt_dig
        ldx     #1
        jsr     dt_dig
        lda     #0
        sta     (wp)
        ldx     #.loword(lbuf)
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF                  ; centred
        sec
        adc     z:ui_w
        lsr     a
        clc
        adc     z:ui_x
        sta     z:ui_x
        inc     z:ui_y
        inc     z:ui_y
        ldx     #.loword(lbuf)
        lda     #C_BLACK | ($FF << 8)
        ldy     z:c
        cpy     z:dtf
        bne     :+
        lda     #C_WHITE | ($FF << 8)
:       jsr     ui_text
        inc     z:c
        lda     z:c
        cmp     #5
        jcc     @f
        rts
; A: its digit of weight X to (wp)++ -> A = the rest
dt_dig: stx     z:d
        ldx     #0
:       cmp     z:d
        bcc     :+
        sbc     z:d
        inx
        bra     :-
:       pha
        txa
        clc
        adc     #'0'
        sep     #$20
        .a8
        sta     (wp)
        rep     #$20
        .a16
        inc     z:wp
        pla
        rts

; the field under the event's pointer -> A, C clear; C set: none
dt_hit: ldx     #0
:       lda     ui_ev+2
        sec
        sbc     dt_fx,x
        cmp     dt_fw,x
        bcs     :+
        lda     ui_ev+4
        sec
        sbc     dt_fy,x
        cmp     #UI_FLDH
        bcs     :+
        txa
        lsr     a
        clc
        rts
:       inx
        inx
        cpx     #10
        bne     :--
        sec
        rts

; ---------------------------------------------------------------- Force quit
; a dialog listing the running programs (not INIT, not the Desktop, not the window system);
; Force quit kills the one selected
forcequit:
        jsr     fqrows
        lda     z:nrow
        sta     fq_list+LS_COUNT
        lda     #$FFFF
        sta     fq_list+LS_SEL
        stz     fq_list+LS_TOP
        lda     #UF_FOCUS
        sta     fq_list+CT_FLAGS
        ldx     #.loword(dg_fq)
        jsr     ui_dlgopen
        bcc     @run
        jmp     ui_beep                 ; (no memory even for that)
@run:   lda     dg_fq+DG_WIN            ; (as ui_dlgrun, but Enter or a double click on
        jsr     ui_modal_get            ; the list also force quits)
        cmp     #WE_CLOSE
        beq     @close
        ldx     #.loword(fq_ctl)
        jsr     ui_event
        cmp     #UA_OPEN
        beq     @kill
        cmp     #UA_CLICK
        bne     @run
        cpx     #.loword(bt_fqk)
        bne     @close
@kill:  lda     fq_list+LS_SEL
        cmp     z:nrow
        bcc     :+
        jsr     ui_beep
        bra     @run
:       asl     a
        tax
        lda     rowid,x
        sys     SYS_KILL
@close: ldx     #.loword(dg_fq)
        jsr     ui_dlgclose
@out:   rts

; the rows: "NAME (task N)" of every live task but slot 0 (INIT), the Desktop and WS
fqrows: sys     SYS_GETPID
        sta     z:me
        stz     z:nrow
        stz     z:t
@s:     lda     z:t
        ptr     info
        sys     SYS_TINFO
        lda     info
        and     #$00FF
        beq     @n
        cmp     z:me
        beq     @n
        sta     z:c
        lda     z:t
        beq     @n
        lda     info+1
        and     #$00FF
        cmp     #4                      ; (a zombie)
        beq     @n
        lda     info+5
        cmp     #'W' | ('S' << 8)
        bne     :+
        lda     info+7
        cmp     #$2020
        beq     @n
:       lda     z:nrow
        cmp     #16
        bcs     @n
        asl     a
        tax
        lda     z:c
        sta     rowid,x
        txa
        asl     a
        asl     a
        asl     a
        asl     a
        adc     #.loword(rows)
        tay                             ; the row: (0.15) its name as the menu bar shows it
        phy                             ; (task_name), " (task N)"
        tyx
        ldy     #^rows
        lda     z:c
        ora     #$8000
        sys     SYS_TNAME
        lda     1,s
        tax
        jsr     ui_strlen
        clc
        adc     1,s
        tay
        pla
        sty     z:yy
        ldx     #.loword(t_task)        ; " (task "
        jsr     ui_strcpy
        clc
        adc     z:yy
        tay
        lda     z:c
        jsr     putdec
        lda     #')'                    ; ")", 0
        sta     a:0,y
        inc     z:nrow
@n:     inc     z:t
        lda     z:t
        cmp     #16
        jcc     @s
        rts

; the list's rows (LS_ROW): A = row -> X = its text
fq_row: asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        adc     #.loword(rows)
        tax
        rts

; A < 10000 as decimal at Y (program bank) -> Y after it (no terminator)
putdec: ldx     #0                      ; digits pushed, then written
:       phx
        ldx     #10
        jsr     divmod                  ; A = quotient, X = digit
        sta     z:dq
        txa
        plx
        pha
        inx
        lda     z:dq
        bne     :-
:       pla
        clc
        adc     #'0'
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
        dex
        bne     :-
        rts

; ---------------------------------------------------------------- restart, shut down
; A = SR_SHUTDOWN / SR_RESTART / SR_FULLRESTART: every other window is asked to close; when
; all its programs are gone: the restart, or the card synced and the "safe" screen.
sysdown:
        sta     z:down
        cmp     #SR_SHUTDOWN
        beq     :+
        cmp     #SR_RESTART
        beq     :+
        cmp     #SR_FULLRESTART
        beq     :+
        rts
:       sys     SYS_WSCLOSEALL          ; WE_CLOSE to every other window
        jsr     targets                 ; the programs with windows
        sys     SYS_UPTIME
        sta     z:t0
@wait:  lda     #100
        sys     SYS_SLEEP
        sys     SYS_UPTIME
        sec
        sbc     z:t0
        sta     z:el                    ; elapsed ms
        stz     z:left
        ldx     #0
@tg:    cpx     z:ntg
        bcs     @chk
        phx
        lda     tgid,x
        jsr     findid                  ; -> info, C clear while it lives
        plx
        bcs     @nx
        inc     z:left
        lda     info+13                 ; idle (its close request read), no dialog open:
        and     #TI_IDLE | TI_MODAL     ; it stays open: cancelled
        cmp     #TI_IDLE
        bne     @nx
        lda     z:el
        cmp     #1000
        bcc     @nx
        jsr     infoname                ; "NAME did not close. The shutdown (restart) was
        ldx     #.loword(t_stays)       ; cancelled."
        lda     z:down
        cmp     #SR_SHUTDOWN
        beq     :+
        ldx     #.loword(t_stays2)
:       jsr     msgname
        ldx     #.loword(al_cancel)
        jsr     ui_alert
        rts
@nx:    inx
        inx
        bra     @tg
@chk:   lda     z:left
        beq     @go
        lda     z:el                    ; 20 s: "NAME does not answer. Shut down anyway?"
        cmp     #20000
        bcc     @wait
        jsr     infoname
        ldx     #.loword(t_hung)
        jsr     msgname
        ldx     #.loword(al_hung)
        jsr     ui_alert
        cmp     #0
        beq     @go
        rts
@go:    jsr     ui_clksave              ; (0.14) the clock kept for the next start
        lda     z:down
        cmp     #SR_SHUTDOWN
        beq     @shut
        sec                             ; restart: 0 Horizon, 1 full
        sbc     #SR_RESTART
        sys     SYS_RESTART
        ldx     #.loword(al_norest)     ; (it came back: the firmware cannot)
        jsr     ui_alert
        rts
@shut:  lda     #1                      ; end the rest, close the files, flush the card
        sys     SYS_SYNC
        jmp     safe

; the tasks (not this one, not WS) that have windows -> tgid, ntg
targets:
        sys     SYS_GETPID
        sta     z:me
        stz     z:ntg
        stz     z:t
:       lda     z:t
        ptr     info
        sys     SYS_TINFO
        lda     info
        and     #$00FF
        beq     @n
        cmp     z:me
        beq     @n
        lda     info+13
        and     #TI_WINDOWS
        beq     @n
        ldx     z:ntg
        cpx     #32
        bcs     @n
        lda     info
        and     #$00FF
        sta     tgid,x
        inx
        inx
        stx     z:ntg
@n:     inc     z:t
        lda     z:t
        cmp     #16
        bcc     :-
        rts

; task id A: its task_info record -> info; C set: no such live task
findid: sta     z:c
        stz     z:t
:       lda     z:t
        ptr     info
        sys     SYS_TINFO
        lda     info
        and     #$00FF
        cmp     z:c
        bne     @n
        lda     info+1
        and     #$00FF
        cmp     #4
        beq     @n
        clc
        rts
@n:     inc     z:t
        lda     z:t
        cmp     #16
        bcc     :-
        sec
        rts

; the name in info -> lbuf (spaces cut, capitalised: "EDIT" -> "Edit")
infoname:
        ldx     #0
:       lda     info+5,x
        and     #$00FF
        cmp     #' '
        beq     :+
        cpx     #0
        beq     @up
        jsr     lower
@up:    sep     #$20
        .a8
        sta     lbuf,x
        rep     #$20
        .a16
        inx
        cpx     #8
        bcc     :-
:       sep     #$20
        .a8
        stz     lbuf,x
        rep     #$20
        .a16
        rts

; abuf = lbuf (a name) + the string X
msgname:
        phx
        ldx     #.loword(lbuf)
        ldy     #.loword(abuf)
        jsr     ui_strcpy
        clc
        adc     #.loword(abuf)
        tay
        plx
        jmp     ui_strcpy

; "It is now safe to switch off the Atari816": the whole screen below an empty menu bar,
; a Restart button (a full restart)
safe:   lda     z:back                  ; the bar: no menus, no status
        ptr     t_none2
        sys     SYS_WMENU
        ptr     t_none
        sys     SYS_WSTATUS
        lda     z:back
        ldx     #0
        sys     SYS_WTIMER
        ptr     sfblk
        sys     SYS_WOPEN
        bcs     @key
        sta     z:ui_win
        sep     #$20
        .a8
        sta     bt_sfr+CT_WIN
        rep     #$20
        .a16
        stz     z:ui_x
        stz     z:ui_y
        lda     #640
        sta     z:ui_w
        lda     #344
        sta     z:ui_h
        lda     #WD_FILL | (C_BLACK << 8)
        jsr     ui_rect
        stz     z:ui_font
        ldx     #.loword(t_safe)
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF
        sec
        adc     #640
        lsr     a
        sta     z:ui_x
        lda     #140
        sta     z:ui_y
        ldx     #.loword(t_safe)
        lda     #C_WHITE | (C_BLACK << 8)
        jsr     ui_text
        ldx     #.loword(sf_ctl)
        jsr     ui_drawall
@key:   lda     #0
        jsr     ui_getev
        bcs     @key
        ldx     #.loword(sf_ctl)
        jsr     ui_event
        cmp     #UA_CLICK
        bne     @key
        lda     #1                      ; a full restart
        sys     SYS_RESTART
        bra     @key


; ---------------------------------------------------------------- the status
; "NNNNK free  up H:MM" (the time since start) until the clock is set, then "NNNNK free
; HH:MM"
clock:  lda     prtick                  ; (0.23) a print notice instead
        beq     :+
        jmp     notice
:       ldy     #0
        sys     SYS_MINFO               ; free banks * 64 KB
        xba
        lsr     a
        lsr     a
        ldy     #.loword(stat)
        jsr     putdec
        tya
        sec
        sbc     #.loword(stat)
        tay
        ldx     #0
:       lda     t_free,x
        and     #$00FF
        beq     :+
        jsr     putb
        inx
        bra     :-
:       phy
        sys     SYS_TGET                ; the clock set: its time
        cpy     #CLK_SET
        bne     @up
        jsr     ui_clksplit
        ply
        lda     ui_clk + CK_HOUR
        jsr     dig2z
        lda     #':'
        jsr     putb
        lda     ui_clk + CK_MIN
        bra     @mm
@up:    sys     SYS_UPTIME              ; X:A milliseconds -> seconds
        sta     z:lo
        stx     z:hi
        lda     #1000
        jsr     div32
        lda     z:lo                    ; (< 65536 s: 18 hours; then it wraps)
        ldx     #3600
        jsr     divmod
        sta     z:t                     ; hours
        txa
        ldx     #60
        jsr     divmod                  ; A = minutes, X = seconds
        stx     z:sc
        sta     z:m
        ply
        lda     #'u'                    ; "up H:MM"
        jsr     putb
        lda     #'p'
        jsr     putb
        lda     #' '
        jsr     putb
        lda     z:t
        jsr     dig2
        lda     #':'
        jsr     putb
        lda     z:m
@mm:    jsr     dig2z
        lda     #0
        jsr     putb
        ptr     stat
        sys     SYS_WSTATUS
        rts

; A < 100: one or two digits / always two digits, at stat + Y
dig2:   cmp     #10
        bcc     :+
dig2z:  ldx     #10
        jsr     divmod
        clc
        adc     #'0'
        jsr     putb
        txa
:       clc
        adc     #'0'
putb:   sep     #$20
        .a8
        sta     stat,y
        rep     #$20
        .a16
        iny
        rts


; A / X -> A = quotient, X = remainder (16 bit; keeps Y)
divmod: stx     z:d
        sta     z:q
        lda     #0
        ldx     #16
:       asl     z:q
        rol     a
        cmp     z:d
        bcc     :+
        sbc     z:d
        inc     z:q
:       dex
        bne     :--
        tax
        lda     z:q
        rts

; hi:lo / A -> hi:lo (32 / 16 bit)
div32:  sta     z:d
        lda     #0
        ldx     #32
:       asl     z:lo
        rol     z:hi
        rol     a
        cmp     z:d
        bcc     :+
        sbc     z:d
        inc     z:lo
:       dex
        bne     :--
        rts

        .segment "RODATA"
bblk:   .word   0, 16, 640, 344
        .faraddr t_none
        .byte   WF_PLAIN | WF_BACK
sfblk:  .word   0, 16, 640, 344         ; the "safe" screen
        .faraddr t_none
        .byte   WF_PLAIN
atblk:  .word   170, 70, ATW, ATH       ; the Atari panel
        .faraddr t_atari
        .byte   0
t_none: .byte   0
t_none2: .byte  0, 0
t_name: .byte   "Atari816", 0
t_atari: .byte  "Atari", 0
t_sd:   .byte   "SD card", 0
t_files: .byte  "Files", 0
t_desktop: .byte "Desktop", 0
t_about: .byte  "About", 0
t_settings: .byte "Settings", 0
t_free: .byte   "K free  ", 0
t_task: .byte   " (task ", 0
t_stays: .byte  " did not close.", 10, "The shutdown was cancelled.", 0
t_stays2: .byte " did not close.", 10, "The restart was cancelled.", 0
t_safe: .byte   "It is now safe to switch off the Atari816.", 0
; the Horizon menu and the Programs title (the programs follow)
m_sys:  .byte   "Horizon", 0, "About Horizon", 0, "Settings...", 0, "-", 0, "Force quit...", 0
        .byte   "-", 0, "Switch to Atari", 9, "F12", 0, "-", 0, "Restart...", 0, "Shut down...", 0, 0
        .byte   "Programs", 0
m_sys_end:
; when /SYSTEM/PROGRAMS is missing
d_progs: .byte  "Edit=/BIN/EDIT.PRG", 10, "Write=/BIN/WRITE.PRG", 10, "Sheet=/BIN/SHEET.PRG", 10
        .byte   "Paint=/BIN/PAINT.PRG", 10, "BASIC=/BIN/BASIC.PRG", 10, "Calculator=/BIN/CALC.PRG", 10
        .byte   "Solitaire=/BIN/SOLITAIR.PRG", 10, "Terminal=/BIN/TERM.PRG", 10
        .byte   "Files=/BIN/WFILES.PRG", 10, "Printer=/BIN/PRINTER.PRG", 10, 0
p_progs: .byte  "/SYSTEM/PROGRAMS", 0
p_ini:  .byte   "/atari.ini", 0         ; (0.25) the folder disk after a restart: fdqry
t_inkey: .byte  "folder", 0
t_indrv: .byte  "drive", 0
p_icons: .byte  "/SYSTEM/ICONS", 0
p_layout: .byte "/SYSTEM/LAYOUT", 0
p_files: .byte  "/BIN/WFILES.PRG", 0
p_about: .byte  "/SYSTEM/ABOUT.PRG", 0
p_set:  .byte   "/BIN/SETTINGS.PRG", 0
p_desk: .byte   "/Desktop", 0
p_deskd: .byte  "/Desktop/", 0
k_sd:   .byte   ":SD", 0
k_pc:   .byte   ":PC", 0
p_pc:   .byte   "/PC:", 0
p_pcd:  .byte   "/PC:/", 0
p_pclc: .byte   "/pc:"
t_pc:   .byte   "PC", 0
k_atari: .byte  ":ATARI", 0
a_root: .byte   "/", 0
a_apply: .byte  "apply", 0
t_rtitle: .byte "Restart", 0
t_rtext: .byte  "Restart Horizon?", 10, "All programs will be closed.", 0
t_rbtn: .byte   "Restart", 0
t_stitle: .byte "Shut down", 0
t_stext: .byte  "Shut down the Atari816?", 10, "All programs will be closed.", 0
t_sbtn: .byte   "Shut down", 0
t_sbtn2: .byte  "Continue", 0
t_ctitle: .byte "Horizon", 0
t_hung: .byte   " is not responding.", 10, "End it and continue?", 0
t_norest: .byte "The machine cannot be restarted.", 10, "Update the Atari816 firmware.", 0
b_ok:   .byte   "OK", 0
b_cancel: .byte "Cancel", 0
t_fq:   .byte   "Force quit", 0
t_fql:  .byte   "Running programs:", 0
t_fqk:  .byte   "Force quit", 0
t_rst:  .byte   "Restart", 0
; (0.15) the pop-up menus' items
pu_sd:  .byte   "Open", 0, 0
pu_ent: .byte   "Open", 0, "-", 0, "Rename...", 0, "Delete", 9, "Del", 0, 0
pu_lnk: .byte   "Open", 0, "Show original", 0, "-", 0, "Rename...", 0, "Delete", 9, "Del", 0, 0
pu_entr: .byte  "Open", 0, "Run in Atari", 0, "-", 0, "Rename...", 0, "Delete", 9, "Del", 0, 0
pu_lnkr: .byte  "Open", 0, "Run in Atari", 0, "Show original", 0, "-", 0, "Rename...", 0
        .byte   "Delete", 9, "Del", 0, 0
pu_tab: .addr   pu_ent, pu_lnk, pu_entr, pu_lnkr    ; (0.23) by shortcut + 2 * BASIC program
pu_desk: .byte  "New folder...", 0, "Tidy up", 0, "-", 0, "Settings...", 0, 0
pu_at1:                                 ; (0.18: also the panel's buttons)
t_atd:  .byte   "Attach disk...", 0
t_atc:  .byte   "Attach cartridge...", 0
t_atr:  .byte   "Run program...", 0
        .byte   "-", 0, 0
pu_at2: .byte   MS_STATE, "Eject all", 0, "-", 0, "Restart Atari", 0, "Switch to Atari", 9, "F12", 0
        .byte   "-", 0
t_fdk:  .byte   "Folder disk...", 0     ; (0.23; also the panel's button)
        .byte   "Atari settings...", 0, "Open panel", 0, 0
at_ek:  .addr   t_ek1, t_ek2, t_ek3, t_ek4, t_ekx, t_ekc
t_ek1:  .byte   "Eject D1: ", 0
t_ek2:  .byte   "Eject D2: ", 0
t_ek3:  .byte   "Eject D3: ", 0
t_ek4:  .byte   "Eject D4: ", 0
t_ekx:  .byte   "Eject program: ", 0
t_ekc:  .byte   "Eject cartridge: ", 0
at_kinds: .byte CK_DISK, CK_CART, CK_XEX
at_dtit: .addr  t_attd, t_attc, t_runp
t_attd: .byte   "Attach disk", 0
t_attc: .byte   "Attach cartridge", 0
t_runp: .byte   "Run program", 0
a_atari: .byte  "atari", 0
t_newf: .byte   "New folder", 0
t_newt: .byte   "New folder", 0
t_newp: .byte   "Name of the new folder:", 0
t_newb: .byte   "Create", 0
t_rent: .byte   "Rename", 0
t_renp: .byte   "New name:", 0
t_lnk:  .byte   ".LNK", 0
t_tl:   .byte   "title=", 0
t_ar:   .byte   "args=", 0
t_nonew: .byte  "The folder could not be created.", 10, "The name may already be in use.", 0
t_noren: .byte  "The item could not be renamed.", 10, "The name may already be in use.", 0
ak_new: .addr   t_newt, t_newp, lbuf
        .word   NAMEL - 8
        .addr   t_newb
ak_ren: .addr   t_rent, t_renp, lbuf
        .word   NAMEL - 8
        .addr   t_rent
t_delt: .byte   "Delete", 0
t_delf: .byte   "Delete ", 0
t_delf2: .byte  " from the card?", 0
t_dell: .byte   "Remove the shortcut ", 0
t_dell2: .byte  "?", 10, "The original is not deleted.", 0
t_nodel: .byte  "The item could not be deleted.", 10, "A folder must be empty to be deleted.", 0
b_delete: .byte "Delete", 0
; the Atari panel
t_d1:   .byte   "D1:", 0
t_d2:   .byte   "D2:", 0
t_d3:   .byte   "D3:", 0
t_d4:   .byte   "D4:", 0
t_xex:  .byte   "Program", 0
t_cart: .byte   "Cartridge", 0
t_empty: .byte  "(empty)", 0
t_eject: .byte  "Eject", 0
t_eja:  .byte   "Eject all", 0
t_boot: .byte   "Restart Atari", 0
t_switch: .byte "Switch to Atari", 0
; (0.23) printing, Run in Atari, the folder disk
p_prn:  .byte   "/PRN:", 0
p_prd:  .byte   "/Printouts", 0
p_prdd: .byte   "/Printouts/", 0
p_printd: .byte "/SYSTEM/PRINTD.PRG", 0
p_saver: .byte  "/SYSTEM/SAVER.PRG", 0
p_printer: .byte "/BIN/PRINTER.PRG", 0
t_printer: .byte "Printer", 0
t_prd:  .byte   "Printed: ", 0
t_topc: .byte   " (to the PC)", 0
t_norun: .byte  "The program could not be run on the Atari.", 10
        .byte   "It must be an Atari BASIC program.", 0
t_fref: .byte   "Refresh", 0
t_fdt:  .byte   "Folder disk", 0
t_fdl1: .byte   "Folder on the card (made if missing):", 0
t_fdl2: .byte   "Drive:", 0
t_fdm:  .byte   "Mount", 0
t_fddef: .byte  "/Atari", 0
t_nofd: .byte   "No folder disk", 0
t_fdin: .byte   " (folder)", 0
t_fdf:  .byte   " files, ", 0
t_fdf1: .byte   " file, ", 0
t_fdlo: .byte   " left out, ", 0
t_fds:  .byte   " free sectors", 0
t_fdsv: .byte   ", saving...", 0
t_nofdx: .byte  "The folder could not be used as a disk.", 10
        .byte   "Check its name.", 0
t_fr1:  .byte   "D1: (the Atari cannot boot from it)", 0
fd_rows: .addr  t_fr1, t_d2, t_d3, t_d4
fd_rowy: .word  8 + ATROW * 0, 8 + ATROW * 1, 8 + ATROW * 2, 8 + ATROW * 3
t_mount: .byte  "The file could not be loaded.", 10, "Check that it is a valid Atari image.", 0
t_notat: .byte  "Only Atari disks (.ATR .XFD), programs", 10, "(.XEX .COM .EXE) and cartridges", 10
        .byte   "(.CAR .ROM .BIN) can be loaded.", 0
t_noboot: .byte "The Atari could not be restarted.", 0
t_nocart: .byte "Not enough free memory for the cartridge:", 10
        .byte   "close a program and try again.", 0
; the date and time
t_dtt:  .byte   "Date and time", 0
t_date: .byte   "Date", 0
t_time: .byte   "Time", 0
t_dash: .byte   "-", 0
t_colon: .byte  ":", 0
dt_fx:  .word   DTX0, DTX0 + 52, DTX0 + 92, DTX0, DTX0 + 40
dt_fy:  .word   DTY0, DTY0, DTY0, DTY1, DTY1
dt_fw:  .word   40, 28, 28, 28, 28
dt_wid: .word   4, 2, 2, 2, 2
dt_lo:  .word   2000, 1, 1, 0, 0
dt_hi:  .word   2135, 12, 31, 23, 59

        .segment "DATA"
; alerts
al_restart: .word 2
        .addr   t_rtitle, t_rtext, t_rbtn, b_cancel, 0
al_shut: .word  2
        .addr   t_stitle, t_stext, t_sbtn, b_cancel, 0
al_cancel: .word 1
        .addr   t_ctitle, abuf, b_ok, 0, 0
al_hung: .word  1
        .addr   t_ctitle, abuf, t_sbtn2, b_cancel, 0
al_norest: .word 3
        .addr   t_rtitle, t_norest, b_ok, 0, 0
al_del: .word   2
        .addr   t_delt, abuf, b_delete, b_cancel, 0
al_nodel: .word 3
        .addr   t_delt, t_nodel, b_ok, 0, 0
al_mount: .word 3
        .addr   t_atari, t_mount, b_ok, 0, 0
al_notat: .word 1
        .addr   t_atari, t_notat, b_ok, 0, 0
al_boot: .word  3
        .addr   t_atari, t_noboot, b_ok, 0, 0
al_nocart: .word 3
        .addr   t_atari, t_nocart, b_ok, 0, 0
al_nonew: .word 3
        .addr   t_newt, t_nonew, b_ok, 0, 0
al_noren: .word 3
        .addr   t_rent, t_noren, b_ok, 0, 0
al_norun: .word 3                       ; (0.23)
        .addr   t_atari, t_norun, b_ok, 0, 0
al_nofd: .word  3
        .addr   t_fdt, t_nofdx, b_ok, 0, 0
; (0.23) the "Folder disk" dialog: the folder, the drive, Cancel / Mount
dg_fd:  .addr   t_fdt
        .word   FDW, FDH
        .addr   fd_ctl
        .word   0
fd_ctl: .addr   fd_l1, fd_fld, fd_l2, fd_list, bt_fdc, bt_fdok, 0
fd_l1:  .byte   UT_LABEL, 0
        .word   8, 8, FDW - 16, UI_LINE, 0
        .addr   t_fdl1
fd_fld: .byte   UT_FIELD, 0
        .word   8, 24, FDW - 16, UI_FLDH, UF_FOCUS
        .word   fdpath, 128, 0, 0, 0, 0
fd_l2:  .byte   UT_LABEL, 0
        .word   8, 52, FDW - 16, UI_LINE, 0
        .addr   t_fdl2
fd_list: .byte  UT_LIST, 0
        .word   8, 68, FDW - 16, 4 * UI_ROWH + 4, 0
        .word   4, 1, 0, fd_row, 0, 0
        .res    SB_SIZE
bt_fdok: .byte  UT_BUTTON, 0
        .word   FDW - 80, FDH - 28, 72, UI_BTNH, UF_DEFAULT
        .addr   t_fdm
bt_fdc: .byte   UT_BUTTON, 0
        .word   FDW - 160, FDH - 28, 72, UI_BTNH, UF_CANCEL
        .addr   b_cancel
fdq:    .byte   "/D1:", 0               ; a drive's STAT (the digit set by fdstat)
; Force quit: a list and two buttons
dg_fq:  .addr   t_fq
        .word   FQW, FQH
        .addr   fq_ctl
        .word   0
fq_ctl: .addr   fq_lab, fq_list, bt_fqc, bt_fqk, 0
fq_lab: .byte   UT_LABEL, 0
        .word   8, 8, FQW - 16, UI_LINE, 0
        .addr   t_fql
fq_list: .byte  UT_LIST, 0
        .word   8, 24, FQW - 16, FQH - 64, UF_FOCUS
        .word   0, $FFFF, 0, fq_row, 0, 0
        .res    SB_SIZE
bt_fqk: .byte   UT_BUTTON, 0
        .word   FQW - 96, FQH - 28, 88, UI_BTNH, UF_DEFAULT
        .addr   t_fqk
bt_fqc: .byte   UT_BUTTON, 0
        .word   FQW - 184, FQH - 28, 80, UI_BTNH, UF_CANCEL
        .addr   b_cancel
; the "safe" screen's button
sf_ctl: .addr   bt_sfr, 0
bt_sfr: .byte   UT_BUTTON, 0
        .word   280, 180, 80, UI_BTNH, UF_DEFAULT
        .addr   t_rst
; the Atari panel: per row a kind label, the name, an Eject button; (0.18) two rows of
; three buttons below
at_k0:  .byte   UT_LABEL, 0
        .word   12, 8 + ATROW * 0 + 4, 64, UI_LINE, 0
        .addr   t_d1
at_n0:  .byte   UT_LABEL, 0
        .word   84, 8 + ATROW * 0 + 4, ATW - 84 - 76, UI_LINE, 0
        .addr   t_empty
at_b0:  .byte   UT_BUTTON, 0
        .word   ATW - 68, 8 + ATROW * 0, 60, UI_BTNH, 0
        .addr   t_eject
at_k1:  .byte   UT_LABEL, 0
        .word   12, 8 + ATROW * 1 + 4, 64, UI_LINE, 0
        .addr   t_d2
at_n1:  .byte   UT_LABEL, 0
        .word   84, 8 + ATROW * 1 + 4, ATW - 84 - 76, UI_LINE, 0
        .addr   t_empty
at_b1:  .byte   UT_BUTTON, 0
        .word   ATW - 68, 8 + ATROW * 1, 60, UI_BTNH, 0
        .addr   t_eject
at_k2:  .byte   UT_LABEL, 0
        .word   12, 8 + ATROW * 2 + 4, 64, UI_LINE, 0
        .addr   t_d3
at_n2:  .byte   UT_LABEL, 0
        .word   84, 8 + ATROW * 2 + 4, ATW - 84 - 76, UI_LINE, 0
        .addr   t_empty
at_b2:  .byte   UT_BUTTON, 0
        .word   ATW - 68, 8 + ATROW * 2, 60, UI_BTNH, 0
        .addr   t_eject
at_k3:  .byte   UT_LABEL, 0
        .word   12, 8 + ATROW * 3 + 4, 64, UI_LINE, 0
        .addr   t_d4
at_n3:  .byte   UT_LABEL, 0
        .word   84, 8 + ATROW * 3 + 4, ATW - 84 - 76, UI_LINE, 0
        .addr   t_empty
at_b3:  .byte   UT_BUTTON, 0
        .word   ATW - 68, 8 + ATROW * 3, 60, UI_BTNH, 0
        .addr   t_eject
at_k4:  .byte   UT_LABEL, 0
        .word   12, 8 + ATROW * 4 + 4, 64, UI_LINE, 0
        .addr   t_xex
at_n4:  .byte   UT_LABEL, 0
        .word   84, 8 + ATROW * 4 + 4, ATW - 84 - 76, UI_LINE, 0
        .addr   t_empty
at_b4:  .byte   UT_BUTTON, 0
        .word   ATW - 68, 8 + ATROW * 4, 60, UI_BTNH, 0
        .addr   t_eject
at_k5:  .byte   UT_LABEL, 0
        .word   12, 8 + ATROW * 5 + 4, 64, UI_LINE, 0
        .addr   t_cart
at_n5:  .byte   UT_LABEL, 0
        .word   84, 8 + ATROW * 5 + 4, ATW - 84 - 76, UI_LINE, 0
        .addr   t_empty
at_b5:  .byte   UT_BUTTON, 0
        .word   ATW - 68, 8 + ATROW * 5, 60, UI_BTNH, 0
        .addr   t_eject
bt_atd: .byte   UT_BUTTON, 0
        .word   8, ATB - 56, ATBW1, UI_BTNH, 0
        .addr   t_atd
bt_atc: .byte   UT_BUTTON, 0
        .word   16 + ATBW1, ATB - 56, ATBW2, UI_BTNH, 0
        .addr   t_atc
bt_atr: .byte   UT_BUTTON, 0
        .word   24 + ATBW1 + ATBW2, ATB - 56, ATBW3, UI_BTNH, 0
        .addr   t_atr
bt_eja: .byte   UT_BUTTON, 0
        .word   8, ATB - 28, ATBW1, UI_BTNH, 0
        .addr   t_eja
bt_boot: .byte  UT_BUTTON, 0
        .word   16 + ATBW1, ATB - 28, ATBW2, UI_BTNH, 0
        .addr   t_boot
bt_switch: .byte UT_BUTTON, 0
        .word   24 + ATBW1 + ATBW2, ATB - 28, ATBW3, UI_BTNH, UF_DEFAULT
        .addr   t_switch
; (0.23) the folder disk: a row of its own (Folder disk..., its numbers), a Refresh button on
; its drive's row (in the list only while there is one: at_fslot)
bt_fdk: .byte   UT_BUTTON, 0
        .word   8, ATB, ATBW1, UI_BTNH, 0
        .addr   t_fdk
lb_fdn: .byte   UT_LABEL, 0
        .word   16 + ATBW1, ATB + 4, ATW - 24 - ATBW1, UI_LINE, UF_DIM
        .addr   fdnum
bt_fref: .byte  UT_BUTTON, 0
        .word   ATW - 136, 8, 64, UI_BTNH, 0
        .addr   t_fref
at_ctl: .addr   at_k0, at_n0, at_b0, at_k1, at_n1, at_b1, at_k2, at_n2, at_b2
        .addr   at_k3, at_n3, at_b3, at_k4, at_n4, at_b4, at_k5, at_n5, at_b5
        .addr   bt_atd, bt_atc, bt_atr, bt_eja, bt_boot, bt_switch, bt_fdk, lb_fdn
at_fslot: .addr 0, 0
at_ab:  .addr   bt_atd, bt_atc, bt_atr  ; (0.18) Attach disk..., cartridge..., Run program...
at_nl:  .addr   at_n0, at_n1, at_n2, at_n3, at_n4, at_n5
at_eb:  .addr   at_b0, at_b1, at_b2, at_b3, at_b4, at_b5
; the date and time dialog: two buttons (the fields are drawn by the Desktop)
dg_dt:  .addr   t_dtt
        .word   DTW, DTH
        .addr   dt_ctl
        .word   0
dt_ctl: .addr   bt_dtc, bt_dtok, 0
bt_dtok: .byte  UT_BUTTON, 0
        .word   DTW - 72, DTH - 28, 64, UI_BTNH, UF_DEFAULT
        .addr   b_ok
bt_dtc: .byte   UT_BUTTON, 0
        .word   DTW - 144, DTH - 28, 64, UI_BTNH, UF_CANCEL
        .addr   b_cancel

        .segment "BSS"
DBUFLEN = 1024
FBUFL   = 1024
POOLL   = 1200
LAYL    = 3600
blk:    .res    16
stat:   .res    32
dbuf:   .res    DBUFLEN + 2
rblk:   .res    10
ic_kind: .res   NICON * 2               ; K_* above
ic_x:   .res    NICON * 2               ; its place in the backdrop
ic_y:   .res    NICON * 2
ic_cell: .res   NICON * 2               ; its cell: column * NROWS + row ($FFFF: none)
ic_ico: .res    NICON * 2               ; its picture (ICO_*)
ic_lnk: .res    NICON * 2               ; 1: a shortcut
names:  .res    NICON * NAMEL           ; a /Desktop entry's name (the fixed slots unused)
labs:   .res    NICON * LABL            ; the labels
lbuf:   .res    NAMEL + 4
abuf:   .res    NAMEL + 64
dropbuf: .res   130
pth:    .res    NAMEL + 140
st:     .res    10
sblk:   .res    8
stblk:  .res    8
rwblk:  .res    6
menu:   .res    MENUL                   ; the menus given to win_menu
mold:   .res    MENUL                   ; and what the kernel has
fbuf:   .res    FBUFL + 2               ; /SYSTEM/PROGRAMS
pool:   .res    POOLL                   ; the programs' titles and paths
ptitle: .res    NPROG * 2
ppath:  .res    NPROG * 2
info:   .res    16
rows:   .res    16 * 32                 ; Force quit: the rows' texts
rowid:  .res    16 * 2                  ; and their task ids
tgid:   .res    32                      ; shutting down: the tasks asked to close
lay:    .res    LAYL + 2                ; /SYSTEM/LAYOUT
qbuf:   .res    130                     ; classic_query
at_nm:  .res    6 * 48                  ; the Atari panel's names
dt_v:   .res    10                      ; the date dialog: year, month, day, hour, minute
pbuf:   .res    640                     ; (0.15) a pop-up menu's items (the Atari's)
pslot:  .res    12                      ; the slots of its Eject lines
rnblk:  .res    6                       ; rename: {u24 old, u24 new}
; (0.23) printing
prok:   .res    2                       ; the I/O processor knows "/PRN:"
prcnt:  .res    2                       ; the count of finished jobs last seen
prtick: .res    2                       ; a notice's seconds left (0: the clock)
tm0:    .res    4                       ; the uptime when the timer started (ms)
tlast:  .res    2                       ; the timer's second of the last 5-s work
tsec:   .res    2                       ; (tick: this one's)
prnoti: .res    2                       ; prscan: new jobs give a notice
prpc:   .res    2                       ; prscan: the PC asked (1 no PDFs, 2 PDFs)
prsnt:  .res    2                       ; prscan: PRINTD started
svdone: .res    2                       ; (0.24) the screen saver was started (until the next input)
svtid:  .res    2                       ; its task id while it may run (0: none)
prsent: .res    2                       ; the notice: "(to the PC)"
prmax:  .res    PNAMEL                  ; the greatest job name seen (without ".txt")
prold:  .res    PNAMEL                  ; (prscan: before it)
prnw:   .res    PNAMEL                  ; (prscan: the greatest new one)
prnew:  .res    PNAMEL                  ; the notice's job
prcand: .res    PNAMEL                  ; a name read
prarg:  .res    130                     ; PRINTD's argument: the job's path
prun:   .res    2                       ; (0.23) the entry's menu: a BASIC program
fdslot: .res    2                       ; (0.23) the folder disk's drive ($FFFF: none)
fdold:  .res    2                       ;   (its Refresh button drawn there)
fdnew:  .res    2                       ;   the drive to mount on
fdpath: .res    130                     ;   the folder
in_drv: .res    2                       ; (0.25) fdqry: the drive, /atari.ini's handle, the
in_h:   .res    2                       ; bytes of a piece, a line's length, folderdrive=,
in_n:   .res    2                       ; the line, folder=
in_ll:  .res    2
in_fd:  .res    2
in_t:   .res    2
in_c:   .res    2
in_ln:  .res    128
in_fold: .res   128
fdnum:  .res    64                      ;   its numbers' line
fdtmp:  .res    64

        .segment "ZEROPAGE"
back:   .res    2
lo:     .res    2
hi:     .res    2
t:      .res    2
t0:     .res    2
m:      .res    2
sc:     .res    2
d:      .res    2
q:      .res    2
r:      .res    2
p:      .res    2
c:      .res    2
i:      .res    2
nic:    .res    2
skip:   .res    2
cnt:    .res    2
dpos:   .res    2
sel:    .res    2
cx:     .res    2
cy:     .res    2
lw:     .res    2
btn:    .res    2
now:    .res    2
lastclk: .res   2
sum:    .res    2
hx:     .res    2
hy:     .res    2
px:     .res    2
py:     .res    2
drag:   .res    2
dragi:  .res    2
mp:     .res    2
pp:     .res    2
lp:     .res    2
tl:     .res    2
pl:     .res    2
nprog:  .res    2
nrow:   .res    2
me:     .res    2
yy:     .res    2
dq:     .res    2
down:   .res    2
el:     .res    2
left:   .res    2
ntg:    .res    2
mlen:   .res    2
icbank: .res    2
atwin:  .res    2
atany:  .res    2
pend:   .res    2
tidy:   .res    2
dirty:  .res    2
ex:     .res    2
bc:     .res    2
bd:     .res    2
cc:     .res    2
wp:     .res    2
pui:    .res    2
pkey:   .res    2
plnk:   .res    2
pw:     .res    2
pn:     .res    2
dl:     .res    2
err:    .res    2
dtf:    .res    2
dtn:    .res    2
nfix:   .res    2                       ; (0.20) the fixed icons: 2, or 3 with the PC
pcon:   .res    2                       ; the PC volume is there (its icon shown)
pcwas:  .res    2                       ; (at the last scan)
pccell: .res    2                       ; the PC icon's cell ($FFFF: none yet)
mvcp:   .res    2                       ; moveto: copy, not move

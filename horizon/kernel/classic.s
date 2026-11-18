; classic.s - Atari 8-bit software from Horizon: mount, eject and cold boot through the
; I/O processor's ops $18 CLASSIC_MOUNT, $19 CLASSIC_EJECT and $1A CLASSIC_BOOT (see
; a816_mailbox() in core/firmware/firmware.c). Results are I/O processor codes + $40,
; like the file syscalls: $44 no file, $C3 bad kind / slot / extension, $C4 not a valid
; image, $C5 the firmware menu is open, $C2 the firmware does not know the op.

        .a16
        .i16

MBOP_CMOUNT = $18
MBOP_CEJECT = $19
MBOP_CBOOT  = $1A

; ---- $61 classic_mount(X, Y = path, A = kind | slot << 8) -> A = kind mounted ----
; kind 0 = by extension (.ATR .XFD disk, .XEX .COM .EXE executable, .CAR .ROM .BIN
; cartridge), 1 disk, 2 executable, 3 cartridge; slot 0-3 = D1:-D4: (disks only)
sys_cmount:
        ldx     cur
        ldy     t_y,x
        lda     t_x,x
        tax
        jsr     copy_upath
        bcc     :+
        jmp     set_err
:       jsr     cart_room               ; (0.18) a cartridge: its banks first
        bcc     :+
        jmp     set_err
:       jsr     path_to_iobuf
        lda     #MBOP_CMOUNT
        jsr     msg_new
        jsr     msg_buf_iobuf
        ldx     cur
        lda     t_a,x
        a8
        sta     t_msg+7,y               ; FLAGS = kind
        a16
        xba
        and     #$00FF
        sta     t_msg+8,y               ; ARG0 = slot
        jsr     mb_call
        beq     :+
        jsr     io_err
        jmp     set_err
:       jsr     rsp_of                  ; remember what is mounted where
        lda     t_rsp+12,y
        pha
        cmp     #1
        bne     @nd
        ldx     cur
        lda     t_a,x
        xba
        and     #$0003
        pha
        jsr     cl_set                  ; disk: its slot
        pla
        bne     @done
        lda     #4                      ; D1: replaces the executable
        jsr     cl_clear
        bra     @done
@nd:    cmp     #2
        bne     @cart
        lda     #4
        jsr     cl_set
        lda     #0                      ; the executable replaces D1:
        jsr     cl_clear
        bra     @done
@cart:  lda     #5
        jsr     cl_set
@done:  pla
        jmp     set_ok

; record the current task's I/O buffer path as mounted item A (0-3 D1:-D4:, 4 executable,
; 5 cartridge); cl_clear empties item A
cl_set: jsr     cl_item
        jsr     iobuf_of
        tax
        lda     #64
        sta     kt6
:       lda     a:0,x
        sta     a:0,y
        inx
        inx
        iny
        iny
        dec     kt6
        bne     :-
        rts
cl_clear:
        jsr     cl_item
        lda     #0
        sta     a:0,y
        rts
; Y = offset of item A
cl_item:
        xba
        lsr     a                       ; * 128
        clc
        adc     #.loword(cl_names)
        tay
        rts

; ---- $64 classic_query(A = item 0-3 D1:-D4:, 4 executable, 5 cartridge, X, Y = 128-byte
; buffer) -> the path mounted there ("" = nothing), A = its length ----
sys_cquery:
        ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #128
        sta     kt2
        lda     #1
        sta     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       ldx     cur
        lda     t_a,x
        cmp     #6
        bcc     :+
        jmp     err_inval
:       jsr     cl_item
        tyx
        lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldy     #0
        a8
:       lda     a:0,x
        sta     [kp1],y
        beq     :+
        inx
        iny
        cpy     #127
        bne     :-
:       a16
        tya
        jmp     set_ok

; ---- $62 classic_eject(A = kind | slot << 8): kind 1 disk, 2 executable, 3 cartridge ----
sys_ceject:
        lda     #MBOP_CEJECT
        jsr     msg_new
        ldx     cur
        lda     t_a,x
        a8
        sta     t_msg+7,y
        a16
        xba
        and     #$00FF
        sta     t_msg+8,y
        jsr     mb_call
        beq     :+
        jsr     io_err
        jmp     set_err
:       ldx     cur                     ; forget what was ejected
        lda     t_a,x
        and     #$00FF
        cmp     #1
        bne     :+
        lda     t_a,x
        xba
        and     #$0003
        pha
        jsr     cl_clear
        pla
        bne     @ok
        lda     #4                      ; D1: also ejects the executable
        jsr     cl_clear
        bra     @ok
:       cmp     #2
        bne     :+
        lda     #4
        jsr     cl_clear
        bra     @ok
:       lda     #5
        jsr     cl_clear
        jsr     cart_free               ; (0.18) its banks back to the pool
@ok:    lda     #0
        jmp     set_ok

; (0.18) The I/O processor loads a cartridge into its SDRAM from $400000, which the 65C816
; sees as banks $70 and up: Horizon's memory. So before a cartridge is mounted its banks are
; taken out of the pool (CART_B0 .. + size in banks, at most CART_NB): they must be free (or
; already the attached cartridge's), else ENOMEM and nothing is mounted. Without this the
; firmware wrote the cartridge over a window's bitmap (a garbage band on the desktop) and the
; desktop then drew into the cartridge (a black screen when the Atari was shown).
; kpath = the absolute path, t_a = kind | slot << 8. C set: A = the error (kpath is copied
; again from the caller's pointer after the I/O processor's STAT).
cart_room:
        ldx     cur
        lda     t_a,x
        and     #$00FF
        cmp     #3
        beq     @cart
        cmp     #0
        beq     :+
@no:    clc
        rts
:       ldx     #0                      ; by extension: .CAR .ROM .BIN
:       lda     kpath,x
        and     #$00FF
        beq     :+
        inx
        bra     :-
:       cpx     #4
        bcc     @no
        lda     kpath-4,x
        and     #$00FF
        cmp     #'.'
        bne     @no
        lda     kpath-3,x               ; three letters, upper case
        and     #$DFDF
        sta     kt0
        lda     kpath-1,x
        and     #$00DF
        sta     kt1
        ldy     #0
:       lda     cart_ext,y
        cmp     kt0
        bne     :+
        lda     cart_ext+2,y
        and     #$00FF
        cmp     kt1
        beq     @cart
:       iny
        iny
        iny
        cpy     #9
        bcc     :--
        bra     @no
@cart:  jsr     path_to_iobuf           ; its size (STAT)
        lda     #MBOP_STAT
        jsr     msg_new
        jsr     msg_buf_iobuf
        jsr     mb_call
        beq     :+
        jsr     io_err
        sec
        rts
:       jsr     rsp_of                  ; banks: size / 64 KB, rounded up
        lda     t_rsp+14,y
        ldx     t_rsp+12,y
        beq     :+
        inc     a
:       cmp     #CART_NB + 1
        bcs     @full
        cmp     cart_nb                 ; (at least what the last one kept)
        bcs     :+
        lda     cart_nb
:       cmp     #0
        bne     :+
        inc     a                       ; (at least one)
:       sta     kt2
        ldx     #CART_B0                ; each free or the cartridge's already
        ldy     kt2
:       txa
        sec
        sbc     #CART_B0
        cmp     cart_nb
        bcc     :+
        lda     bank_st,x
        and     #$00FF
        bne     @full
:       inx
        dey
        bne     :--
        ldx     #CART_B0 + 0            ; take them
        ldy     kt2
:       lda     #BK_KERNEL
        phy
        jsr     bank_set
        ply
        inx
        dey
        bne     :-
        lda     kt2
        sta     cart_nb
        ldx     cur                     ; the path again (kpath is shared)
        ldy     t_y,x
        lda     t_x,x
        tax
        jmp     copy_upath
@full:  lda     #ENOMEM
        sec
        rts
cart_ext:
        .byte   "CAR", "ROM", "BIN"

; (0.19) a cartridge the I/O processor loaded by itself (boot=ash in /atari.ini, at power-on
; or a full restart): asked for once, by the first task's loader before anything allocates
; (CLASSIC_STATE, op $1E); its banks are taken as classic_mount takes them and classic_query
; reports its path. An older firmware answers $82: nothing then. The task's I/O buffer holds
; the program's path meanwhile: it is kept in the buffer's second half.
cart_boot:
        jsr     iobuf_of
        tax
        ldy     #64
:       lda     a:0,x
        sta     a:128,x
        inx
        inx
        dey
        bne     :-
        lda     #MBOP_CSTATE
        jsr     msg_new
        jsr     msg_buf_iobuf
        lda     #128
        sta     t_msg+2,y
        lda     #5
        sta     t_msg+8,y
        jsr     mb_call
        bne     @back
        jsr     rsp_of                  ; banks: size / 64 KB, rounded up (at most CART_NB)
        lda     t_rsp+14,y
        ldx     t_rsp+12,y
        beq     :+
        inc     a
:       cmp     #0
        beq     @back
        cmp     #CART_NB + 1
        bcc     :+
        lda     #CART_NB
:       sta     cart_nb
        tay
        ldx     #CART_B0
:       lda     #BK_KERNEL
        phy
        jsr     bank_set
        ply
        inx
        dey
        bne     :-
        lda     #5
        jsr     cl_set
@back:  jsr     iobuf_of                ; the path back
        tax
        ldy     #64
:       lda     a:128,x
        sta     a:0,x
        inx
        inx
        dey
        bne     :-
        rts

; (eject of the cartridge) its banks back to the pool
cart_free:
        ldx     #CART_B0
:       lda     cart_nb
        beq     :+
        dec     cart_nb
        lda     #BK_FREE
        jsr     bank_set
        inx
        bra     :-
:       rts

; ---- $63 classic_boot: keyboard holder only. Cold boots the classic machine with what is
; mounted and shows it as classic_show does (F12 comes back). The firmware needs the
; machine running and the keyboard routed to it before the boot (an executable is booted
; with OPTION held through the keyboard path). On failure everything is put back. ----
sys_cboot:
        lda     cur
        inc     a
        cmp     in_owner
        beq     :+
        lda     ws_on                   ; (the desktop: any program may)
        bne     :+
        jmp     err_inval
:       jsr     classic_run             ; 1. unfreeze
        a8
        lda     #1                      ; 2. keyboard to the Atari
        sta     f:KB_ROUTE
        a16
        lda     #MBOP_CBOOT             ; 3. boot, wait for the reply
        jsr     msg_new
        jsr     mb_call
        bne     @fail
        ldx     cur                     ; (0.18) A = CB_STAY: frozen again, not shown (a power
        lda     t_a,x                   ; cycle after a cartridge was attached or ejected;
        cmp     #CB_STAY                ; a value old callers never pass on purpose)
        beq     @back
        jmp     classic_show            ; 4. show it until F12
@back:  jsr     classic_freeze
        jsr     kb_back
        lda     #0
        jmp     set_ok
@fail:  pha
        jsr     classic_freeze
        jsr     kb_back                 ; (keys held during the attempt are swallowed)
        pla
        jsr     io_err
        jmp     set_err

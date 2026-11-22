; needs.inc - (0.29) what a program needs, checked by the program itself when it starts.
; Include it after horizon.inc and put HZ_NEEDS first at the program's start:
;
;       start:  HZ_NEEDS "DIGGER", 0, 29, 0, NEED_OPL2, 1024
;
; The arguments: the name used in the message (at most 15 characters), the Horizon version
; needed (major, minor; 0, 0 = any), the lowest hardware revision (0 = any), NEED_* flags,
; and the free memory in KB the program needs when it starts (0 = any). When everything is
; there, the macro's code returns with A, X, Y as they were (the start conditions: A = the
; length of the argument string, X = its offset) and the program goes on. When something is
; missing, it prints one line on the console, shows the same line in a small window when
; the window system runs (closed by a click or a key), and exits with code 1:
;
;       DIGGER needs Horizon 0.29 or later (this is 0.28).
;
; It works on every Horizon, also on those older than this file (that is the point: a
; program copied to an old card says what it needs instead of crashing). How it finds out:
;   - the version and the hardware revision: sys_info ($36, Horizon 0.29). Before 0.29 the
;     call is missing (ENOSYS); then task_path ($35) answering tells 0.28, opl_write's
;     probe ($6D) 0.27; anything older counts as "0.26 or older". The hardware revision is
;     then unknown: a revision, NEED_SPRITES and NEED_BLITTER are not checked there.
;   - Lau: sample_stat ($6A) answering (ENODEV or ENOSYS: none); the OPL2: opl_write's
;     probe ($FFFE: it writes nothing, never takes the chip).
;   - the memory: mem_info ($12), free banks x 64 KB.
; NEED_JOY is not checked (a joystick cannot be detected): installers show it.
;
; The block at the start of the code is also read by tools (sdk/tools/hzapp.py check):
;   "HZNEEDS", 1 (8 bytes), u8 minor, u8 major, u8 revision, u8 flags, u16 KB, the name
;   (zero-terminated). See sdk/docs/apps.md.
; Cost: 650 to 720 bytes of code (the messages included), depending on what is asked; nothing in zero page; at the start
; 150 bytes of the hardware stack for a moment. A program that has no HZ_NEEDS pays nothing.

NEED_LAU     = $01      ; Lau, the sample player (REV $0A and later)
NEED_OPL2    = $02      ; the OPL2 FM synthesizer (REV $0C)
NEED_SPRITES = $04      ; Marga's sprites and scrolling (REV $0B)
NEED_BLITTER = $08      ; the blitter, Ali (REV $08)
NEED_JOY     = $10      ; a joystick (noted only)

.macro  HZ_NEEDS nd_name, nd_vmaj, nd_vmin, nd_rev, nd_flags, nd_kb
        ; (its labels are local to each use; the frame, on the hardware stack, is the
        ; direct page meanwhile)
        .local  F_HAVE, F_OLD, F_REV, F_P, F_L, F_T, F_W, F_WB, F_DB, F_EV, F_MSG, FRAME, blk, nm, s_nd, s_hz, s_ol, s_old, s_rv, s_bd, s_lau, s_opl, s_spr, s_bl, s_kb, s_fr, s_end, s_dot, s_cl, chk, what, fail, out, draw, head, put, pchr, pver, pdec, phex, done
        F_HAVE  = 0             ; the Horizon version (major << 8 | minor)
        F_OLD   = 2             ; 1: older than F_HAVE ("0.26 or older")
        F_REV   = 4             ; the hardware revision, $FFFF unknown
        F_P     = 6             ; a string's address (code bank)
        F_L     = 8             ; the message's length so far
        F_T     = 10            ; scratch
        F_W     = 12            ; the window
        F_WB    = 14            ; win_open's block (13 bytes)
        F_DB    = 28            ; win_draw's block (17 bytes)
        F_EV    = 46            ; win_event's buffer (8 bytes)
        F_MSG   = 54            ; the message (110 characters at most)
        FRAME   = F_MSG + 112
        pha
        phx
        phy
        phd
        jsr     chk
        pld
        ply
        plx
        pla
        jmp     done
blk:    .byte   "HZNEEDS", 1, nd_vmin, nd_vmaj, nd_rev, nd_flags
        .word   nd_kb
nm:     .byte   nd_name, 0
        .assert .strlen(nd_name) <= 15, error, "HZ_NEEDS: the name is at most 15 characters"
s_nd:   .byte   " needs ", 0
.if nd_vmaj | nd_vmin
s_hz:   .byte   "Horizon ", 0
s_ol:   .byte   " or later (this is ", 0
s_old:  .byte   " or older", 0
.endif
.if nd_rev
s_rv:   .byte   "hardware revision $", 0
s_bd:   .byte   " or later (this board is $", 0
.endif
.if nd_flags & NEED_LAU
s_lau:  .byte   "Lau, the sample player (hardware revision $0A or later)", 0
.endif
.if nd_flags & NEED_OPL2
s_opl:  .byte   "the OPL2 sound chip (hardware revision $0C)", 0
.endif
.if nd_flags & NEED_SPRITES
s_spr:  .byte   "hardware sprites (hardware revision $0B or later)", 0
.endif
.if nd_flags & NEED_BLITTER
s_bl:   .byte   "the blitter (hardware revision $08 or later)", 0
.endif
.if nd_kb
s_kb:   .byte   " KB of free memory (", 0
s_fr:   .byte   " KB free", 0
.endif
s_end:  .byte   ").", 0
s_dot:  .byte   ".", 0
s_cl:   .byte   "Click or press a key to close this.", 0

chk:    tsc                     ; the frame below the stack; D = its start
        sec
        sbc     #FRAME
        tcs
        inc     a
        tcd
        lda     #$FFFF
        sta     z:F_REV
        stz     z:F_OLD
        cop     $36             ; sys_info (0.29): A = version, X = revision
        bcs     :+
        sta     z:F_HAVE
        stx     z:F_REV
        bra     @ver
:       lda     #0              ; before 0.29: task_path ($35, 0.28) with no room: EINVAL
        cop     $35
        cmp     #7              ; (ENOSYS: older)
        beq     :+
        lda     #$001C
        bra     @hv
:       lda     #$FFFE          ; opl_write's probe ($6D, 0.27)
        cop     $6D
        bcc     @is27
        cmp     #7
        bne     @is27
        inc     z:F_OLD
        lda     #$001A
        bra     @hv
@is27:  lda     #$001B
@hv:    sta     z:F_HAVE
@ver:
.if nd_vmaj | nd_vmin
        lda     z:F_HAVE
        cmp     #(nd_vmaj << 8) | nd_vmin
        bcs     :+
        jsr     head
        lda     #.loword(s_hz)
        jsr     put
        lda     #(nd_vmaj << 8) | nd_vmin
        jsr     pver
        lda     #.loword(s_ol)
        jsr     put
        lda     z:F_HAVE
        jsr     pver
        lda     z:F_OLD
        beq     @ve
        lda     #.loword(s_old)
        jsr     put
@ve:    jmp     fail
:
.endif
.if nd_rev
        lda     z:F_REV
        cmp     #$FFFF
        beq     :+
        cmp     #nd_rev
        bcs     :+
        jsr     head
        lda     #.loword(s_rv)
        jsr     put
        lda     #nd_rev
        jsr     phex
        lda     #.loword(s_bd)
        jsr     put
        lda     z:F_REV
        jsr     phex
        jmp     fail
:
.endif
.if nd_flags & NEED_LAU
        cop     $6A             ; sample_stat: ENODEV / ENOSYS without Lau
        bcc     :+
        lda     #.loword(s_lau)
        jmp     what
:
.endif
.if nd_flags & NEED_OPL2
        lda     #$FFFE          ; opl_write's probe
        cop     $6D
        bcc     :+
        lda     #.loword(s_opl)
        jmp     what
:
.endif
.if nd_flags & NEED_SPRITES
        lda     z:F_REV
        cmp     #$000B
        bcs     :+
        lda     #.loword(s_spr)
        jmp     what
:
.endif
.if nd_flags & NEED_BLITTER
        lda     z:F_REV
        cmp     #$0008
        bcs     :+
        lda     #.loword(s_bl)
        jmp     what
:
.endif
.if nd_kb
        cop     $12             ; mem_info: A = free banks
        xba                     ; x 64 KB = x 256 / 4
        and     #$FF00
        lsr     a
        lsr     a
        sta     z:F_EV          ; (pdec uses F_T)
        cmp     #nd_kb
        bcs     :+
        jsr     head
        lda     #nd_kb
        jsr     pdec
        lda     #.loword(s_kb)
        jsr     put
        lda     z:F_EV
        jsr     pdec
        lda     #.loword(s_fr)
        jsr     put
        jmp     fail
:
.endif
        tsc                     ; all there: the frame given back
        clc
        adc     #FRAME
        tcs
        rts

; "NAME needs " + the string A + "."
what:   pha
        jsr     head
        pla
        jsr     put
        lda     #.loword(s_dot)
        jsr     put
        bra     out
; the message so far ends with ")."
fail:   lda     #.loword(s_end)
        jsr     put
out:    tdc                     ; on the console
        clc
        adc     #F_MSG
        tax
        ldy     #0
        cop     $06             ; puts
        lda     #10
        cop     $05             ; putc
        tdc                     ; in a window, when the window system runs
        clc
        adc     #F_MSG
        tax
        ldy     #0
        lda     #0
        cop     $76             ; win_twidth (UI font)
        bcc     :+
        jmp     @end
:
        cmp     #180
        bcs     :+
        lda     #180
:       clc
        adc     #24
        sta     z:F_WB+4        ; {x, y, width, height, u24 title, u8 flags}
        eor     #$FFFF
        sec
        adc     #640            ; centred
        lsr     a
        sta     z:F_WB
        lda     #150
        sta     z:F_WB+2
        lda     #44
        sta     z:F_WB+6
        lda     #.loword(nm)
        sta     z:F_WB+8
        phk
        sep     #$20
        .a8
        pla
        sta     z:F_WB+10
        lda     #32             ; WF_MODAL
        sta     z:F_WB+11
        rep     #$20
        .a16
        tdc
        clc
        adc     #F_WB
        tax
        ldy     #0
        cop     $72             ; win_open (EINVAL: no window system)
        bcc     :+
        jmp     @end
:
        sta     z:F_W
        lda     #4              ; text (WD_TEXT): ink 0 (black), paper $FF (none), font 0
        sta     z:F_DB
        lda     #$00FF
        sta     z:F_DB+2
        lda     #12
        sta     z:F_DB+4
        lda     #8
        sta     z:F_DB+6
        lda     #600
        sta     z:F_DB+8
        lda     #12
        sta     z:F_DB+10
        tdc
        clc
        adc     #F_MSG
        sta     z:F_DB+12
        stz     z:F_DB+14       ; (bank 0: the window)
        jsr     draw
        lda     #24
        sta     z:F_DB+6
        lda     #.loword(s_cl)
        sta     z:F_DB+12
        phk
        sep     #$20
        .a8
        pla
        sta     z:F_DB+14
        rep     #$20
        .a16
        jsr     draw
@wait:  tdc                     ; a key down, a press or the close box
        clc
        adc     #F_EV
        tax
        ldy     #0
        lda     #0
        cop     $75             ; win_event
        bcs     @end
        lda     z:F_EV
        and     #$00FF
        cmp     #3
        beq     @end
        cmp     #1
        bne     :+
        lda     z:F_EV+4
        and     #$FF00
        bne     @end
:       cmp     #2
        bne     @wait
        lda     z:F_EV+6
        and     #$0007
        beq     @wait
@end:   lda     #1
        cop     $00             ; exit 1

draw:   tdc
        clc
        adc     #F_DB
        tax
        ldy     #0
        lda     z:F_W
        cop     $74             ; win_draw
        rts

; the message starts: "NAME needs "
head:   stz     z:F_L
        lda     #.loword(nm)
        jsr     put
        lda     #.loword(s_nd)
; the string at A (code bank) appended to the message
put:    sta     z:F_P
        ldy     #0
        ldx     z:F_L
:       lda     (F_P),y
        and     #$00FF
        sta     z:F_MSG,x
        beq     :+
        iny
        cpx     #108
        bcs     :+
        inx
        bra     :-
:       stx     z:F_L
        rts
; a character A appended
pchr:   ldx     z:F_L
        and     #$00FF
        sta     z:F_MSG,x
        cpx     #108
        bcs     :+
        inc     z:F_L
:       rts
; A = major << 8 | minor appended: "0.29"
pver:   pha
        xba
        and     #$00FF
        jsr     pdec
        lda     #'.'
        jsr     pchr
        pla
        and     #$00FF
; A appended in decimal
pdec:   ldy     #0              ; the digits pushed, lowest first
:       ldx     #16             ; A / 10: the quotient in F_T, the remainder in A
        sta     z:F_T
        lda     #0
@bit:   asl     z:F_T
        rol     a
        cmp     #10
        bcc     @nb
        sbc     #10
        inc     z:F_T
@nb:    dex
        bne     @bit
        pha
        iny
        lda     z:F_T
        bne     :-
:       pla
        clc
        adc     #'0'
        phy
        jsr     pchr
        ply
        dey
        bne     :-
        stz     z:F_T
        rts
; A appended as two hex digits
phex:   pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @dig
        pla
@dig:   and     #$000F
        cmp     #10
        bcc     :+
        adc     #'A' - '0' - 10 - 1
:       adc     #'0'
        jmp     pchr
done:
.endmacro

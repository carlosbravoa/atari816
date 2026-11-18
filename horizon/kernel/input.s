; input.s - keyboard. While a task holds the keyboard, KB_ROUTE = 0 and the I/O processor
; sends $E0 KEY events; they go into a 128-entry queue (usage, modifiers | down << 8).
; F12 is the system key: its own KEY events are dropped and its NMI is queued instead as
; usage $FF, down (nmi_poll). The owner reads the queue, blocking while it is empty.
;
; Lending: the owner may lend the keyboard to another task (input_lend), typically a
; foreground child. The queue is kept (typeahead survives) and KB_ROUTE stays 0. When the
; borrower releases it or exits, the keyboard goes back to the lender (t_lender).
; Break key: ctrl-C (usage $06 with a ctrl modifier) arriving while the keyboard is lent
; with the break flag (input_lend X bit 0) is not queued: the kernel kills the borrower
; instead, exactly like kill(). (INIT lends to the shell without it, the shell lends to
; its foreground jobs with it.)

        .a16
        .i16

input_init:
        stz     in_owner
        stz     kq_head
        stz     kq_count
        ldx     #0
        lda     #NONE
:       sta     t_lender,x
        inx
        inx
        cpx     #NSLOT*2
        bne     :-
        a8
        lda     #1
        sta     f:KB_ROUTE
        a16
        rts

; queue an event: A = usage, X = modifiers | down << 8 (dropped when the queue is full).
; Called from interrupt service: may wake or kill, never switches.
key_put:
        cmp     #$45                    ; F12: reported through the NMI as $FF
        bne     :+
        rts
:       ldy     sw_on                   ; just back from the classic machine?
        beq     :+
        jmp     swallow
:       cpx     #$0100                  ; key repeat: a key goes down (not a modifier, not
        bcc     @kup                    ; the system key) / the repeating key goes up
        cmp     #$E0
        bcs     key_put2
        sta     rep_u
        stx     rep_m
        ldy     rep_delay
        sty     rep_n
        bra     key_put2
@kup:   cmp     rep_u
        bne     key_put2
        stz     rep_u
; (the repeat comes in here)
key_put2:
        ldy     ws_on                   ; the window system: to the top window
        beq     :+
        jmp     ws_key
:       cmp     #$06                    ; ctrl-C on a lent keyboard: break
        bne     @queue
        cpx     #$0100
        bcc     @queue
        pha
        txa
        and     #$0011
        beq     @nobrk
        lda     in_owner
        beq     @nobrk
        dec     a
        tay
        lda     t_lender,y
        cmp     #NONE
        beq     @nobrk
        lda     t_lbrk,y
        beq     @nobrk
        pla
        tyx
        jmp     kill_slot
@nobrk: pla
@queue: ldy     #0
        ; fall through
; queue usage A, second word X, third word Y (dropped when full); wake the holder
kq_push:
        pha
        phy
        lda     kq_count
        cmp     #KQLEN
        bcc     :+
        ply
        pla
        rts
:       clc
        adc     kq_head
        and     #KQLEN - 1
        asl     a
        tay
        pla
        sta     kq_y,y
        pla
        sta     kq_usage,y
        txa
        sta     kq_mods,y
        inc     kq_count
        lda     in_owner
        beq     :+
        dec     a
        tax
        lda     t_state,x
        cmp     #TS_BLOCKED
        bne     :+
        lda     t_wreason,x
        cmp     #W_INPUT
        bne     :+
        jsr     k_wake
:       rts

; ---- after the classic machine: swallow key events until every key that is reported as
; down has been released again (keys still held when KB_ROUTE went back to 0 come back
; as new presses), at least 30 ms, at most 300 ms. A = usage, X = mods | down << 8.
swallow:
        sta     kt6
        cpx     #$0100
        bcc     @up
        ldy     #0                      ; down: remember it (8 slots)
:       lda     sw_keys,y
        cmp     kt6
        beq     @chk
        iny
        iny
        cpy     #16
        bne     :-
        ldy     #0
:       lda     sw_keys,y
        beq     @put
        iny
        iny
        cpy     #16
        bne     :-
        bra     @chk
@put:   lda     kt6
        sta     sw_keys,y
        bra     @chk
@up:    ldy     #0                      ; up: forget it
:       lda     sw_keys,y
        cmp     kt6
        bne     :+
        lda     #0
        sta     sw_keys,y
:       iny
        iny
        cpy     #16
        bne     :--
@chk:   ; fall through
; end the swallowing when it is due (also called by the tick)
sw_check:
        lda     sw_on
        beq     @out
        lda     ticks
        sec
        sbc     sw_t0
        cmp     #30                     ; 300 ms: stop anyway
        bcs     @end
        cmp     #3                      ; 30 ms and nothing held any more
        bcc     @out
        ldy     #0
:       lda     sw_keys,y
        bne     @out
        iny
        iny
        cpy     #16
        bne     :-
@end:   stz     sw_on
@out:   rts

; ---- $60 classic_show: the keyboard holder hands screen and keyboard to the classic
; machine until the system key (F12) is pressed ----
sys_classic:
        lda     cur
        inc     a
        cmp     in_owner
        beq     classic_show
        lda     ws_on                   ; (the desktop: any program may)
        bne     classic_show
        jmp     err_inval
; let the classic machine run and show it until F12 (classic_boot ends here too)
classic_show:
        lda     #1
        sta     cls_on
        stz     cls_done
        jsr     classic_run
        jsl     k2_classic              ; (0.18) out of a full screen first
        lda     #0                      ; the desktop and pointer off, keyboard to the Atari
        jsr     nv_ctrl
        a8
        lda     #1
        sta     f:KB_ROUTE
        a16
@wait:  lda     cls_done
        bne     @back
        ldx     cur
        lda     t_killed,x
        bne     @back
        lda     #W_CLASSIC
        ldy     #0
        jsr     k_block
        bra     @wait
@back:  stz     cls_on
        jsr     classic_freeze
        lda     scr_ctrl                ; the desktop (and the pointer, if shown) back
        jsr     nv_ctrl
        jsr     kb_back
        lda     #0
        jmp     set_ok

; the keyboard comes back from the classic machine (KB_ROUTE 1 -> 0): empty the queue
; (nothing typed for the Atari reaches Horizon) and swallow the keys the I/O processor
; reports again because they are still held
kb_back:
        stz     rep_u
        stz     kq_head
        stz     kq_count
        ldy     #14
        lda     #0
:       sta     sw_keys,y
        dey
        dey
        bpl     :-
        lda     ticks
        sta     sw_t0
        lda     #1
        sta     sw_on
        a8
        lda     #0
        sta     f:KB_ROUTE
        a16
        rts

; ---- classic machine freeze (hardware REV $06+, SV_CTRL bit 2 FREEZE_REQ). The machine
; is frozen while the desktop is shown. Read-modify-write keeps the other SV_CTRL bits;
; FROZEN is never waited for (older hardware and the emulator do not have it). ----
classic_freeze:
        a8
        lda     f:SYS_REV
        cmp     #$06
        bcc     :+
        lda     f:SV_CTRL
        ora     #$04
        sta     f:SV_CTRL
:       a16
        rts
classic_run:
        jsr     snd_silence             ; (the sound writes need the freeze)
        a8
        lda     f:SYS_REV
        cmp     #$06
        bcc     :+
        lda     f:SV_CTRL
        and     #$FB
        sta     f:SV_CTRL
:       a16
        rts

; ---- $50 input_claim ----
sys_iclaim:
        jsr     term_iclaim             ; (a terminal: its own keys)
        bcs     :+
        rts
:
        lda     cur
        inc     a
        cmp     in_owner
        beq     @ok                     ; already ours (claimed or lent): keep the queue
        lda     in_owner
        beq     :+
        lda     #EAGAIN
        jmp     set_err
:       lda     cur
        inc     a
        sta     in_owner
        ldx     cur
        lda     #NONE
        sta     t_lender,x
        stz     kq_head
        stz     kq_count
        a8
        lda     #0
        sta     f:KB_ROUTE
        a16
@ok:    lda     #0
        jmp     set_ok

; ---- $51 input_read -> A = usage, X = modifiers | down << 8 (keys);
;      A = $0100 | buttons, X = x, Y = y (mouse); A = $0200, X = wheel delta ----
sys_iread:
        jsr     term_iread
        bcs     :+
        rts
:
        lda     cur
        inc     a
        cmp     in_owner
        bne     iread_bad
        lda     kq_count
        bne     iread_take
        ldx     cur
        lda     t_killed,x
        bne     iread_bad
        lda     #W_INPUT
        ldy     #0
        jsr     k_block
        bra     sys_iread
iread_take:
        lda     kq_head
        asl     a
        tay
        lda     kq_head
        inc     a
        and     #KQLEN - 1
        sta     kq_head
        dec     kq_count
        ldx     cur
        lda     kq_mods,y
        sta     t_x,x
        lda     kq_usage,y
        cmp     #$0100                  ; keys leave Y alone
        bcc     :+
        lda     kq_y,y
        sta     t_y,x
        lda     kq_usage,y
        and     #$7FFF                  ; (the "do not coalesce" flag)
:       jmp     set_ok
iread_bad:
        jmp     err_inval

; (the tick, interrupt service) the held key repeats: after rep_delay ticks, then every
; rep_rate ticks
rep_tick:
        lda     rep_u
        beq     @out
        lda     rep_delay
        beq     @out
        lda     cls_on
        bne     @out
        dec     rep_n
        bne     @out
        lda     rep_rate
        bne     :+
        inc     a
:       sta     rep_n
        lda     rep_u
        ldx     rep_m
        jmp     key_put2
@out:   rts

; ---- $54 input_poll -> as input_read, or EAGAIN at once when nothing is queued ----
sys_ipoll:
        jsr     term_ipoll              ; (0.22) a task attached to a Terminal window
        bcs     :+
        rts
:       lda     cur
        inc     a
        cmp     in_owner
        beq     :+
        jmp     err_inval
:       lda     kq_count
        beq     :+
        jmp     iread_take
:       lda     #EAGAIN
        jmp     set_err

; ---- $52 input_release ----
sys_irelease:
        jsr     term_irel
        bcs     :+
        rts
:
        lda     cur
        inc     a
        cmp     in_owner
        beq     :+
        jmp     err_inval
:       jsr     input_release_cur
        lda     #0
        jmp     set_ok

; ---- $53 input_lend(A = task id, X bit 0 = ctrl-C kills it): the owner lends the keyboard ----
sys_ilend:
        jsr     term_ilend
        bcs     :+
        rts
:
        lda     cur
        inc     a
        cmp     in_owner
        bne     @inval
        ldx     cur
        lda     t_a,x
        jsr     find_id
        bcs     @inval
        cpx     cur
        beq     @inval
        lda     t_state,x
        cmp     #TS_ZOMBIE
        beq     @inval
        lda     cur
        sta     t_lender,x
        ldy     cur
        lda     t_x,y
        and     #1
        sta     t_lbrk,x
        txa
        inc     a
        sta     in_owner
        lda     #0
        jmp     set_ok
@inval: jmp     err_inval

; the current task gives the keyboard up (input_release, exit): back to its lender if
; there is one, else nobody (KB_ROUTE = 1)
input_release_cur:
        lda     cur
        inc     a
        cmp     in_owner
        bne     @out
        ldx     cur
        lda     t_lender,x
        pha
        lda     #NONE
        sta     t_lender,x
        pla
        cmp     #NONE
        beq     @none
        tax
        lda     t_state,x
        beq     @none
        cmp     #TS_ZOMBIE
        beq     @none
        txa
        inc     a
        sta     in_owner
        jsr     k_wake_input            ; it may be waiting for keys already
        rts
@none:  stz     in_owner
        a8
        lda     #1
        sta     f:KB_ROUTE
        a16
@out:   rts

; wake the keyboard owner if it waits for a key
k_wake_input:
        lda     in_owner
        beq     :+
        dec     a
        tax
        lda     t_state,x
        cmp     #TS_BLOCKED
        bne     :+
        lda     t_wreason,x
        cmp     #W_INPUT
        bne     :+
        jmp     k_wake
:       rts

; at exit: nobody may return the keyboard to this task any more
input_forget_cur:
        ldx     #0
:       lda     t_lender,x
        cmp     cur
        bne     :+
        lda     #NONE
        sta     t_lender,x
:       inx
        inx
        cpx     #NSLOT*2
        bne     :--
        rts

; sched.s - scheduler, blocking and waking, idle loop, timer tick, interrupt service.
;
; Each task has its own kernel stack. A task that is not running keeps its kernel S in
; t_ksp; resuming it is "S = t_ksp, RTS". k_block and k_yield save the caller's context
; that way; a new task's kernel stack holds the address of its first kernel routine.
; Priority 0 is the highest; within a priority, round robin starting after the last task
; picked. Time slice: SLICE_TICKS ticks of 10 ms. The kernel itself is never preempted:
; need_resched is acted on at the next return to user mode.

        .a16
        .i16

; ---- block the current task: A = reason (W_*), Y = object. Returns once woken. ----
k_block:
        ldx     cur
        sta     t_wreason,x
        tya
        sta     t_wobj,x
        lda     #TS_BLOCKED
        sta     t_state,x
        bra     k_save_switch

; ---- give up the CPU, staying ready ----
k_yield:
        ldx     cur
        lda     #TS_READY
        sta     t_state,x
        ; fall through
; save this kernel context (the caller's return address is on the stack) and run another
k_save_switch:
        ldx     cur
        tsc
        sta     t_ksp,x
        ; fall through
; pick the next task and resume it; with nothing ready, the idle loop
k_pick_run:
        jsr     pick_next
        cpx     #NONE
        bne     k_run
        lda     #IDLE_TOP
        tcs
        jmp     idle_loop

; resume task X (slot*2)
k_run:  stx     cur
        stx     rr_pos
        lda     #TS_RUNNING
        sta     t_state,x
        lda     #SLICE_TICKS
        sta     t_slice,x
        stz     need_resched
        txa
        xba                             ; slot*2*256 = slot*512
        clc
        adc     #KSTK_BASE + KSTK_SIZE - 1
        sta     e_stop
        a8
        lda     t_id,x
        sta     f:CUR_TASK
        lda     t_wbank,x
        beq     :+                      ; still loading: no window yet
        sta     f:B0WIN
:       a16
        lda     t_ksp,x
        tcs
        rts

; X = best ready slot*2 (highest priority, round robin after rr_pos) or NONE
pick_next:
        lda     #4
        sta     kt6
        lda     #NONE
        sta     kt7
        ldx     rr_pos
        cpx     #NSLOT*2
        bcc     :+
        ldx     #0
:       ldy     #NSLOT
@loop:  inx
        inx
        cpx     #NSLOT*2
        bcc     :+
        ldx     #0
:       lda     t_state,x
        cmp     #TS_READY
        bne     @next
        lda     t_prio,x
        cmp     kt6
        bcs     @next
        sta     kt6
        stx     kt7
@next:  dey
        bne     @loop
        ldx     kt7
        rts

; ---- wake task X (slot*2) if it is blocked. Keeps X. ----
k_wake: lda     t_state,x
        cmp     #TS_BLOCKED
        bne     @out
        lda     #TS_READY
        sta     t_state,x
        stz     t_wreason,x
        ldy     cur
        cpy     #NONE
        beq     @out
        lda     t_prio,x
        cmp     t_prio,y
        bcs     @out
        lda     #1
        sta     need_resched
@out:   rts

; wake every task blocked for reason A on object Y
k_wake_all:
        sta     kt6
        sty     kt7
        ldx     #0
@loop:  lda     t_state,x
        cmp     #TS_BLOCKED
        bne     @next
        lda     t_wreason,x
        cmp     kt6
        bne     @next
        lda     t_wobj,x
        cmp     kt7
        bne     @next
        jsr     k_wake
@next:  inx
        inx
        cpx     #NSLOT*2
        bne     @loop
        rts

; ---- idle loop: the only place where the kernel enables interrupts ----
idle_loop:
        lda     #NONE
        sta     cur
        ldx     #0
:       lda     t_state,x
        bne     @alive
        inx
        inx
        cpx     #NSLOT*2
        bne     :-
        kprint  "[halt] no tasks\n"
        stp
@alive: jsr     mb_drain                ; a system key seen while idle: queue it now
        jsr     nmi_poll
        jsr     pick_next
        cpx     #NONE
        beq     :+
        jmp     k_run
:       cli
        wai
        sei
        bra     idle_loop

; ---- interrupt service: called with interrupts masked from any kernel context.
; Never switches tasks; it only wakes them and sets need_resched. ----
irq_service:
        a8
        lda     f:IRQ_STATUS            ; (0.18) the raster line first: it is due now
        and     f:IRQ_EN
        bit     #$02
        beq     :+
        a16
        jsl     k2_line
        a8
:       lda     f:IRQ_STATUS            ; mailbox first: key events that arrived before
        bit     #IRQ_IOP                ; a system key press are queued before its $FF
        beq     :+
        a16
        jsr     mb_drain
        a8
:       lda     f:IRQ_STATUS
        bit     #IRQ_TIMER0
        beq     :+
        lda     #IRQ_TIMER0
        sta     f:IRQ_STATUS
        a16
        jsr     tick
        a8
:       lda     f:IRQ_STATUS            ; the blitter is done (REV $08)
        bit     #IRQ_BLITTER
        beq     :+
        lda     #IRQ_BLITTER
        sta     f:IRQ_STATUS
        a16
        lda     #1
        sta     bl_done
        lda     #W_BLIT
        ldy     #0
        jsr     k_wake_all
        a8
:       jsr     vs_irq                  ; (0.15) a vertical blank awaited (vsync)
        lda     f:IRQ_STATUS            ; anything else that is latched: drop it (0.18: not the
        and     #$3C & ~(IRQ_TIMER0 | IRQ_BLITTER) ; raster line or the blank that latched
                                        ; meanwhile: their handlers take them next time)
        beq     :+
        sta     f:IRQ_STATUS
:       a16
        rts

; service pending interrupts from a kernel busy-wait (console); keeps X and Y
irq_poll:
        a8
        lda     f:IRQ_STATUS
        and     f:IRQ_EN
        a16
        beq     :+
        phx
        phy
        jsr     irq_service
        ply
        plx
:       rts

; ---- 10 ms tick ----
tick:   inc     ticks
        bne     :+
        inc     ticks+2
:       jsr     clock_update
        jsr     clk_tick                ; (0.14) the clock's seconds
        a8
        lda     #$5A                    ; (re)arm and restart: an expiry disarms it
        sta     f:WATCHDOG
        a16
        jsr     nmi_poll
        jsr     sw_check
        jsr     snd_tick
        jsr     ws_tick
        jsr     rep_tick
        ; sleepers whose wake-up tick has come
        ldx     #0
@loop:  lda     t_state,x
        cmp     #TS_BLOCKED
        bne     @next
        lda     t_wreason,x
        cmp     #W_SLEEP
        bne     @next
        lda     ticks+2
        cmp     t_wake_hi,x
        bcc     @next
        bne     @wake
        lda     ticks
        cmp     t_wake_lo,x
        bcc     @next
@wake:  jsr     k_wake
@next:  inx
        inx
        cpx     #NSLOT*2
        bne     @loop
        ; time slice of the running task
        ldx     cur
        cpx     #NONE
        beq     @out
        lda     t_slice,x
        beq     :+
        dec     t_slice,x
        bne     @out
:       lda     #1
        sta     need_resched
@out:   rts

; milliseconds since boot from the hardware microsecond counter (exact even when ticks were
; lost while the kernel had interrupts masked): us_acc += UPTIME - us_last, 1000 us -> 1 ms
clock_update:
        a8
        lda     f:UPTIME                ; latches the upper three bytes
        a16
        and     #$00FF
        sta     kt5
        lda     f:UPTIME+1
        xba
        and     #$FF00
        ora     kt5                     ; kt5/kt6 = UPTIME
        sta     kt5
        lda     f:UPTIME+2
        sta     kt6
        lda     kt5
        sec
        sbc     us_last
        tax
        lda     kt6
        sbc     us_last+2
        tay                             ; Y:X = elapsed microseconds
        lda     kt5
        sta     us_last
        lda     kt6
        sta     us_last+2
        txa
        clc
        adc     us_acc
        sta     us_acc
        tya
        adc     us_acc+2
        sta     us_acc+2
@ms:    lda     us_acc+2                ; while us_acc >= 1000: ms++
        bne     @sub
        lda     us_acc
        cmp     #1000
        bcc     @out
@sub:   lda     us_acc
        sec
        sbc     #1000
        sta     us_acc
        bcs     :+
        dec     us_acc+2
:       inc     ms_lo
        bne     @ms
        inc     ms_hi
        bra     @ms
@out:   rts

; queue a key event ($FF, down) for each system key press counted by the NMI handler
nmi_poll:
        a8
        lda     nmi_cnt
        cmp     nmi_seen
        a16
        beq     :+
        inc     nmi_seen                ; the counters are compared as bytes
        lda     cls_on                  ; the classic machine is shown: F12 brings
        beq     @key                    ; Horizon back instead of being a key
        lda     #1
        sta     cls_done
        lda     #W_CLASSIC
        ldy     #0
        jsr     k_wake_all
        bra     nmi_poll
@key:   lda     #$FF
        ldx     #$0100
        jsr     key_put
        bra     nmi_poll
:       rts

; ---- sleep the current task until tick (A = ticks from now, >= 1). Interruptible. ----
k_sleep_ticks:
        ldx     cur
        clc
        adc     ticks
        sta     t_wake_lo,x
        lda     ticks+2
        adc     #0
        sta     t_wake_hi,x
        lda     #W_SLEEP
        ldy     #0
        jmp     k_block

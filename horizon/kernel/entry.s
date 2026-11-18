; entry.s - every way into and out of the kernel.
;
; Entry from user mode (COP, BRK, ABORT, IRQ, NMI): the CPU has pushed PBR/PC/P on the
; task's own stack (in its window). The entry code saves A X Y D DBR S and that frame in
; the TCB, switches to the task's kernel stack, D = $8000, DBR = $01, and dispatches.
; The frame is only trusted if it lies inside the window ((S+1) <= $7FFC); for a non-ABORT
; entry a non-zero ABORT_CAUSE also means the hardware dropped the pushes. Either way the
; task is killed.
; Return to user (ret_user) rebuilds the frame on the task's stack, restores everything,
; writes FR_CTRL with USER_ARM = 1 and executes RTI. The kernel never relies on what the
; hardware mode stack holds.
; Entry from supervisor mode is only expected for an IRQ in the idle loop (and NMI, handled
; on the spot); anything else is a panic.

        .a16
        .i16

; ---- native vectors (reached through JML trampolines at $00:E000) ----
v_cop:  rep     #$30
        sta     f:KDPL+e_a
        lda     #K_COP
        jmp     entry
v_brk:  rep     #$30
        sta     f:KDPL+e_a
        lda     #K_BRK
        jmp     entry
v_abort:
        rep     #$30
        sta     f:KDPL+e_a
        lda     #K_ABORT
        jmp     entry
v_irq:  rep     #$30
        sta     f:KDPL+e_a
        lda     #K_IRQ
        jmp     entry

; NMI: may arrive anywhere, even inside the kernel. From user mode it is a normal entry;
; from supervisor mode it is handled on the current stack, touching only NMI_STATUS and
; the nmi_cnt counter (the key event is queued later by nmi_poll).
v_nmi:  rep     #$30
        sta     f:KDPL+n_a
        a8
        lda     f:FR_CTRL
        and     #FRC_ARM
        beq     @super
        ; From user mode. Clear NMI_STATUS now (no stack use: S is still the task's):
        ; releasing the NMI hold with a source still set would raise a second NMI edge.
@col:   lda     f:NMI_STATUS
        beq     @go
        sta     f:NMI_STATUS
        ora     f:KDPL+nmi_pend
        sta     f:KDPL+nmi_pend
        bra     @col
@go:    a16
        lda     f:KDPL+n_a
        sta     f:KDPL+e_a
        lda     #K_NMI
        jmp     entry
        .a8
@super: a16
        lda     f:KDPL+n_a
        pha
        jsr     nmi_status
        bcc     :+
        lda     #KDP                    ; the watchdog expired while the kernel ran
        tcd
        pea     KBANK * $0101
        plb
        plb
        kpanic  "watchdog in the kernel"
:       a8
        lda     f:KDPL+ctrl_base        ; back to the interrupted kernel code
        sta     f:FR_CTRL
        a16
        pla
        rti

; Reads and clears NMI_STATUS until it reads 0 (NMI stays asserted while it is non-zero).
; Counts system key presses. Returns C set if the watchdog expired (the caller decides:
; kill the task it interrupted, or panic). Keeps X and Y; long addressing only, any D/DBR.
nmi_status:
        a8
        lda     f:KDPL+nmi_pend         ; what the user-mode entry already collected
        sta     f:KDPL+nmi_wd
        lda     #0
        sta     f:KDPL+nmi_pend
@loop:  lda     f:NMI_STATUS
        beq     @done
        sta     f:NMI_STATUS
        ora     f:KDPL+nmi_wd
        sta     f:KDPL+nmi_wd
        bra     @loop
@done:  lda     f:KDPL+nmi_wd
        bit     #$01
        beq     :+
        lda     f:KDPL+nmi_cnt
        inc     a
        sta     f:KDPL+nmi_cnt
        lda     f:KDPL+nmi_wd
:       and     #$02
        cmp     #2                      ; C = watchdog seen
        a16
        rts

; ---- emulation-mode vectors: a task that switched to emulation mode is killed ----
v_ecop:
v_eabort:
v_eirq: clc
        xce
        rep     #$30
        sta     f:KDPL+e_a
        lda     #K_EMU
        jmp     entry
v_enmi: clc
        xce
        rep     #$30
        sta     f:KDPL+e_a
        jsr     nmi_status
        lda     #K_EMU
        jmp     entry

v_unexp:
        clc
        xce
        rep     #$30
        sta     f:KDPL+e_a
        lda     #$FF
        jmp     entry

; ---- common entry: A = kind, e_a = A of the interrupted code ----
entry:  sta     f:KDPL+e_kind
        a8
        lda     f:FR_CTRL
        and     #FRC_ARM
        a16
        bne     :+
        jmp     from_super
:       tsc                             ; leave the task's stack as early as possible
        sta     f:KDPL+e_s
        lda     f:KDPL+e_stop           ; the current task's kernel stack
        tcs
        a8                              ; on the kernel stack: release the NMI hold that
        lda     #CTRL_KERNEL            ; the hardware (REV $04) set at this entry
        sta     f:FR_CTRL
        a16
        txa
        sta     f:KDPL+e_x
        tya
        sta     f:KDPL+e_y
        tdc
        sta     f:KDPL+e_d
        lda     #KDP
        tcd
        lda     #0
        a8
        phb
        pea     KBANK * $0101
        plb
        plb
        pla                             ; user DBR
        a16
        ldy     cur
        sta     t_dbr,y
        lda     e_a
        sta     t_a,y
        lda     e_x
        sta     t_x,y
        lda     e_y
        sta     t_y,y
        lda     e_d
        sta     t_d,y
        lda     e_kind
        cmp     #K_EMU
        jeq     @emu
        ; native frame: P at S+1, PC at S+2, PBR at S+4 (window, bank 0)
        lda     e_s
        inc     a
        cmp     #$7FFD
        bcs     @badfr
        tax
        lda     f:$000000,x
        and     #$00FF
        sta     t_p,y
        lda     f:$000001,x
        sta     t_pc,y
        lda     f:$000003,x
        and     #$00FF
        sta     t_pbr,y
        txa
        clc
        adc     #3
        sta     t_s,y
        a8
        lda     f:ABORT_CAUSE
        a16
        and     #$001F
        sta     kt0
        ldx     e_kind
        cpx     #K_EMU
        bcc     :+
        kpanic  "unused vector"
:       cpx     #K_ABORT
        beq     :+
        cmp     #0
        bne     @lost                   ; a push of this entry was refused
:       jmp     (kind_tab,x)

@badfr: ; frame outside the window: PC unknown
        lda     e_s
        clc
        adc     #4
        sta     t_s,y
        lda     #$FFFF
        sta     t_pbr,y                 ; marks "PC unknown"
        lda     e_kind
        cmp     #K_ABORT
        jeq     ent_abort
@lost:  lda     #$FFFF
        sta     t_pbr,y
        a8
        lda     #$1F
        sta     f:ABORT_CAUSE
        a16
        lda     e_kind                  ; an IRQ or NMI still needs service
        jsr     service_kind
        lda     e_s
        clc
        adc     #4
        sta     kt1                     ; "addr" = the task's S before the entry
        stz     kt2
        lda     #CAUSE_STACK
        jmp     fault_kill

@emu:   ; emulation frame: P at S+1, PC at S+2 (stack page 1, inside the window)
        lda     e_s
        inc     a
        tax
        lda     f:$000000,x
        and     #$00FF
        sta     t_p,y
        lda     f:$000001,x
        sta     t_pc,y
        lda     #0
        sta     t_pbr,y
        txa
        clc
        adc     #2
        sta     t_s,y
        a8
        lda     #$1F
        sta     f:ABORT_CAUSE
        a16
        stz     kt1
        stz     kt2
        lda     #CAUSE_EMUL
        jmp     fault_kill

kind_tab:
        .word   .loword(ent_cop), .loword(ent_brk), .loword(ent_abort), .loword(ent_irq), .loword(ent_nmi)

; IRQ / NMI side work for a task that is being killed anyway
service_kind:
        cmp     #K_IRQ
        bne     :+
        jmp     irq_service
:       cmp     #K_NMI
        bne     :+
        jsr     nmi_status
        jsr     mb_drain
        jmp     nmi_poll
:       rts

ent_irq:
        jsr     irq_service
        jmp     ret_user

ent_nmi:
        jsr     nmi_status
        php
        jsr     mb_drain                ; key events that came before the system key
        jsr     nmi_poll
        plp
        bcs     :+
        jmp     ret_user
:       stz     kt1                     ; the watchdog expired in this task (SEI + loop)
        stz     kt2
        lda     #CAUSE_WDOG
        jmp     fault_kill

ent_brk:
        ldx     cur                     ; addr = the BRK itself (PC - 2)
        lda     t_pc,x
        sec
        sbc     #2
        sta     kt1
        lda     t_pbr,x
        sta     kt2
        lda     #CAUSE_BRK
        jmp     fault_kill

ent_abort:
        a8
        lda     f:ABORT_CAUSE
        sta     kt0
        lda     #$1F
        sta     f:ABORT_CAUSE
        a16
        lda     f:ABORT_ADDR
        sta     kt1
        lda     f:ABORT_ADDR+2
        and     #$00FF
        sta     kt2
        lda     kt0
        and     #$001F
        jmp     fault_kill

; ---- fault: A = cause, kt2:kt1 = address. Logs one line, the task exits $FF00 + cause ----
fault_kill:
        sta     kt0
        jsr     iobuf_of                ; the line is built in the task's buffer, then
        sta     kout                    ; printed under the console lock like a puts
        kprint  "[kill] task "
        ldx     cur
        lda     t_id,x
        jsr     kputdec
        lda     #' '
        jsr     kputc
        jsr     kputname
        kprint  " cause "
        lda     kt0
        jsr     kputhex8
        kprint  " addr "
        lda     kt2
        jsr     kputhex8
        lda     kt1
        jsr     kputhex16
        kprint  " pc "
        ldx     cur
        lda     t_pbr,x
        cmp     #$FFFF
        bne     :+
        kprint  "??????"
        bra     :++
:       jsr     kputhex8
        ldx     cur
        lda     t_pc,x
        jsr     kputhex16
:       lda     #10
        jsr     kputc
        lda     #0
        jsr     kputc
        stz     kout
        lda     kt0
        ora     #$FF00
        pha
        jsr     iobuf_of
        jsr     con_print
        pla
        jmp     do_exit

; ---- syscall: the number is the COP signature byte, at PBR:PC-1 ----
ent_cop:
        ldx     cur
        lda     t_pc,x
        dec     a
        sta     kp0
        lda     t_pbr,x
        sta     kp0+2
        a8
        lda     [kp0]
        a16
        and     #$00FF
        cmp     #NSYS
        bcs     @nosys
        asl     a
        tax
        jsr     (sys_tab,x)
        jmp     ret_user
@nosys: lda     #ENOSYS
        jsr     set_err
        jmp     ret_user

; ---- return to user mode (current task, on its kernel stack) ----
ret_user:
        jsr     irq_poll                ; ticks keep coming even for a task running with I = 1
        ldx     cur
        lda     t_killed,x
        beq     :+
        lda     t_killcode,x
        jmp     do_exit
:       lda     need_resched
        beq     :+
        jsr     k_yield
        bra     ret_user
:       a8
        lda     t_id,x
        sta     f:CUR_TASK
        lda     t_wbank,x
        sta     f:B0WIN
        a16
        stz     kp0
        stz     kp0+2                   ; kp0 = $00:0000 (the window)
        lda     t_s,x
        sec
        sbc     #4
        sta     kt1                     ; S for the RTI
        tay
        a8
        iny
        lda     t_p,x
        sta     [kp0],y
        iny
        lda     t_pc,x
        sta     [kp0],y
        iny
        lda     t_pc+1,x
        sta     [kp0],y
        iny
        lda     t_pbr,x
        sta     [kp0],y
        a16
        lda     t_a,x
        sta     r_a
        lda     t_x,x
        sta     r_x
        lda     t_y,x
        sta     r_y
        lda     t_d,x
        sta     kt0
        a8
        lda     t_dbr,x
        pha
        plb                             ; from here on: long addressing only
        a16
        lda     kt1
        tcs
        lda     kt0
        tcd
        lda     f:KDPL+r_y
        tay
        lda     f:KDPL+r_x
        tax
        a8
        lda     #CTRL_USER
        sta     f:FR_CTRL
        a16
        lda     f:KDPL+r_a
        rti

; ---- entry from supervisor mode ----
from_super:
        txa
        sta     f:KDPL+e_x
        tya
        sta     f:KDPL+e_y
        tsc
        sta     f:KDPL+e_s
        lda     f:KDPL+e_kind
        cmp     #K_IRQ
        bne     @bad
        lda     f:KDPL+cur
        cmp     #NONE
        bne     @bad
        ; IRQ in the idle loop (idle stack)
        phd
        phb
        lda     #KDP
        tcd
        pea     KBANK * $0101
        plb
        plb
        jsr     irq_service
        plb
        pld
        lda     f:KDPL+e_y
        tay
        lda     f:KDPL+e_x
        tax
        a8
        lda     #CTRL_KERNEL
        sta     f:FR_CTRL
        a16
        lda     f:KDPL+e_a
        rti
@bad:   lda     #KDP
        tcd
        pea     KBANK * $0101
        plb
        plb
        stz     kout
        kprint  "[panic] supervisor entry kind "
        lda     e_kind
        jsr     kputhex8
        a8
        lda     f:ABORT_CAUSE
        a16
        and     #$00FF
        sta     kt0
        kprint  " cause "
        lda     kt0
        jsr     kputhex8
        kprint  " addr "
        lda     f:ABORT_ADDR+2
        jsr     kputhex8
        lda     f:ABORT_ADDR
        jsr     kputhex16
        kprint  " frame "
        lda     e_s
        tax
        lda     f:$000004,x
        jsr     kputhex8
        lda     f:$000002,x
        jsr     kputhex16
        kprint  " P="
        lda     f:$000001,x
        jsr     kputhex8
        jmp     panic_regs

; ---- panic: message already printed; registers from the entry scratch, then STP ----
panic_inline:                           ; JSR'd by kpanic with the message after it
        stz     kout
        kprint  "[panic] "
        pla
        tax
        inx
@m:     lda     f:$010000,x
        and     #$00FF
        beq     panic_regs
        jsr     kputc
        inx
        bra     @m
panic_regs:
        kprint  " A="
        lda     e_a
        jsr     kputhex16
        kprint  " X="
        lda     e_x
        jsr     kputhex16
        kprint  " Y="
        lda     e_y
        jsr     kputhex16
        kprint  " S="
        lda     e_s
        jsr     kputhex16
        kprint  " task "
        lda     cur
        jsr     kputhex16
        lda     #10
        jsr     kputc
        stp

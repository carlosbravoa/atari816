; boot.s - entered from the I/O processor's reset stub (CLC XCE JML $010000): native mode,
; 8-bit registers, junk everywhere. Sets up the kernel state, vectors, bank table,
; mailbox, timer and watchdog, creates the INIT task and enters the idle loop.

        .a8
        .i8
boot:   sei
        cld
        clc
        xce
        rep     #$30
        .a16
        .i16
        lda     #IDLE_TOP
        tcs
        lda     #KDP
        tcd
        pea     KBANK * $0101
        plb
        plb
        stz     ctrl_base               ; the NMI handler writes this to FR_CTRL
        a8
        lda     #0
        sta     f:FR_CTRL               ; protection off until the table is valid
        sta     f:IRQ_EN
        sta     f:TM0_CTRL
        lda     #$1F
        sta     f:ABORT_CAUSE
        a16
        ; (0.18) the second code segment (k2.s): the I/O processor loaded it right after the
        ; image, where the BSS goes; to $00:E100 (WP_VEC is off until the end of boot)
        ldx     #0
:       lda     f:__BSS_RUN__,x
        sta     f:__K2CODE_RUN__,x
        inx
        inx
        cpx     #__K2CODE_SIZE__ + __K2DATA_SIZE__ + 1
        bcc     :-
        ; direct page and BSS: junk -> 0
        ldx     #$00FE
:       stz     $00,x
        dex
        dex
        bpl     :-
        lda     #NONE
        sta     cur
        ldx     #.loword(__BSS_RUN__)
:       stz     a:0,x
        inx
        inx
        cpx     #.loword(__BSS_RUN__ + __BSS_SIZE__ + 1)
        bcc     :-
        ldx     #.loword(__BSS2_RUN__)
:       stz     a:0,x
        inx
        inx
        cpx     #.loword(__BSS2_RUN__ + __BSS2_SIZE__ + 1)
        bcc     :-
        ldx     #0                      ; (0.18) the bank 0 variables of k2.s
:       lda     #0
        sta     f:__K0BSS_RUN__,x
        inx
        inx
        cpx     #__K0BSS_SIZE__ + 1
        bcc     :-
        a8
        lda     #$54                    ; MVN stub used by kmemcpy
        sta     mvn_op
        lda     #$60                    ; RTS
        sta     mvn_op+3
        a16
        jsr     bank_init
        jsr     vs_init                 ; the video-state block, the whole palette
        jsr     scr_init                ; the screen console, before the first message
        jsr     mouse_init
        jsr     classic_freeze          ; the classic Atari only runs while it is shown
        jsr     snd_init                ; (POKEY 2 writes need the freeze)
        lda     #1                      ; settings: mouse speed 1, beep volume 8, key
        sta     ms_speed                ; repeat after 0.4 s every 50 ms
        lda     #8
        sta     snd_vol
        sta     smp_vol                 ; (0.18) the sound volume
        jsr     au_master               ; (0.17) Lau's master volume
        lda     #40
        sta     rep_delay
        lda     #5
        sta     rep_rate
        kprint  "\n"
        kprint  KVERSION_STR
        kprint  "\n"
        a8
        lda     f:SYS_REV               ; REV $04 holds NMIs off at a user-mode entry
        cmp     #$04
        a16
        bcs     :+
        kprint  "warning: FPGA rev < $04, no NMI hold at kernel entry\n"
:

        jsr     vec_install
        jsr     mb_init
        jsr     input_init

        ; 10 ms repeating tick on TIMER0
        a8
        lda     #<TICK_US
        sta     f:TM0_RELOAD
        lda     #>TICK_US
        sta     f:TM0_RELOAD+1
        lda     #^TICK_US
        sta     f:TM0_RELOAD+2
        lda     #IRQ_TIMER0
        sta     f:IRQ_STATUS            ; drop a stale latch
        lda     #$03                    ; RUN + REPEAT
        sta     f:TM0_CTRL
        lda     #IRQ_TIMER0 | IRQ_IOP | IRQ_BLITTER
        sta     f:IRQ_EN
        lda     #$03
        sta     f:NMI_STATUS            ; clear stale NMI sources
        lda     #$5A                    ; arm the watchdog; every tick restarts it
        sta     f:WATCHDOG
        ; protection on: kernel window bank = $01 until a task runs
        lda     #KBANK
        sta     f:B0WIN
        lda     #0
        sta     f:CUR_TASK
        a16
        lda     #CTRL_KERNEL
        sta     ctrl_base               ; first: an NMI writes ctrl_base to FR_CTRL
        a8
        sta     f:FR_CTRL
        a16
        lda     #1
        sta     next_id

        ; the first task: /SYSTEM/INIT.PRG, priority 1, no parent
        ldx     #0
:       lda     init_path,x
        sta     kpath,x
        inx
        inx
        cpx     #init_path_end - init_path + 1
        bcc     :-
        lda     #1
        sta     kt0                     ; priority
        lda     #NONE
        sta     kt1                     ; parent
        stz     kt2                     ; argument
        jsr     task_create
        bcc     :+
        jsr     kputhex8
        kpanic  "no slot for INIT"
:       lda     #1
        sta     booted
        jmp     idle_loop

init_path:      .byte   "/SYSTEM/INIT.PRG", 0
init_path_end:

; ---- vectors: JML trampolines at $00:E000, then the vector words, then WP_VEC ----
vec_install:
        ldx     #0
:       lda     tramp_src,x
        sta     f:$00E000,x
        inx
        inx
        cpx     #tramp_end - tramp_src
        bcc     :-
        ldx     #0
:       lda     vec_tab,x               ; vector address
        tay
        lda     vec_tab+2,x             ; trampoline
        phx
        tyx
        sta     f:$000000,x
        plx
        inx
        inx
        inx
        inx
        cpx     #vec_end - vec_tab
        bcc     :-
        rts

tramp_src:
        .byte   $5C
        .faraddr v_cop                  ; $E000
        .byte   $5C
        .faraddr v_brk                  ; $E004
        .byte   $5C
        .faraddr v_abort                ; $E008
        .byte   $5C
        .faraddr v_nmi                  ; $E00C
        .byte   $5C
        .faraddr v_irq                  ; $E010
        .byte   $5C
        .faraddr v_unexp                ; $E014
        .byte   $5C
        .faraddr v_ecop                 ; $E018
        .byte   $5C
        .faraddr v_eabort               ; $E01C
        .byte   $5C
        .faraddr v_enmi                 ; $E020
        .byte   $5C
        .faraddr v_eirq                 ; $E024
tramp_end:

vec_tab:
        .word   $FFE4, $E000            ; native COP
        .word   $FFE6, $E004            ; native BRK
        .word   $FFE8, $E008            ; native ABORT
        .word   $FFEA, $E00C            ; native NMI
        .word   $FFEE, $E010            ; native IRQ
        .word   $FFE0, $E014
        .word   $FFE2, $E014
        .word   $FFEC, $E014
        .word   $FFF4, $E018            ; emulation COP
        .word   $FFF8, $E01C            ; emulation ABORT
        .word   $FFFA, $E020            ; emulation NMI
        .word   $FFFE, $E024            ; emulation IRQ / BRK
        .word   $FFF0, $E014
        .word   $FFF2, $E014
        .word   $FFF6, $E014
vec_end:

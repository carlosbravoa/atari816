; emu816 mouse test: takes the keyboard and mouse (KB_ROUTE = 0) and prints every event,
; "MOUSE dx dy wheel buttons" for $E1 and "KEY usage mods down" for $E0. From 0.5 s to 0.7 s
; KB_ROUTE is 1 (input belongs to the classic side: mouse motion is discarded). Ends at 1 s.
        .include "common.inc"

MB_REQ_BASE = $00DD00
MB_RSP_BASE = $00DD05
MB_RSP_HEAD = $00DD08
MB_RSP_TAIL = $00DD09
MB_STATUS   = $00DD0A
KB_ROUTE    = $00DE20
RSP_RING    = $0E1000
ms          = $20               ; direct page: UPTIME / 256 (~ms/4), 16 bits

        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        ldx     #$01FF
        txs
        phk
        plb
        print   m_hello
        lda     #$00
        sta     f:MB_REQ_BASE
        sta     f:MB_RSP_BASE
        sta     f:MB_REQ_BASE+1
        lda     #$10
        sta     f:MB_RSP_BASE+1
        lda     #$0E
        sta     f:MB_REQ_BASE+2
        sta     f:MB_RSP_BASE+2
        lda     #$00
        sta     f:KB_ROUTE

loop:   jsr     now                     ; X = UPTIME / 256 (units of 256 us)
        cpx     #1953                   ; 0.5 s
        bcc     :+
        cpx     #2734                   ; 0.7 s
        bcs     :+
        lda     #$01                    ; classic side owns the input
        bra     :++
:       lda     #$00
:       cmp     f:KB_ROUTE
        beq     :+
        sta     f:KB_ROUTE
        pha
        print   m_route
        pla
        jsr     puthex
        jsr     crlf
:       lda     f:MB_RSP_HEAD
        cmp     f:MB_RSP_TAIL
        beq     idle
        rep     #$20
        .a16
        lda     f:MB_RSP_TAIL
        and     #$00FF
        asl
        asl
        asl
        asl
        tax
        sep     #$20
        .a8
        lda     f:RSP_RING,x
        cmp     #$E1
        bne     :+
        phx
        print   m_mouse
        plx
        lda     f:RSP_RING+8,x          ; dx
        jsr     sp_hex
        lda     f:RSP_RING+9,x          ; dy
        jsr     sp_hex
        lda     f:RSP_RING+10,x         ; wheel
        jsr     sp_hex
        lda     f:RSP_RING+12,x         ; buttons
        jsr     sp_hex
        jsr     crlf
        bra     next
:       cmp     #$E0
        bne     next
        phx
        print   m_key
        plx
        lda     f:RSP_RING+8,x
        jsr     sp_hex
        lda     f:RSP_RING+12,x
        jsr     sp_hex
        lda     f:RSP_RING+13,x
        jsr     sp_hex
        jsr     crlf
next:   lda     f:MB_RSP_TAIL
        inc
        sta     f:MB_RSP_TAIL
idle:   jsr     now
        cpx     #3906                   ; 1 s
        bcs     :+
        jmp     loop
:       lda     #$01
        sta     f:KB_ROUTE
        print   m_done
        stp

sp_hex: pha
        lda     #' '
        jsr     putc
        pla
        jmp     puthex

now:    lda     f:UPTIME                ; latches the upper bytes
        lda     f:UPTIME+1
        sta     ms
        lda     f:UPTIME+2
        sta     ms+1
        ldx     ms
        rts

m_hello: .byte "MOUSETEST", 10, 0
m_route: .byte "KB_ROUTE ", 0
m_mouse: .byte "MOUSE", 0
m_key:   .byte "KEY", 0
m_done:  .byte "DONE", 10, 0

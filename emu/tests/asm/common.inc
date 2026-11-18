; Shared helpers for the emu816 test programs (a8 i16, DBR = program bank).
        .p816
        .smart  -

DBG_OUT    = $00DEF0
SYS_ID     = $00DE00
IRQ_STATUS = $00DE08
IRQ_EN     = $00DE09
UPTIME     = $00DE18

        .macro  print   msg
        ldx     #.loword(msg)
        jsr     puts
        .endmacro

        .segment "CODE"
        jmp     start                   ; the program starts at $01:0000, helpers follow
        .a8
        .i16
crlf:   lda     #10
putc:   sta     f:DBG_OUT
        rts
puts:   lda     a:0,x
        beq     :+
        jsr     putc
        inx
        bra     puts
:       rts
puthex: pha
        lsr
        lsr
        lsr
        lsr
        jsr     nib
        pla
        and     #$0F
nib:    cmp     #10
        bcc     :+
        adc     #6
:       adc     #'0'
        bra     putc
puthex16:                               ; X as 4 hex digits
        rep     #$20
        .a16
        txa
        sep     #$20
        .a8
        xba
        jsr     puthex
        xba
        jmp     puthex

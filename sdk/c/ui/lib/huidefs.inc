; huidefs.inc - the C binding's own symbols (sdk/c/ui/lib/*.s, the generated shims).
; ca65 syntax, included after horizon.inc and ui.inc.
;
; The block (sdk/docs/c/apps.md, "How the block is built") starts at $0100 of the program's
; code bank with a 12-byte header the C side (the wrapper hcc writes) fills in:
;   +0  JMP _start          the program's entry: the C startup
;   +3  JML ___hui_fatal    C: void __hui_fatal(const char *msg): prints msg, exits
;   +7  .word hz_errno      the address of the C library's hz_errno (code bank)
;   +9  JMP hui_rowtramp    LS_ROW of every C list (HUI_ROWCB in hui.h), or RTS
HUI_FATAL  = hui_hdr + 3
HUI_ERRNO  = hui_hdr + 7
HUI_ROWCB  = hui_hdr + 9

.global hui_hdr
.global hui_fail                ; A = message: the C program's __hui_fatal (never returns)
.global hui_seterr              ; A -> hz_errno (keeps A)
.global hui_incb                ; nonzero inside a callback into C
.global hui_instr, hui_outstr   ; scratch copies of C strings (str.s)
.global hui_rowtramp            ; the list row callback (row.s)
.global hui_setwin, hui_setcpcb  ; ui_setwin, ui_setcpcb (setwin.s, cpcb.s)
.globalzp hui_ra, hui_rx, hui_ry, hui_cy, hui_s, hui_d, hui_fn

; ZSAVE / ZRESTORE: the block's whole direct page (ZEROPAGE: ulib's, the library's and
; ours, $50 up to hui_zend; every module reserves words, so the size is even) pushed on
; the stack and pulled back, around a call into C. A, X clobbered.
.globalzp hui_zend
.macro  ZSAVE
        .local  lp
        ldx     #hui_zend - 2
lp:     lda     f:0,x                   ; (bank 0: the direct page, D = 0)
        pha
        dex
        dex
        cpx     #$50
        bcs     lp
.endmacro
.macro  ZRESTORE
        .local  lp
        ldx     #$50
lp:     pla
        sta     f:0,x
        inx
        inx
        cpx     #hui_zend
        bcc     lp
.endmacro

; CALLC: JSL to the C function whose 24-bit address is in z:hui_fn (A, X: its first
; argument; the others pushed before). Returns here.
.macro  CALLC
        .local  back
        phk
        per     back - 1
        .byte   $DC                     ; JML [hui_fn] (absolute indirect long: bank 0,
        .word   hui_fn                  ;   the direct page, D = 0)
back:
.endmacro

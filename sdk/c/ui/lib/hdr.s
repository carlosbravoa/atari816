; hdr.s - the block's header: 12 bytes at $0100 of the code bank, written by the wrapper
; hcc makes for each program (huidefs.inc lists them). Linked first (BLOBHDR).
        .p816
        .include "horizon.inc"
        .include "ui.inc"
        .include "huidefs.inc"

        .segment "BLOBHDR"
hui_hdr:
        .res    12

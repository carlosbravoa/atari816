# Atari816: Register Specification v0.1

Nov 16, 2026 · @Carlos

Every register a Horizon driver or the FPGA needs, following the decisions in [Atari816: System Architecture Design](https://claude.ai/artifact/2m27W3DQiW3NNPuqpLi2Tu).

## Conventions and I/O page map

All native I/O lives in $00:D800 to $00:DFFF, in 256-byte blocks; user-mode code cannot touch it and must go through a system call.

- **Addresses:** 24-bit, written bank:offset ($00:D800). Multi-byte registers are little-endian; a 24-bit pointer is three bytes, low, middle, high.
- **Access:** R (read only), W (write only), RW. Unlisted bits read 0 and must be written 0. Unlisted addresses are reserved.
- **Reset:** every register resets to 0 unless its row says otherwise.
- **Status bits** marked W1C are cleared by writing 1 to them.
- **Latching:** reading the low byte of a multi-byte counter latches the other bytes until they are read.

| Range | Block | Section |
| --- | --- | --- |
| $00:D000 to $00:D7FF | Classic chipset window (only when the supervisor gives the chipset to the native side) | Classic supervisor |
| $00:D800 to $00:D8FF | FREDDIE II | FREDDIE II |
| $00:D900 to $00:D9FF | Marga (video) | Marga |
| $00:DA00 to $00:DAFF | Ali (blitter) | Ali |
| $00:DB00 to $00:DBFF | Native audio: POKEY 2, Lau (sample player) | Native audio |
| $00:DC00 to $00:DCFF | Classic supervisor | Classic supervisor |
| $00:DD00 to $00:DDFF | I/O processor mailbox | Mailbox |
| $00:DE00 to $00:DEFF | System: ID, interrupts, timers, input routing | System block |
| $00:DF00 to $00:DFFF | Reserved for expansion |  |

**The custom chips and their register prefixes:** FREDDIE II, the memory manager (FR\_\*); Marga, the video chip (NV\_\*, from its old name, the native video controller or NVC); Ali, the blitter (BL\_\*); Lau, the 8-voice sample player (AU\_\*); POKEY 2, the classic machine's second POKEY lent to the native side (its own register names, at $DB00). The prefixes keep the old names, so code does not change.

### 65C816 vectors (native mode)

All vector fetches switch FREDDIE II to supervisor mode in hardware, using the 65C816's VPB (vector pull) output.

| Vector | Address | Use in Horizon |
| --- | --- | --- |
| COP | $00:FFE4 | System calls: `COP #n`, arguments in A, X, Y, carry set on error |
| BRK | $00:FFE6 | Debugger breakpoints |
| ABORT | $00:FFE8 | Protection faults from FREDDIE II |
| NMI | $00:FFEA | System key (F12) |
| IRQ | $00:FFEE | All other interrupts, via the system block |
| RESET | $00:FFFC | Emulation-mode reset; the kernel switches to native mode at once |

## FREDDIE II: modes, protection, bank 0 window

FREDDIE II checks every 65C816 access against a 256-entry bank table and asserts ABORT on a violation; the kernel enters user mode by arming a flag and executing RTI.

### Mode rules

1. **Supervisor mode** is entered in hardware on every vector fetch (VPB low): interrupts, COP, BRK, ABORT, reset.
2. **User mode** is entered when FR\_CTRL.USER\_ARM is set and an RTI completes: the first opcode fetch after it runs in user mode, and USER\_ARM clears.
3. In supervisor mode every access is allowed, except writes to $00:E000 to $00:FFFF while FR\_CTRL.WP\_VEC is set.
4. In user mode an access is allowed only if the bank's entry is VALID, its OWNER is CUR\_TASK or 63 (shared), and, for a write, WRITE is set. Any user access to $00:D000 to $00:DFFF is refused.
5. A refused access asserts ABORT: the instruction completes without changing registers or memory, then the ABORT vector runs. Refused writes never reach memory.

### Registers

| Address | Name | Access | Bits |
| --- | --- | --- | --- |
| $00:D800 | FR\_CTRL | RW | 0 PROT\_EN, 1 USER\_ARM, 2 B0WIN\_EN, 3 WP\_VEC, 7 MODE (R: 1 = user) |
| $00:D801 | PT\_INDEX | RW | Bank number 0 to 255 for PT\_DATA |
| $00:D802 | PT\_DATA | RW | Entry for bank PT\_INDEX: bits 0 to 5 OWNER (0 kernel only, 1 to 62 task, 63 shared), 6 WRITE, 7 VALID |
| $00:D803 | CUR\_TASK | RW | Bits 0 to 5: task id checked against OWNER |
| $00:D804 to $00:D806 | ABORT\_ADDR | R | 24-bit address of the last refused access |
| $00:D807 | ABORT\_CAUSE | R, W1C | 0 WRITE (it was a write), 1 NOT\_OWNER, 2 NOT\_VALID, 3 IO\_PAGE, 4 WP\_VEC (supervisor write to protected vectors) |
| $00:D808 | B0WIN | RW | Physical bank whose $0000 to $7FFF replaces $00:0000 to $00:7FFF when B0WIN\_EN is set; must be $01 or above |
| $00:D809 | RAM\_BANKS | R | Installed RAM in 64 KB banks, minus 1 ($7F for 8 MB, $FF for 16 MB) |

PT\_DATA reads and writes do not auto-increment, so a context switch only rewrites CUR\_TASK and B0WIN, never the table.

### Bank 0 window

With B0WIN\_EN set, both modes see the current task's private 32 KB at $00:0000 to $00:7FFF (its direct page and stack). The kernel keeps its own direct page and stack at $00:8000 and up, and switches B0WIN on every task switch. On an interrupt the 65C816 pushes onto the interrupted task's stack, inside its window; the kernel entry code then moves S to its own stack above $00:8000.

## FREDDIE II: classic map

The classic map is a set of base pointers that FREDDIE II applies to every 6502 and ANTIC address of the active classic session; the supervisor writes them only while the 6502 is held in reset or frozen.

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:D810 | CM\_MODEL | RW | Bits 0 to 1: 0 = 400/800, 1 = XL/XE. Bit 2 BASIC\_FITTED (XL/XE: PORTB bit 1 can enable it). Bit 3 PAL. Bit 4 SEPARATE\_ANTIC (130XE: PORTB bit 5 for ANTIC) |
| $00:D811 | CM\_MAIN | RW | Physical bank (64 KB) of the session's main RAM |
| $00:D812 | CM\_EXT | RW | First physical bank of the extended RAM pool |
| $00:D813 | CM\_EXT\_MODE | RW | 0 none, 1 130XE (64 KB), 2 320 KB RAMBO. The classic machine is capped at 320 KB extended RAM since REV $0A (the 576 KB and 1088 KB schemes were removed from the core) |
| $00:D814 to $00:D815 | CM\_OS | RW | Physical address bits 23 to 14 of the 16 KB OS image (XL/XE); for 400/800 the 10 KB OS-A/B image sits in its top 10 KB |
| $00:D816 to $00:D817 | CM\_BASIC | RW | Physical address bits 23 to 13 of the 8 KB BASIC image |
| $00:D818 to $00:D81A | CM\_CART | RW | 24-bit physical address of the cartridge image, 8 KB aligned |
| $00:D81B | CM\_CART\_TYPE | RW | .CAR header type number (0 = no cartridge); bank switching through $D500 follows the current core's cartridge logic, which since REV $0A keeps only standard 8/16 KB, 2/4 KB, OSS, XEGS and switchable XEGS, Atarimax, SIC and MegaCart |
| $00:D81C | CM\_RAMSIZE | RW | 400/800 only: top of RAM in 4 KB pages ($C0 = 48 KB) |

### Resulting 6502 view

| 6502 range | Source |
| --- | --- |
| $0000 to $3FFF | CM\_MAIN |
| $4000 to $7FFF | CM\_MAIN, or a CM\_EXT bank when PORTB selects one (CPU and ANTIC selected separately when SEPARATE\_ANTIC) |
| $5000 to $57FF | XL/XE self-test from the CM\_OS image when PORTB bit 7 = 0 and bit 0 = 1 |
| $8000 to $BFFF | CM\_MAIN, CM\_BASIC at $A000 when enabled, or CM\_CART |
| $C000 to $CFFF | XL/XE: CM\_OS when PORTB bit 0 = 1, else CM\_MAIN |
| $D000 to $D7FF | The real chipset; $D1C0 to $D1CF is the classic side of the mailbox (see supervisor) |
| $D800 to $FFFF | CM\_OS when the OS is enabled, else CM\_MAIN |

All image areas (OS, BASIC, cartridge) are read-only to the 6502. The 6502 has no way to form an address outside these sources, so a classic session cannot read or write Horizon's memory.

## Classic supervisor

The supervisor block lets Horizon start, freeze, inspect and resume the classic machine, feed it keys, and swap the HDMI source; while frozen, the whole classic domain (6502, ANTIC, GTIA, POKEYs, PIA) stops on the same clock edge.

### Control and status

| Address | Name | Access | Bits |
| --- | --- | --- | --- |
| $00:DC00 | SV\_CTRL | RW | 0 RUN, 1 RESET (holds the classic domain in reset), 2 FREEZE\_REQ, 3 STEP, 4 CHIPSET\_NATIVE (chipset window at $00:D000 belongs to Horizon; only while RESET or frozen), 5 TURBO, 6 VIDEO\_CLASSIC (HDMI shows the classic picture), 7 LOWLAT (genlocked line-buffer output instead of the frame buffer) |
| $00:DC01 | SV\_STATUS | R, W1C on bits 1 to 4 | 0 FROZEN, 1 JAM (KIL opcode hit), 2 BREAKPOINT, 3 MAILBOX, 4 COLD\_START (6502 jumped to the OS cold-start entry), 7 IN\_VBLANK |
| $00:DC02 | SV\_IRQ\_EN | RW | Same bit layout as SV\_STATUS bits 1 to 4; a set status bit with its enable raises the SUPERVISOR interrupt |

**Freeze:** setting FREEZE\_REQ makes the hardware wait for the first scanline of vertical blank, then the next 6502 instruction boundary, then stop the classic clock enable and set FROZEN. Clearing FREEZE\_REQ resumes on the next clock. With FROZEN set, writing 1 to STEP runs exactly one 6502 instruction (ANTIC DMA included) and freezes again. POKEY audio is muted while frozen.

**Reset and start:** with RESET set, write the classic map, load images, then clear RESET and set RUN. The 6502 starts from the RESET vector of the classic map, like a real power-on.

### 6502 registers and breakpoints (valid while FROZEN)

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:DC04 | SV\_A | RW | Accumulator |
| $00:DC05 | SV\_X | RW | X |
| $00:DC06 | SV\_Y | RW | Y |
| $00:DC07 | SV\_S | RW | Stack pointer |
| $00:DC08 | SV\_P | RW | Status flags |
| $00:DC09 to $00:DC0A | SV\_PC | RW | Program counter |
| $00:DC0B | SV\_INJECT | W | 0 NMI, 1 IRQ: raise that interrupt on resume |
| $00:DC10 to $00:DC11 | SV\_BP0 | RW | Breakpoint 0 address |
| $00:DC12 | SV\_BP0\_CTRL | RW | 0 on opcode fetch, 1 on read, 2 on write; hit freezes the 6502 and sets BREAKPOINT |
| $00:DC14 to $00:DC16 | SV\_BP1 | RW | Breakpoint 1, same layout |

### Chip state

Every classic chip register, including the write-only ones and the internal counters a save state needs, is reachable through an index port.

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:DC20 | SV\_CHIP\_SEL | RW | 0 ANTIC, 1 GTIA, 2 POKEY 1, 3 POKEY 2, 4 PIA, 5 ANTIC internal, 6 POKEY internal (counters, polynomials) |
| $00:DC21 | SV\_CHIP\_IDX | RW | Register index within the chip |
| $00:DC22 | SV\_CHIP\_DATA | RW | Value; each access increments SV\_CHIP\_IDX |

The exact index list per chip comes from the chip sources during bring-up.

### Keyboard and joysticks for the session

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:DC28 | SV\_KEY | W | Bits 0 to 5 Atari key code, 6 SHIFT, 7 CONTROL: presses that key in POKEY's matrix |
| $00:DC29 | SV\_KEY\_CTRL | RW | 0 KEY\_DOWN (release by clearing), 1 BREAK key, 2 HELP key (XL/XE) |
| $00:DC2A | SV\_CONSOL | RW | 0 START, 1 SELECT, 2 OPTION (1 = pressed) |
| $00:DC2B | SV\_JOY\_OVR | RW | Bits 0 to 3 stick 1 directions, 4 to 7 stick 2: ORed with the DB9 ports (USB gamepads) |
| $00:DC2C | SV\_TRIG\_OVR | RW | 0 trigger 1, 1 trigger 2 |

When the system block routes the keyboard to the classic side, this happens in hardware without Horizon; these registers are for paste and for the I/O processor's gamepads.

### Mailbox

A small register mailbox lets classic programs (the H: handler, an exit-to-desktop call) talk to Horizon.

| Classic address | Native address | Direction | Meaning |
| --- | --- | --- | --- |
| $D1C0 to $D1C6 | $00:DC30 to $00:DC36 | classic to native | 7 data bytes |
| $D1C7 | $00:DC37 | classic to native | Command; a classic write sets SV\_STATUS.MAILBOX |
| $D1C8 to $D1CE | $00:DC38 to $00:DC3E | native to classic | 7 reply bytes |
| $D1CF | $00:DC3F | native to classic | Reply status: bit 7 BUSY while the command is in progress, cleared when the reply is ready |

Command $01 asks Horizon to end the session (Quit); $10 to $1F are reserved for the H: handler.

## Marga (video) — $D900: framebuffer, palette, pointer, sprites, scrolling

Marga, the video chip, reads a 640x360 framebuffer from main RAM and shows it at exactly 2x on the 1280x720 output, with a 256-entry palette and a hardware pointer; it is idle while the HDMI shows a classic session. From REV $0B it adds fine scrolling and 16 sprites (sections below); with their registers left at their reset values the picture is exactly as in REV $0A.

### Display

| Address | Name | Access | Bits or meaning |
| --- | --- | --- | --- |
| $00:D900 | NV\_CTRL | RW | 0 ENABLE, 1 to 2 MODE (0 = 640x360x8, 1 = 640x360x4, 2 = 320x180x8 at 4x), 3 POINTER\_EN |
| $00:D901 to $00:D903 | NV\_BASE | RW | 24-bit framebuffer address, 256-byte aligned (low byte ignored); takes effect at the next vertical blank |
| $00:D904 to $00:D905 | NV\_STRIDE | RW | Bytes per line (from REV $0B: per bitmap row); reset value 640 |
| $00:D906 to $00:D907 | NV\_LINE | R | Raster line on screen, 0 to 359, 360 to 365 in vertical blank (see "Raster events"). From REV $09 reading $D906 latches $D907 |
| $00:D908 to $00:D909 | NV\_LINE\_CMP | RW | The LINE event (IRQ\_STATUS bit 1) fires when NV\_LINE becomes this value; reset value 511 (never). REV $0B: also the split line (see Fine scrolling) |
| $00:D90A | NV\_STATUS | R | 0 IN\_VBLANK (NV\_LINE is 360 or more), 1 BASE\_PENDING (a new NV\_BASE has not been taken yet) |
| $00:D90B | NV\_LATE | R, any write clears | Lines whose fetch had not finished in time (saturates at 255) |
| $00:D90C to $00:D90D | NV\_FRAME | R | REV $09: frames since the 65C816 was released, +1 at each VBLANK event, wraps at 65536. Reading $D90C latches $D90D |

In 4 bpp mode the high nibble is the left pixel, and pixels use palette entries 0 to 15.

### Raster events (REV $09 timing)

Lines are always the 360 lines of the 640x360 picture, in all three modes (in 320x180 mode picture line p is shown on lines 2p and 2p+1); each is two output lines of the 1280x720 raster (43.8 µs). Line n of a frame begins with the horizontal blank at the end of the second output line of line n-1 (for line 0: the blank before the first visible output line). At that point NV\_LINE becomes n, and:

- n = NV\_LINE\_CMP sets LINE (IRQ\_STATUS bit 1);
- n = 360 (the end of the last visible line) sets VBLANK (IRQ\_STATUS bit 0) and adds 1 to NV\_FRAME;
- lines 360 to 365 are vertical blank; NV\_LINE stays 365 until line 0 of the next frame (the blank lasts 40 output lines, 876 µs).

The horizontal blank is 292 pixel clocks (4.1 µs): a LINE handler that writes the palette within that time changes the colour exactly from line n on. The events run whether or not ENABLE is set, also while the HDMI shows the classic machine; the frame rate is that of the shared raster (1572 x 760 pixel clocks at 71.72 MHz, 60.03 Hz). Before REV $09 the events came 1,141 clk\_core cycles (about 40 µs) earlier, at the fetch of line n, while line n-1 was being drawn.

### Palette

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:D910 | PAL\_IDX | RW | Entry 0 to 255 |
| $00:D911 | PAL\_R | RW | Red, 8 bits |
| $00:D912 | PAL\_G | RW | Green |
| $00:D913 | PAL\_B | RW | Blue; a write commits the entry and increments PAL\_IDX |

The reset palette is the GTIA NTSC palette, so colour $94 means the same blue on both sides.

### Pointer

The pointer is 32x32 at 2 bits per pixel (256 bytes in main RAM): 0 transparent, 1 palette entry PTR\_C1, 2 entry PTR\_C2, 3 entry PTR\_C3.

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:D920 to $00:D921 | PTR\_X | RW | Hot spot X in framebuffer pixels, 0 to 639 |
| $00:D922 to $00:D923 | PTR\_Y | RW | Hot spot Y, 0 to 359 |
| $00:D924 | PTR\_HOT | RW | Bits 0 to 3 hot spot X offset, 4 to 7 Y offset, in 2-pixel steps |
| $00:D925 to $00:D927 | PTR\_IMG | RW | 24-bit address of the image |
| $00:D928 to $00:D92A | PTR\_C1 to PTR\_C3 | RW | Palette entries for colours 1 to 3 |

The pointer is drawn at framebuffer resolution and scaled with it, so it looks like the rest of the desktop. The image is 32 rows of 8 bytes, the leftmost pixel in bits 7 and 6 of the first byte; PTR\_IMG is 8-byte aligned (bits 0 to 2 are ignored). The pointer registers are not latched: each line uses their values at its fetch, one line period before it is shown, so a move made in vertical blank never splits the pointer.

### Fine scrolling (REV $0B)

Without these registers the picture can only move by whole NV\_BASE steps of 256 bytes: with a 640-byte stride that is two lines vertically, and horizontally nothing finer than 256 pixels (a line must also start on a 16-byte burst). REV $0B adds pixel-exact offsets, wrap-around in a larger virtual bitmap and a split screen. Lines are always fetched from 16-byte (8-byte while the classic machine runs) aligned addresses; the offset inside the first burst is dropped by Marga as the line is unpacked, which costs one more burst per line.

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:D930 to $00:D931 | NV\_SCROLLX | RW | Bits 0 to 11: pixels (of the current mode) to skip at the start of every line, 0 to 4095 |
| $00:D932 to $00:D933 | NV\_SCROLLY | RW | Bits 0 to 9: the bitmap row shown on line 0, 0 to 1023 |
| $00:D934 to $00:D935 | NV\_SCROLLX2 | RW | Like NV\_SCROLLX, for the lines from the split on |
| $00:D936 to $00:D937 | NV\_SCROLLY2 | RW | The row shown on the split line |
| $00:D938 to $00:D939 | NV\_VHEIGHT | RW | Bits 0 to 9: rows in the virtual bitmap; the row after row VHEIGHT - 1 is row 0. 0 = no vertical wrap |
| $00:D93A | NV\_SCROLL\_CTRL | RW | 0 HWRAP (a line that runs past the end of its row, NV\_STRIDE bytes, continues at the start of the same row), 1 SPLIT |

**Rows.** Row r of the bitmap starts at NV\_BASE + r × NV\_STRIDE. Line 0 shows row NV\_SCROLLY; every following line shows the next row (in 320x180 mode every second line, as before), and the row after VHEIGHT - 1 is row 0 when VHEIGHT is not 0. A line shows the pixels NV\_SCROLLX to NV\_SCROLLX + 639 (319) of its row. With HWRAP the bytes of a row are taken modulo NV\_STRIDE, so a row of NV\_STRIDE bytes is a horizontal ring; without it the line simply reads on into the next row. NV\_SCROLLY may be VHEIGHT or more: the wrap happens only when the row number reaches VHEIGHT - 1 exactly, so rows below the virtual bitmap (a status panel, for instance) can be shown without wrapping.

**Split.** With SPLIT set, line L, where L is NV\_LINE\_CMP as it was at the fetch of line 0 (1 to 359), starts again: it shows row NV\_SCROLLY2 (with the same wrap rule), with NV\_SCROLLX2. Lines 0 to L - 1 use the first set, lines L to 359 the second. A status panel above a playfield: the panel at rows VHEIGHT and up with fixed offsets in the first set, the playfield in the second; a panel below is the other way round. The LINE interrupt still fires at L, so a handler can change the palette for the panel at the same line. In 320x180 mode L should be even.

**Latching.** All six registers, and NV\_LINE\_CMP for the split, are taken at the fetch of line 0, together with NV\_BASE (they read back the value written). Whatever is written before that point (about 830 µs after the VBLANK interrupt) applies to the whole next frame; nothing changes in the middle of a frame. Values that need changing mid-frame belong to the second set.

**Limits.** NV\_STRIDE must be a multiple of 16 (8 while the classic machine runs); with HWRAP, NV\_SCROLLX must be below the row's width in pixels. Sprites and the pointer do not scroll. In 4 bpp mode NV\_SCROLLX counts pixels, two per byte.

### Sprites (REV $0B)

Marga draws 16 sprites over the bitmap in all three modes. Each has its own image in RAM, which Marga reads itself through its memory port, line by line, like the bitmap; moving a sprite is a write of its position, animating it a write of its image address. The pointer stays in front of everything.

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:D940 | NV\_SPR\_CTRL | RW | 0 SPR\_EN: draw the sprites (needs NV\_CTRL.ENABLE) |
| $00:D941 | NV\_SPR\_COMMIT | W, R | Write any value: copy the 16 records, as written, to the set in use, in vertical blank. Read: bit 0 PENDING (1 from the write until the copy is done) |
| $00:D942 | NV\_SPR\_STATUS | R, W1C | 0 OVERFLOW (a visible sprite was left out of a line, see the line limit), 1 LATE (a line's sprites were not finished in time; 0 in normal use) |
| $00:D943 | NV\_SPR\_PEEK | RW | Write: index 0 to 255 of a record byte to read back (0 to 127: the records as written, 128 to 255: the set in use) |
| $00:D944 | NV\_SPR\_PEEKD | R | That byte, from the second CPU cycle after the PEEK write |
| $00:D945 to $00:D94F | | | Reserved (collision detection was not built) |
| $00:D980 to $00:D9FF | Records | W | 16 records of 8 bytes, sprite n at $00:D980 + 8n. Write only (they read 0); NV\_SPR\_PEEK reads them back |

**Record** (8 bytes):

| Offset | Field | Meaning |
| --- | --- | --- |
| +0, +1 | X | Left edge in framebuffer pixels, signed; bits 0 to 10 are used (-1024 to 1023) |
| +2, +3 | Y | Top edge in picture lines (framebuffer pixels), signed; bits 0 to 9 are used (-512 to 511) |
| +4 | IMG / PAL | Bits 4 to 7: image address bits 4 to 7. Bits 0 to 3: PAL, the palette bank of a 4 bpp sprite |
| +5, +6 | IMG | Image address bits 8 to 23. The image is 16-byte aligned; bits 0 to 3 of its address are PAL instead |
| +7 | CTRL | 0 EN, 1 HFLIP, 2 VFLIP, 3 MAG (2x in both directions), 4 WIDE (32 pixels wide; 4 bpp only, ignored at 8 bpp), 5 TALL (32 lines, else 16), 6 BPP4 (else 8 bpp), 7 BEHIND |

**Images.** Rows from top to bottom, no gaps: 8 bpp is 16 pixels of one byte (16 bytes a row); 4 bpp is two pixels a byte, the left one in the high nibble (8 bytes a row, 16 with WIDE). Sizes: 16 x 16 and 16 x 32 at 8 bpp; 16 x 16, 32 x 16, 16 x 32, 32 x 32 at 4 bpp; MAG doubles them on screen (up to 64 x 64). Colour 0 is transparent (8 bpp: byte 0; 4 bpp: nibble 0). A 4 bpp pixel p (1 to 15) shows palette entry PAL × 16 + p, also in the 640x360x4 mode, so sprites there can use all 256 colours. A sprite pixel can never show palette entry 0. Why both depths: a 4 bpp sprite of 32 pixels reads the same 16-byte burst per line as an 8 bpp one of 16, so 4 bpp gives twice the width for the same memory time and half the image size; 8 bpp is there for full-colour images. 32-pixel 8 bpp rows (two bursts) were left out: two 16 x 32 sprites side by side do the same.

**Position and clipping.** X and Y are the top-left corner; a sprite is drawn where it overlaps the picture (640 x 360, or 320 x 180), so it can slide out past every edge. In 320x180 mode positions and sizes are in the large pixels. HFLIP and VFLIP mirror the image; MAG repeats each pixel and each row.

**Priority.** Sprite 0 is in front, sprite 15 at the back; all are in front of the bitmap, except that a BEHIND sprite's pixels are hidden by bitmap pixels that are not colour 0. The pointer is in front of everything.

**Line limit.** Marga prepares each line in the line period before it is shown. For every line it takes the sprites visible on that line in index order (0 first) and keeps a sprite if the sum of the on-screen widths kept so far (16, 32 or 64 pixels: 16 << (WIDE + MAG)) plus its own is 512 or less; a sprite that does not fit is left out of that line only, sets OVERFLOW, and the ones after it are still tried. So all 16 sprites always appear when they are at most 32 pixels wide on screen (16 x 32 = 512), and eight 64-pixel ones fit on one line. The budget is set by time: drawing takes a cycle per on-screen pixel plus about 25 per sprite, and the worst line within the budget leaves a third of the line period spare for memory delays (bring-up log, step 19). Sprites do not cost CPU time; their memory reads come just after the bitmap's (see Memory).

**Latching.** The CPU writes the records as written (a shadow); Marga draws from the set in use. Writing NV\_SPR\_COMMIT copies all 128 bytes in vertical blank: at once (within about 15 µs) if the write comes between the fetch of line 360 (one line before the VBLANK interrupt) and the fetch of line 0, otherwise at the start of the next vertical blank. PENDING reads 1 until the copy is done; do not write the records while it is 1. A frame never shows half-updated sprites. The usual loop: on VBLANK, write the changed record bytes, write COMMIT; the new positions are on screen from line 0 of the next frame. SPR\_EN is not latched: it acts from the next line fetched.

**Reset.** While the 65C816 is held in reset the records (both sets), SPR\_EN, PENDING and the status return to 0.

**Memory.** Every line, Marga reads the record set (from its own block RAM) and one burst per sprite on that line: 16 bytes (two of 8 bytes while the classic machine runs, which works but leaves less margin), or 8 bytes for a 16-pixel 4 bpp row. Priority on the port: Marga's line fetch, Lau, the sprite fetch, the CPU, Ali. The longest a line has taken in simulation is given in the bring-up log, step 19; LATE stays 0 there.

Showing one sprite, 16 x 16 at 8 bpp, image at $02:0000, at (100, 50):

```
        sep #$20 : lda #1 : sta f:$00D940          ; SPR_EN
        rep #$20 : lda #100 : sta f:$00D980         ; X
        lda #50 : sta f:$00D982                     ; Y
        lda #$0000 : sta f:$00D984                  ; IMG bits 0-15 (PAL 0)
        lda #$0102 : sta f:$00D986 : sep #$20 : sta f:$00D941   ; IMG bits 16-23 = $02, CTRL = EN; COMMIT
```

The image is 256 bytes at $02:0000, 16 rows of 16 palette indices, 0 transparent.

## Ali (blitter) — $DA00

Ali, the blitter, does five rectangle operations on 8 bpp surfaces anywhere in RAM; clipping is done by the GUI library before it starts a blit, which keeps the hardware small.

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:DA00 to $00:DA02 | BL\_SRC | RW | 24-bit source address (first byte of the rectangle) |
| $00:DA03 to $00:DA04 | BL\_SRC\_STRIDE | RW | Source bytes per line |
| $00:DA05 to $00:DA07 | BL\_DST | RW | 24-bit destination address |
| $00:DA08 to $00:DA09 | BL\_DST\_STRIDE | RW | Destination bytes per line |
| $00:DA0A to $00:DA0B | BL\_WIDTH | RW | Width in pixels, 1 to 4096 |
| $00:DA0C to $00:DA0D | BL\_HEIGHT | RW | Height in lines, 1 to 4096 |
| $00:DA0E | BL\_FG | RW | Fill colour, or colour for 1 bits in EXPAND |
| $00:DA0F | BL\_BG | RW | Colour for 0 bits in EXPAND |
| $00:DA10 | BL\_KEY | RW | Transparent colour for COPY\_KEY |
| $00:DA11 | BL\_OP | RW | 0 FILL, 1 COPY, 2 COPY\_KEY (skip pixels equal to BL\_KEY), 3 EXPAND (1 bpp source to BL\_FG and BL\_BG), 4 EXPAND\_KEY (0 bits leave the destination alone) |
| $00:DA12 | BL\_FLAGS | RW | 0 BACKWARDS (copy from the last pixel, for overlapping moves), bits 4 to 6 SRC\_BIT (first source bit for EXPAND, 7 = leftmost) |
| $00:DA13 | BL\_CTRL | RW | Write: bit 0 START, bit 1 IRQ\_EN, bit 2 LIST (REV $09), bit 3 ABORT (REV $09). Read: bit 0 BUSY, bit 1 IRQ\_EN, and from REV $09 bit 2 LIST (a list is running), bit 3 WAITING (the list waits for vertical blank), bit 4 DONE, bit 5 ABORTED. IRQ\_EN raises BLITTER in the system block when a blit or a list is done |
| $00:DA14 to $00:DA16 | BL\_LIST | RW | REV $09: 24-bit address of the next command record, 8-byte aligned (bits 0 to 2 are ignored and read 0) |
| $00:DA17 to $00:DA18 | BL\_COUNT | RW | REV $09: number of records still to run, 0 to 65535 |

EXPAND reads 1 bpp sources with the leftmost pixel in bit 7, which matches Atari font and icon data. The 65C816 may keep running while the blitter works; both share SDRAM through FREDDIE II, with the classic side keeping priority.

**Rules (all revisions).** START and LIST are ignored while BUSY is 1. From REV $09, writes to $DA00 to $DA12 and $DA14 to $DA18 are ignored while BUSY is 1 (before REV $09 they were not allowed). WIDTH or HEIGHT 0, or OP above 4, does nothing; WIDTH and HEIGHT above 4096 count as 4096. The blitter writes behind the 65C816's cache: write CACHE\_FLUSH ($00:D80A) before the CPU reads memory the blitter has written. Addresses wrap at the installed RAM. An overlapping copy in the wrong direction (BACKWARDS clear when the destination starts above the source, or set when it starts below) is undefined.

### Command lists (REV $09)

A command list lets the blitter run many blits without the CPU: the CPU writes the records to memory, sets BL\_LIST and BL\_COUNT and writes BL\_CTRL with LIST set; the blitter reads each record, loads it into $DA00 to $DA12 and runs it exactly as if START had been written, then goes on with the next.

| Record byte | Field |
| --- | --- |
| 0 to 18 | Same layout as $DA00 to $DA12: SRC (3), SRC\_STRIDE (2), DST (3), DST\_STRIDE (2), WIDTH (2), HEIGHT (2), FG, BG, KEY, OP, FLAGS |
| 19 | RFLAGS: bit 0 WAIT\_VBL (before this blit, wait for the next VBLANK event, see Marga) |
| 20 to 23 | Reserved, write 0 |

- A record is 24 bytes; records follow each other with no gap, and the first must be 8-byte aligned.
- Each record is read when the one before it has finished. BL\_LIST then points to the record after it and BL\_COUNT holds the records not yet read; after a list BL\_LIST points past the last record, BL\_COUNT is 0, and $DA00 to $DA12 hold the last record's values.
- BUSY reads 1 from the LIST write until the last blit has finished. The BLITTER interrupt (with IRQ\_EN) comes once, at the end of the list, never after single records. A LIST write with BL\_COUNT 0 finishes at once (and raises the interrupt).
- DONE is set when a blit or a list ends normally, ABORTED when it was stopped by ABORT; both clear on the next START or LIST.
- **ABORT** (with BUSY set) stops the list and the blit that is running after at most one memory access; BUSY then drops within a few cycles, with no interrupt. Pixels the stopped blit had written stay written. BL\_LIST and BL\_COUNT show where the list stopped (the stopped record has been counted).
- While BUSY, the CPU can only change IRQ\_EN and write ABORT: all other blitter register writes are ignored.
- Records are read through the blitter's own memory port (video fetch, then CPU, then blitter); the CPU's writes reach RAM at once (write-through cache), so no flush is needed before LIST.
- WAIT\_VBL is the cheap way to a tear-free update: put it on the first record of a frame's work; the blits then start in vertical blank (about 870 µs before line 0 is fetched).

## Native audio — $DB00: POKEY 2 and Lau

Two parts share $00:DB00 to $00:DBFF: the classic machine's second POKEY and four DACs, lent to the 65C816 while the classic machine is frozen (REV $07), and Lau, the 8-voice sample player, which plays from main RAM (REV $0A). Both are mixed with the classic machine's sound into the HDMI audio.

**Status (2026-11-17):** Lau is in the default build from REV $0A (bring-up log, step 17). A build with `A816_NO_SAMPLER` defined in `core/src/tang_top.sv` leaves it out and reports REV $09; there $DB20 to $DBFF read 0 and ignore writes.

### POKEY 2 and DACs (REV $07)

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:DB00 to $00:DB0F | POKEY 2 | W | The classic machine's second POKEY (AUDF1 to SKCTL), only while SV\_CTRL.FREEZE\_REQ is set |
| $00:DB10 to $00:DB13 | DAC0 to DAC3 | W | 8-bit DACs: 0 and 1 left, 2 and 3 right, same condition |

They run from a 1.79 MHz tick that does not stop with the freeze; the frozen first POKEY is left out of the mix. Horizon must silence them before resuming the classic machine.

### Lau (sample player) — $DB20 (REV $0A)

Eight voices play signed PCM samples from anywhere in RAM; after KEYON the hardware needs nothing more from the CPU. Every 48 kHz output sample (the HDMI audio rate, taken from the HDMI transmitter's own sample clock), each playing voice steps its position by its pitch, reads its sample from RAM if the position moved, and adds it to the left and right sums with its two volumes. There is no interpolation (see Behaviour).

**Voice registers**, 16 bytes per voice at $00:DB80 + 16 × n (n = 0 to 7), write only (they read 0). A voice reads them every output sample, so they can be changed while it plays (for slides and streaming); a multi-byte field that is half written may be used once (21 µs).

| Offset | Name | Meaning |
| --- | --- | --- |
| +$0 to +$2 | V\_START | 24-bit address of sample 0 (even for 16-bit samples) |
| +$3 to +$5 | V\_LEN | Length in samples, 0 to 16,777,215: positions run 0 to LEN - 1 |
| +$6 to +$8 | V\_LOOP | Loop start in samples from sample 0, below LEN |
| +$9 to +$A | V\_PITCH | Position step per output sample, unsigned 2.14 fixed point: $4000 = one sample per output sample (a 48 kHz recording at its own pitch), $2000 = 24 kHz; up to $FFFF (almost 4) |
| +$B | V\_VOL\_L | Left volume, 0 to 255 (255 = 255/256) |
| +$C | V\_VOL\_R | Right volume |
| +$D | V\_CTRL | 0 LOOP, 1 SIXTEEN (16-bit little-endian samples, else 8-bit) |
| +$E to +$F | | Reserved |

Samples are signed (8-bit: -128 to 127; 16-bit: -32768 to 32767).

**Common registers**

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:DB20 | AU\_KEYON | W | 1 bits start those voices at position 0 and set them in AU\_PLAYING (also a voice that is playing: it restarts) |
| $00:DB21 | AU\_KEYOFF | W | 1 bits stop those voices at once |
| $00:DB22 | AU\_PLAYING | R | Bit n = voice n is playing |
| $00:DB23 | AU\_END | R, W1C | Bit n is set when voice n reaches LEN: it then stops (LOOP clear, PLAYING clears) or goes on at the loop (LOOP set) |
| $00:DB24 | AU\_IRQ\_EN | RW | The AUDIO interrupt (IRQ\_STATUS bit 5) is set while any bit of AU\_END AND AU\_IRQ\_EN is set; clear it through AU\_END |
| $00:DB25 | AU\_MASTER | RW | Master volume of Lau, reset value $C0 |
| $00:DB26 | AU\_LATE | R, any write clears | Output samples that were not ready in time (saturates at 255); 0 in normal use |
| $00:DB27 | AU\_SEL | RW | Bits 0 to 2: the voice AU\_POS shows |
| $00:DB28 to $00:DB2A | AU\_POS | R | Position (whole samples) of voice AU\_SEL when it was last stepped. Not latched (an exception to the convention, to save logic): it changes once per output sample, so read $DB2A, $DB29, $DB28, then $DB2A again and repeat if it changed |
| $00:DB2C to $00:DB2D | AU\_OUT\_L | R | Lau's left output now (L below, signed 16-bit; not latched, changes at 48 kHz) |
| $00:DB2E to $00:DB2F | AU\_OUT\_R | R | Right output |

**Behaviour**

- **Position.** The position is POS + FRAC / 16384. Each output sample adds V\_PITCH to it. When POS reaches LEN: with LOOP, POS = POS - LEN + V\_LOOP (the overshoot is kept; LEN - LOOP must be at least 4, else at least the step); without LOOP the voice stops and outputs nothing more. Either way the voice's AU\_END bit is set.
- **No interpolation.** A voice outputs the sample at its position (the last one it read) until the position moves on. Linear interpolation was planned but left out: it cost about 90 logic cells, a multiplier and a second stored sample per voice, more than the budget allowed. Samples recorded near 48 kHz, or played near pitch $4000, sound clean; low-rate samples played slowly get the usual stair-step aliasing.
- **Start.** KEYON takes effect within four output samples (83 µs, the output FIFO below); the first output of the voice is sample 0.
- **Mix.** Per voice, a 16-bit value (8-bit samples are multiplied by 256) times its volume, divided by 512 (arithmetic shift, rounding down); the sum over the voices (18 bits) times AU\_MASTER / 256, saturated to 16 bits: L = sat(Σ (sample × V\_VOL\_L >> 9) × AU\_MASTER >> 8), likewise R. One voice at full volume and AU\_MASTER $FF reaches half of full scale; louder sums are clipped. The HDMI output is the classic machine's mix (POKEYs, DACs, as before but shifted by +16384, so that its silence sits at -16384 instead of -32768) plus L and R, saturated.
- **Memory.** A voice reads its samples as 8-byte blocks and keeps the last one, so at pitch $4000 it reads RAM once every 8 (8-bit) or 4 (16-bit) output samples. Reads go through Ali's memory port with priority after Marga's line fetch and before the sprite fetch, the CPU and the blitter (REV $0B; in REV $0A after the CPU). The player computes up to four output samples ahead into a FIFO; a sample that is not ready when the HDMI takes it repeats the last one and counts in AU\_LATE.
- Lau runs whether the classic machine is frozen or not. While the 65C816 is held in reset (restart) all its registers return to their reset values and it is silent.
- Like Ali, it reads RAM behind the 65C816's cache: samples the CPU has just written are in RAM already (write-through), nothing to flush.

## System block

The system block identifies the machine, collects every interrupt source into the 65C816's IRQ and NMI, provides two timers and a microsecond clock, and decides where the keyboard goes.

### Identity and speed

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:DE00 | SYS\_ID | R | $81 ("8" for Atari816, revision family 1) |
| $00:DE01 | SYS\_REV | R | Hardware revision |
| $00:DE02 | SYS\_SPEED | RW | 0 = 14.3 MHz (spec), 1 = turbo; reads back the speed actually in use (turbo is ignored where the build does not support it) |

### Interrupts

| Address | Name | Access | Bits |
| --- | --- | --- | --- |
| $00:DE08 | IRQ\_STATUS | R, W1C | 0 VBLANK, 1 LINE, 2 TIMER0, 3 TIMER1, 4 BLITTER, 5 AUDIO, 6 IOP (response or event waiting), 7 SUPERVISOR |
| $00:DE09 | IRQ\_EN | RW | Same layout; IRQ is asserted while any enabled bit is set |
| $00:DE0A | NMI\_STATUS | R, W1C | 0 SYSTEM\_KEY (F12 pressed), 1 WATCHDOG |

The SUPERVISOR bit is the OR of the supervisor's enabled status bits; the AUDIO bit (REV $0A) is the OR of AU\_END AND AU\_IRQ\_EN, a live level that IRQ\_STATUS writes do not clear. The system key is an NMI so that it reaches Horizon even when a task has disabled interrupts.

### Timers and clock

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:DE10 to $00:DE12 | TM0\_RELOAD | RW | 24-bit count in microseconds |
| $00:DE13 | TM0\_CTRL | RW | 0 RUN, 1 REPEAT (reload and continue; else stop at 0) |
| $00:DE14 to $00:DE16 | TM1\_RELOAD | RW | Same as TM0 |
| $00:DE17 | TM1\_CTRL | RW | Same as TM0 |
| $00:DE18 to $00:DE1B | UPTIME | R | 32-bit microseconds since reset; reading $DE18 latches all four bytes |
| $00:DE1C | WATCHDOG | W | Writing $A5 restarts a 2-second watchdog once it has been armed by writing $5A |

Horizon uses TIMER0 as the scheduler tick (10 ms suggested) and TIMER1 for sleeps.

### Input routing

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:DE20 | KB\_ROUTE | RW | 0 = keyboard events go to Horizon through the mailbox; 1 = keys go straight into the classic POKEY matrix. F12 always raises SYSTEM\_KEY instead |
| $00:DE21 | JOY\_PORT | R | Raw DB9 ports: bits 0 to 3 stick 1 directions, 4 to 7 stick 2 (1 = pressed) |
| $00:DE22 | JOY\_TRIG | R | 0 trigger 1, 1 trigger 2 |

The mouse always goes to Horizon; while a classic session is shown, Horizon ignores it unless the session's profile asks for joystick-port mouse emulation.

## I/O processor mailbox

Horizon and the PicoRV32 I/O processor exchange 16-byte messages through two rings in main RAM; the registers only hold the ring positions and doorbells. Requests carry a tag, so many can be in flight and replies may come back out of order.

### Registers

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| $00:DD00 to $00:DD02 | MB\_REQ\_BASE | RW | 24-bit address of the request ring (256 entries × 16 bytes = 4 KB, 4 KB aligned) |
| $00:DD03 | MB\_REQ\_HEAD | RW | Next entry Horizon will write; writing it rings the I/O processor's doorbell |
| $00:DD04 | MB\_REQ\_TAIL | R | Next entry the I/O processor will read |
| $00:DD05 to $00:DD07 | MB\_RSP\_BASE | RW | 24-bit address of the response ring (same size and alignment) |
| $00:DD08 | MB\_RSP\_HEAD | R | Next entry the I/O processor will write |
| $00:DD09 | MB\_RSP\_TAIL | RW | Next entry Horizon will read; IOP in IRQ\_STATUS stays set while HEAD differs from TAIL |
| $00:DD0A | MB\_STATUS | R | 0 IOP\_READY (firmware running and rings accepted), 1 IOP\_ERROR |

A ring is empty when HEAD equals TAIL and full when HEAD + 1 equals TAIL.

### Message layout

| Byte | Field | Meaning |
| --- | --- | --- |
| 0 | OP | Operation; responses use OP + $80, events use $E0 to $EF |
| 1 | TAG | Chosen by Horizon, copied into the response |
| 2 to 3 | LEN | Buffer length in bytes |
| 4 to 6 | BUF | 24-bit buffer address in main RAM |
| 7 | FLAGS | Operation-specific |
| 8 to 11 | ARG0 | Operation-specific; in a response, the result (0 = OK, else an error code) |
| 12 to 15 | ARG1 | Operation-specific; in a response, the byte count or value |

### Operations (v1)

| OP | Name | Arguments | Response ARG1 |
| --- | --- | --- | --- |
| $01 | OPEN | BUF = path, FLAGS = 0 read, 1 write, 2 create, 3 append | File handle |
| $02 | CLOSE | ARG0 = handle | 0 |
| $03 | READ | ARG0 = handle, BUF and LEN = destination | Bytes read |
| $04 | WRITE | ARG0 = handle, BUF and LEN = source | Bytes written |
| $05 | SEEK | ARG0 = handle, ARG1 = offset | New position |
| $06 | STAT | BUF = path; result written back into BUF | Size |
| $07 | READDIR | BUF = path, LEN = output space; entries written back into BUF | Entries returned |
| $08 | MKDIR | BUF = path | 0 |
| $09 | DELETE | BUF = path | 0 |
| $0A | RENAME | BUF = "old\\0new" | 0 |
| $10 | LOAD | BUF = path, ARG0 = 24-bit destination address | Bytes loaded |
| $18 to $1A | CLASSIC\_MOUNT, CLASSIC\_EJECT, CLASSIC\_BOOT | Implemented in the firmware; layout in the comment block in `core/firmware/firmware.c` | |
| $1B | SYS\_RESTART | ARG0 = 0: reload Horizon from the card and restart the 65C816; 1: full restart (/atari.ini read again, classic images ejected, classic machine cold booted, then Horizon). The OK reply comes first; the 65C816 is reset once it has moved MB\_RSP\_TAIL past it (at most 500 ms later). Errors: $83 bad ARG0, 4 no Horizon on the card (no restart then) | 0 |
| $1C | SYS\_SYNC | none. Closes every mailbox file and classic disk image, unmounts the card; then the card may be removed or the power cut. Until the next restart every op below $1B answers $86 | Handles that were open |
| $1D | SYS\_TIME | ARG0 = the time Horizon knows, in seconds since 2000-01-01 00:00 (local: the clock the user set, or the last one saved, counting from start). The firmware counts on from it with its own millisecond timer, and FatFs stamps files with it (`get_fattime`, FF\_FS\_NORTC = 0); before it is given, files get the firmware's build date. Horizon sends it whenever `time_set` is called (at start, after the saved clock is loaded, and when the user sets the clock) | 0 |
| $1E | CLASSIC\_STATE | ARG0 = 5 (the cartridge; other values answer $83), BUF and LEN = where its path goes (zero-terminated, cut to LEN - 1; LEN 0: not written). Also reports a cartridge the firmware loaded by itself (`boot=ash` in /atari.ini, at power-on or a full restart): Horizon asks at start and reserves its banks | Size of the cartridge image in bytes, 0 = none |
| $20 | MOUNT | ARG0 = drive 1 to 8, BUF = ATR path, FLAGS bit 0 = read-only | 0 |
| $21 | UNMOUNT | ARG0 = drive | 0 |
| $30 | TIME | none | Seconds since 2000-01-01 |

Paths are FAT32 paths, UTF-8, zero-terminated. LOAD streams a whole file straight into RAM, for ROM images, cartridge images and programs. $40 to $5F are reserved for FujiNet sockets later.

### Events (I/O processor to Horizon, TAG = 0)

| OP | Name | Fields |
| --- | --- | --- |
| $E0 | KEY | ARG0 = USB HID usage, ARG1 bits 0 to 7 modifiers, bit 8 = 1 key down |
| $E1 | MOUSE | ARG0 bytes: dx, dy (signed), wheel; ARG1 = buttons |
| $E2 | GAMEPAD | ARG0 = pad number, ARG1 = buttons and directions |
| $E3 | MEDIA | ARG0 = 0 SD card removed, 1 inserted |

### Boot handshake

1. At power-on the I/O processor holds the 65C816 in reset, loads /SYSTEM/HORIZON.SYS to $01:0000 and writes a small reset stub with the vectors at $00:FF00 to $00:FFFF.
2. It releases the 65C816, whose reset stub jumps to $01:0000.
3. Horizon writes MB\_REQ\_BASE and MB\_RSP\_BASE, then waits for IOP\_READY.

## Open questions

None of these block the start of development; each is best answered by building and measuring.

- [ ] **Cache size and hit rate:** 2 KB or 4 KB for the 65C816, decided by block RAM left after a fresh resource count.
- [ ] **Turbo speed:** whether the 65C816 closes timing at 28.7 MHz on the Tang Nano 20K.
- [ ] **Chip state index lists:** the exact SV\_CHIP\_IDX layout for each chip, taken from the chip sources.
- [ ] **4 bpp desktop mode:** the blitter is 8 bpp only; either drop the 4 bpp mode or add 4 bpp support later.
- [ ] **I/O processor access to SDRAM:** confirm the PicoRV32's existing SDRAM path is fast enough for LOAD and READ into main RAM, or add a burst path.
- [ ] **Classic RAM in block RAM:** whether the classic 64 KB moves to block RAM to take load off the SDRAM arbiter, or stays in SDRAM as today.

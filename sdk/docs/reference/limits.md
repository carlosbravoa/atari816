# Limits (Horizon 0.18)

From horizon/README.md ("Current limits"), ABI.md and the sources.

| | |
| --- | --- |
| Program file | the o65 under 64 KB (0.28: the program's own data may follow it in the file); code + data + bss at most 65,280 bytes; zero page 256 bytes (ulib takes 38, ui.lib 38) |
| Memory | 64 KB banks only, no heap; 92 banks on 8 MB, 4 for the text screen, 88 for programs; the window system takes 6 contiguous banks, each window its bitmap (a power-of-two stride, contiguous banks) |
| Tasks | 16 task slots, ids 1-62 |
| Files | 4 open files in the whole system; paths at most 127 characters (absolute, after `.`/`..` are resolved) |
| Internet (0.22) | 4 URLs or connections in the whole system (handles 4-7); a URL at most 127 characters with its scheme; needs the PC link's gateway |
| Arguments | one string, 127 characters |
| Message ports | 16, 8 messages of 16 bytes each |
| Keyboard | 128 queued key events (console); 4 keys held at once plus modifiers (the I/O processor) |
| Windows | 16, counting the menu bar and an open menu; 32 queued events each |
| Menus | 254 bytes per window; 12 titles in the bar; the Desktop's Programs menu 16 entries |
| Window titles | 31 characters |
| Clipboard | 64 KB |
| Drag and drop strings | 127 characters |
| Screen | 640 x 360, 8 bpp; windows below the 16-line menu bar |
| Full screen (0.18) | one program at a time; 640 x 360 x 8, 640 x 360 x 4 or 320 x 180 x 8; stride a multiple of 16, at most 4096 bytes; at most 1024 rows; 16 raster table entries |
| Sprites (0.18, REV $0B) | 16 in the whole system; 8 bpp 16 x 16 or 16 x 32, 4 bpp up to 32 x 32 (x 2 with SPR_MAG); 512 on-screen pixels of sprites per line; in a window only while it has the focus and is not covered |
| Draw lists (0.18) | 128 records a call, 460,800 pixels a call; one list of a program runs at a time (the next call waits) |
| Palette entries (0.18) | 16-255 for programs (240), each held by one program at a time; 0-15 global |
| Terminal windows | at most 128 x 40 cells |
| Console | 78 x 29 characters; no colour escapes; lines longer than 78 wrap |
| Time | milliseconds since start; no wall clock (the board has none) |
| Shared libraries | none: link everything into the program |

Not available to programs (no syscall): interrupt code of their own (the raster table is the
kernel's), video modes other than the three above, sprite collision detection, the DACs at a
sample rate (Lau plays samples), hiding the pointer in a window or giving it a custom shape,
sockets / networking. (Horizon 0.15 added the joystick ports, SYS_JOY, and the focus events
WE_FOCUS / WE_UNFOCUS; 0.17 Lau; 0.18 full-screen mode, sprites, scrolling, raster tables,
draw lists, palette entries of programs and frame sync.)

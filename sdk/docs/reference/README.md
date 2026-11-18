# Programmer's reference

The interface between Horizon 0.18 (and 0.22's internet, 0.23's printing, 0.24's idle time) and its programs, reorganised by topic with an example
for each call. The source of truth is `horizon/ABI.md` (and the sources it names);
`make -C sdk check` compares this reference with `horizon/user/horizon.inc`, `ui.inc` and
the kernel's syscall table, and assembles every example.

| Page | Contents |
| --- | --- |
| [program.md](program.md) | Program format, building, memory model (banks, direct page), register widths, calling convention, start conditions, exit, faults |
| [system.md](system.md) | Error codes; syscalls for tasks, time, memory, the console, the keyboard (console programs), message ports, restart / shut down, settings |
| [files.md](files.md) | Files and folders |
| [internet.md](internet.md) | (0.22) The internet through the PC link: URLs as files, tcp:// and tls:// connections, WE_NET, the error codes |
| [windows.md](windows.md) | The window system: windows, events (focus, WE_VBL), timer, menus, pointer, clipboard, drag and drop, palette (entries of your own), terminals |
| [drawing.md](drawing.md) | win_draw: fills, frames, lines, text, blits (plain, keyed, with stride), copy; fonts; the system palette; win_draw or a draw list |
| [controls.md](controls.md) | The controls library (ui.lib): buttons, fields, lists, scroll bars, alerts, the file dialog |
| [ulib.md](ulib.md) | The user library and the macros of horizon.inc |
| [sound.md](sound.md) | beep, sound_write, POKEY 2 and the DACs; samples on Lau; the sound volume |
| [classic.md](classic.md) | The classic Atari: mount, eject, boot, show; (0.23) Run in Atari, the folder disk |
| [printing.md](printing.md) | (0.23) Printing: `/PRN:NAME` jobs, watching for new ones, PDFs on the PC |
| [games.md](games.md) | Horizon 0.18, the games round: frame sync (vsync, frame, WE_VBL), palette entries, Marga's sprites, full-screen mode (own framebuffer, scrolling with wrap and split, raster table), draw lists |
| [hardware.md](hardware.md) | The hardware (video, blitter, sound, input, timers) and what programs can reach of it |
| [performance.md](performance.md) | Measured costs: CPU, syscalls, drawing, board against emulator |
| [game-patterns.md](game-patterns.md) | The game loop (frame-synchronous or timer), full screen with scrolling and sprites, windowed games with draw lists and sprites, input, art, sound effects |
| [limits.md](limits.md) | Limits |

## All syscalls

| # | Name | Constant | Page |
| --- | --- | --- | --- |
| $00 | exit | SYS_EXIT | [system](system.md) |
| $01 | yield | SYS_YIELD | [system](system.md) |
| $02 | sleep | SYS_SLEEP | [system](system.md) |
| $03 | getpid | SYS_GETPID | [system](system.md) |
| $04 | uptime | SYS_UPTIME | [system](system.md) |
| $05 | putc | SYS_PUTC | [system](system.md) |
| $06 | puts | SYS_PUTS | [system](system.md) |
| $07 | con_size | SYS_CSIZE | [system](system.md) |
| $08 | chdir | SYS_CHDIR | [files](files.md) |
| $09 | getcwd | SYS_GETCWD | [files](files.md) |
| $0A | restart | SYS_RESTART | [system](system.md) |
| $0B | sync | SYS_SYNC | [system](system.md) |
| $0C | sysreq | SYS_SYSREQ | [system](system.md) |
| $0D | time_get | SYS_TGET | [system](system.md) |
| $0E | time_set | SYS_TSET | [system](system.md) |
| $0F | vsync | SYS_VSYNC | [games](games.md) |
| $10 | bank_alloc | SYS_BALLOC | [system](system.md) |
| $11 | bank_free | SYS_BFREE | [system](system.md) |
| $12 | mem_info | SYS_MINFO | [system](system.md) |
| $20 | open | SYS_OPEN | [files](files.md) |
| $21 | close | SYS_CLOSE | [files](files.md) |
| $22 | read | SYS_READ | [files](files.md) |
| $23 | write | SYS_WRITE | [files](files.md) |
| $24 | seek | SYS_SEEK | [files](files.md) |
| $25 | stat | SYS_STAT | [files](files.md) |
| $26 | readdir | SYS_READDIR | [files](files.md) |
| $27 | delete | SYS_DELETE | [files](files.md) |
| $28 | mkdir | SYS_MKDIR | [files](files.md) |
| $29 | rename | SYS_RENAME | [files](files.md) |
| $30 | spawn | SYS_SPAWN | [system](system.md) |
| $31 | wait | SYS_WAIT | [system](system.md) |
| $32 | kill | SYS_KILL | [system](system.md) |
| $33 | task_info | SYS_TINFO | [system](system.md) |
| $34 | task_single | SYS_SINGLE | [system](system.md) |
| $40 | port_create | SYS_PCREATE | [system](system.md) |
| $41 | send | SYS_SEND | [system](system.md) |
| $42 | recv | SYS_RECV | [system](system.md) |
| $43 | port_close | SYS_PCLOSE | [system](system.md) |
| $50 | input_claim | SYS_ICLAIM | [system](system.md) |
| $51 | input_read | SYS_IREAD | [system](system.md) |
| $52 | input_release | SYS_IRELEASE | [system](system.md) |
| $53 | input_lend | SYS_ILEND | [system](system.md) |
| $54 | input_poll | SYS_IPOLL | [system](system.md) |
| $55 | joystick | SYS_JOY | [system](system.md) |
| $5F | mouse_inject | SYS_MINJECT | [system](system.md) |
| $60 | classic_show | SYS_CLASSIC | [classic](classic.md) |
| $61 | classic_mount | SYS_CMOUNT | [classic](classic.md) |
| $62 | classic_eject | SYS_CEJECT | [classic](classic.md) |
| $63 | classic_boot | SYS_CBOOT | [classic](classic.md) |
| $64 | classic_query | SYS_CQUERY | [classic](classic.md) |
| $65 | beep | SYS_BEEP | [sound](sound.md) |
| $66 | sound_write | SYS_SNDW | [sound](sound.md) |
| $67 | sound_chime | SYS_CHIME | [sound](sound.md) |
| $68 | sample_play | SYS_SPLAY | [sound](sound.md) |
| $69 | sample_stop | SYS_SSTOP | [sound](sound.md) |
| $6A | sample_stat | SYS_SSTAT | [sound](sound.md) |
| $6B | sample_set | SYS_SSET | [sound](sound.md) |
| $70 | ws_start | SYS_WSSTART | [windows](windows.md) |
| $71 | ws_stop | SYS_WSSTOP | [windows](windows.md) |
| $72 | win_open | SYS_WOPEN | [windows](windows.md) |
| $73 | win_close | SYS_WCLOSE | [windows](windows.md) |
| $74 | win_draw | SYS_WDRAW | [drawing](drawing.md) |
| $75 | win_event | SYS_WEVENT | [windows](windows.md) |
| $76 | win_twidth | SYS_WTWIDTH | [drawing](drawing.md) |
| $77 | ws_sync | SYS_WSSYNC | [windows](windows.md) |
| $78 | win_move | SYS_WMOVE | [windows](windows.md) |
| $79 | ws_redraw | SYS_WSREDRAW | [windows](windows.md) |
| $7A | ws_stats | SYS_WSSTATS | [windows](windows.md) |
| $7B | ws_config | SYS_WSCONFIG | [windows](windows.md) |
| $7C | win_timer | SYS_WTIMER | [windows](windows.md) |
| $7D | win_menu | SYS_WMENU | [windows](windows.md) |
| $7E | ws_status | SYS_WSTATUS | [windows](windows.md) |
| $7F | ws_term | SYS_WTERM | [windows](windows.md) |
| $80 | clip_put | SYS_CLPUT | [windows](windows.md) |
| $81 | clip_get | SYS_CLGET | [windows](windows.md) |
| $82 | win_info | SYS_WINFO | [windows](windows.md) |
| $83 | win_at | SYS_WINAT | [windows](windows.md) |
| $84 | win_drop | SYS_WDROP | [windows](windows.md) |
| $85 | win_dropget | SYS_WDROPGET | [windows](windows.md) |
| $86 | ws_palette | SYS_WSPAL | [windows](windows.md) |
| $87 | setting | SYS_SETTING | [system](system.md) |
| $88 | win_title | SYS_WTITLE | [windows](windows.md) |
| $89 | ws_pointer | SYS_WPTR | [windows](windows.md) |
| $8A | ws_mouse | SYS_WMOUSE | [windows](windows.md) |
| $8B | ws_hold | SYS_WSHOLD | [windows](windows.md) |
| $8C | win_mstate | SYS_WMSTATE | [windows](windows.md) |
| $8D | ws_closeall | SYS_WSCLOSEALL | [windows](windows.md) |
| $8E | win_geom | SYS_WGEOM | [windows](windows.md) |
| $8F | task_name | SYS_TNAME | [windows](windows.md) |
| $90 | win_popup | SYS_WPOPUP | [windows](windows.md) |
| $91 | spr_alloc | SYS_SPRALLOC | [games](games.md) |
| $92 | spr_free | SYS_SPRFREE | [games](games.md) |
| $93 | spr_set | SYS_SPRSET | [games](games.md) |
| $94 | spr_move | SYS_SPRMOVE | [games](games.md) |
| $95 | spr_show | SYS_SPRSHOW | [games](games.md) |
| $96 | fs_enter | SYS_FSENTER | [games](games.md) |
| $97 | fs_leave | SYS_FSLEAVE | [games](games.md) |
| $98 | fs_scroll | SYS_FSSCROLL | [games](games.md) |
| $99 | fs_raster | SYS_FSRASTER | [games](games.md) |
| $9A | pal_set | SYS_PALSET | [games](games.md) |
| $9B | pal_alloc | SYS_PALALLOC | [games](games.md) |
| $9C | draw_list | SYS_DRAWLIST | [games](games.md) |
| $9D | list_wait | SYS_LISTWAIT | [games](games.md) |
| $9E | frame | SYS_FRAME | [games](games.md) |
| $9F | win_vbl | SYS_WINVBL | [games](games.md) |
| $A1 | sheet_new | SYS_SHEETNEW | [games](games.md) |
| $A2 | sheet_free | SYS_SHEETFREE | [games](games.md) |
| $A3 | sheet_draw | SYS_SHEETDRAW | [games](games.md) |

This table is checked too: `make check` fails if a number, a name or a constant here
disagrees with the sources.

; kdata.s - kernel variables in bank $01 (BSS: cleared at boot, never assumed zero by the loader).
; Per-task arrays are indexed by slot*2 (one word per slot) unless noted.

        .segment "BSS"

; ---- task control blocks ----
t_state:    .res    NSLOT*2     ; TS_*
t_id:       .res    NSLOT*2     ; FREDDIE owner id 1..62
t_prio:     .res    NSLOT*2     ; 0 (highest) .. 3
t_slice:    .res    NSLOT*2     ; ticks left in the time slice
t_wake_lo:  .res    NSLOT*2     ; wake-up tick (W_SLEEP)
t_wake_hi:  .res    NSLOT*2
t_wreason:  .res    NSLOT*2     ; W_* while BLOCKED
t_wobj:     .res    NSLOT*2     ; object waited for (port, child slot*2, ...)
t_exit:     .res    NSLOT*2     ; exit code
t_parent:   .res    NSLOT*2     ; parent slot*2 or NONE
t_killed:   .res    NSLOT*2     ; non-zero: exit with t_killcode at the next return to user
t_killcode: .res    NSLOT*2
t_name:     .res    NSLOT*8     ; 8 characters, space padded (indexed by slot*8)
; saved user context
t_a:        .res    NSLOT*2
t_x:        .res    NSLOT*2
t_y:        .res    NSLOT*2
t_s:        .res    NSLOT*2     ; S as before the entry frame (frame popped)
t_d:        .res    NSLOT*2
t_p:        .res    NSLOT*2     ; low byte
t_pc:       .res    NSLOT*2
t_pbr:      .res    NSLOT*2     ; low byte
t_dbr:      .res    NSLOT*2     ; low byte
; memory
t_wbank:    .res    NSLOT*2     ; window bank (bank 0 $0000-$7FFF)
t_cbank:    .res    NSLOT*2     ; code/data bank
t_tbank:    .res    NSLOT*2     ; loader scratch bank (kernel owned) or 0
; kernel context
t_ksp:      .res    NSLOT*2     ; saved kernel S while not running
; mailbox
t_iodone:   .res    NSLOT*2     ; set when the answer is in t_rsp
t_msg:      .res    NSLOT*16    ; request being built (indexed by slot*16)
t_rsp:      .res    NSLOT*16    ; answer
; spawn
t_wres:     .res    NSLOT*2     ; result posted by a loading child to its parent ($FFFF = pending)
t_arglen:   .res    NSLOT*2     ; length of the argument string
t_lender:   .res    NSLOT*2     ; task that lent this task the keyboard (slot*2), NONE
t_lbrk:     .res    NSLOT*2     ; non-zero: ctrl-C kills this borrower (break key)
t_iobuf:    .res    NSLOT*256   ; path (+0) and a scratch copy (+128) for the I/O processor (indexed by slot*256)

; ---- banks ----
bank_st:    .res    256         ; BK_FREE, BK_NONE, BK_KERNEL or owner task id

; ---- files ----
NFILE = 8                   ; (0.22) 0-3 files, 4-7 streams (URLs, connections)
fh_owner:   .res    NFILE*2     ; slot*2 + 1 of the owner, 0 = closed

; ---- ports ----
NPORT  = 16
PQLEN  = 8
p_owner:    .res    NPORT*2     ; slot*2 + 1, 0 = free
p_head:     .res    NPORT*2     ; next message to receive (0..7)
p_count:    .res    NPORT*2
p_queue:    .res    NPORT*PQLEN*16

; ---- input ----
KQLEN  = 128
in_owner:   .res    2           ; slot*2 + 1 of the claiming task, 0 = none
kq_head:    .res    2
kq_count:   .res    2
kq_usage:   .res    KQLEN*2
kq_mods:    .res    KQLEN*2     ; modifiers | down << 8 (mouse: x / wheel)
kq_y:       .res    KQLEN*2     ; mouse: y

kargs:      .res    128         ; spawn arguments being copied
kpath:      .res    128
        .export kpath               ; (0.31: in build/horizon.lbl, for tests/cardreq.py)
kraw:       .res    128
t_cwd:      .res    NSLOT*128   ; current directory of each task (indexed by slot*128)         ; path being worked on (spawn, file syscalls)
kblk:       .res    18          ; syscall parameter block copied from user memory
mvn_op:     .res    4           ; MVN dst,src / RTS, patched by kmemcpy

con_owner:  .res    2           ; slot*2 + 1 of the task holding the console, 0 = free
; ---- classic machine ----
cls_on:     .res    2           ; the classic machine has screen and keyboard
cls_done:   .res    2           ; the system key was pressed
sw_on:      .res    2           ; swallowing key events (see input.s)
sw_t0:      .res    2           ; tick when the swallowing started
sw_keys:    .res    16          ; usages reported down meanwhile (0 = free)

; ---- mouse ----
ms_x:       .res    2
ms_y:       .res    2
ms_btn:     .res    2           ; buttons last reported
ms_dx:      .res    2           ; the event being handled
ms_dy:      .res    2
ms_dw:      .res    2
ms_nb:      .res    2

; ---- sound, hardware ----
; (0.30) k_rev (SYS_REV) is in the video-state block (vstate.s)
snd_left:   .res    2           ; ticks left of the beep playing

; ---- window system ----
ws_on:      .res    2
ws_quit:    .res    2
ws_owner:   .res    2           ; slot*2 of the task that started it
ws_sbank:   .res    2           ; first of the 6 screen banks
ws_top:     .res    2           ; window*2 on top (the focus), NONE
ws_scr:     .res    16          ; the screen surface
w_used:     .res    16*2
w_fl:       .res    16*2        ; WF_* flags
w_cx:       .res    16*2        ; content origin in the window, bottom margin
w_cy:       .res    16*2
w_cb:       .res    16*2
w_stale:    .res    16*2        ; drawn on the screen directly: its bitmap is behind
wo_x:       .res    2           ; win_target: the offset of the drawing surface
wo_y:       .res    2
wo_dir:     .res    2           ; win_target: 1 = on the screen (no damage)
wd_ox:      .res    2           ; win_draw: content -> surface offset
wd_oy:      .res    2
ws_nodir:   .res    2           ; ws_config bit 2: no direct drawing
vs_w:       .res    2
sy_w:       .res    2
w_tper:     .res    16*2        ; timer events: period, countdown (ticks), due
w_tcnt:     .res    16*2
w_tdue:     .res    16*2
w_net:      .res    16*2        ; (0.22) WE_NET due: bit n = stream handle n has news
ws_tflag:   .res    2           ; a timer is due
ws_wheel:   .res    2           ; wheel steps not yet delivered
wk_n:       .res    2           ; keys for the window manager
wk_h:       .res    2
wk_u:       .res    16*2
wk_m:       .res    16*2
cap_w:      .res    2           ; window that got the press (gets the release)
cap_lx:     .res    2           ; the pointer when its last motion event went out
cap_ly:     .res    2
hov_w:      .res    2           ; WF_HOVER window under the pointer (gets motion), NONE
hov_lx:     .res    2           ; the pointer when the hover window was last looked for
hov_ly:     .res    2
rs_w:       .res    2           ; window being resized, NONE
rs_ox:      .res    2
rs_oy:      .res    2
rs_lx:      .res    2
rs_ly:      .res    2
sa_x:       .res    2           ; surf_alloc / win_resize
sa_ow:      .res    2
sa_oh:      .res    2
sa_os:      .res    16          ; the old surface descriptor
mb_w:       .res    2           ; the menu bar window, NONE
t_term:     .res    NSLOT*2     ; per task: its terminal window*2 | $8000, 0 = none
t_det:      .res    NSLOT*2     ; per task: spawned detached (SP_DETACH)
clip_bank:  .res    2           ; the clipboard's bank (0: not yet)
clip_len:   .res    2
ms_speed:   .res    2           ; settings: mouse speed 1-4, beep volume, key repeat
snd_vol:    .res    2
smp_vol:    .res    2
cart_nb:    .res    2           ; (0.18) banks from CART_B0 kept for the attached cartridge           ; (0.18) setting 4: the sound volume (Lau's master), 0-15
rep_delay:  .res    2
rep_rate:   .res    2
in_idle:    .res    2           ; (0.24) setting 6: seconds without input (ws14.s clk_tick)
sv_delay:   .res    2           ; (0.24) setting 5: the screen saver's delay in seconds, 0 = off
rep_u:      .res    2           ; the key repeating (0 none), its modifiers, countdown
rep_m:      .res    2
rep_n:      .res    2
kren:       .res    256         ; rename: "old\0new" (one rename at a time)
kren_busy:  .res    2
kren_n:     .res    2
tm_bank:    .res    16*2        ; per terminal window: state bank, size, cursor, modes
tm_cols:    .res    16*2
tm_rows:    .res    16*2
tm_cx:      .res    16*2
tm_cy:      .res    16*2
tm_inv:     .res    16*2
tm_coff:    .res    16*2
tm_esc:     .res    16*2
tm_fg:      .res    16*2        ; the task that gets its keys (slot*2), NONE
tm_kn:      .res    16*2
tm_kh:      .res    16*2
tm_w:       .res    2           ; the terminal being written
tm_poll:    .res    2           ; (0.22) term_iread called for input_poll: never block
tm_ch:      .res    2           ; one character and its terminator
tm_c:       .res    2
tm_t:       .res    2
tm_si:      .res    2
tm_top:     .res    16*2        ; per terminal: the cells' ring (physical row of row 0)
tm_ps:      .res    16*2        ; rows scrolled since the last flush (pixels not moved yet)
tm_d0:      .res    16*2        ; rows to draw at the flush ($FFFF: none) .. tm_d1
tm_d1:      .res    16*2
tm_dcx:     .res    16*2        ; the cursor as drawn (tm_dcy = NONE: not drawn)
tm_dcy:     .res    16*2
tm_pw:      .res    16*2        ; a flush is due
tm_lt:      .res    16*2        ; the tick of its last output, of its last flush
tm_lf:      .res    16*2
tm_pend:    .res    2           ; some terminal has a flush due
tm_r:       .res    2           ; flush: row, column, run start, attribute
tm_col:     .res    2
tm_rs:      .res    2
tm_at:      .res    2
tm_ri:      .res    2
tm_rb:      .res    130         ; flush: one run of characters
ws_hl:      .res    NSLOT*2     ; ws_hold: per task slot, 1 = holds the screen
ws_hn:      .res    2           ; tasks holding
ws_hcnt:    .res    2           ; ticks the compositor waited for them
ws_thr:     .res    2           ; the WS thread's slot*2
dd_w:       .res    2           ; the open drop-down's window, NONE
mb_n:       .res    2           ; menus in the bar
mb_x:       .res    2
mb_back:    .res    2
mb_src:     .res    2
mb_m:       .res    2
mb_win:     .res    13*2        ; per bar entry: window, menu index, title, x range
mb_idx:     .res    13*2        ; (0.15: entry 12 is the pop-up menu, MB_POP)
mb_off:     .res    13*2
mb_x0:      .res    13*2
mb_x1:      .res    13*2
mn_open:    .res    2           ; the open bar entry, NONE
mn_sel:     .res    2           ; the highlighted item, NONE
mn_sticky:  .res    2
mn_kill:    .res    2
mn_items:   .res    2
mn_n:       .res    2
mn_wd:      .res    2
mn_i:       .res    2
mn_y:       .res    2
mn_lx:      .res    2
mn_ly:      .res    2
it_st:      .res    2           ; item_split: the item's state byte, the address of its TAB
it_tab:     .res    2
km_alt:     .res    2           ; an Alt key went down, no other key since (keyboard menus)
ws_mods:    .res    2           ; the HID modifiers << 8 (button and motion events' c)
ws_stat:    .res    32          ; the status text (ws_status)
w_owner:    .res    16*2
w_x:        .res    16*2
w_y:        .res    16*2
w_w:        .res    16*2        ; outer size
w_h:        .res    16*2
w_nb:       .res    16*2        ; banks of its bitmap
w_qh:       .res    16*2
w_qn:       .res    16*2
w_surf:     .res    16*16
w_title:    .res    16*32
w_ev:       .res    16*32*8     ; event queues: {type, a, b, c}
z_list:     .res    16*2        ; windows bottom to top
z_n:        .res    2
d_n:        .res    2           ; damage rectangles * 2
d_x0:       .res    8*2
d_y0:       .res    8*2
d_x1:       .res    8*2
d_y1:       .res    8*2
cr_x0:      .res    2           ; compositor
cr_y0:      .res    2
cr_x1:      .res    2
cr_y1:      .res    2
cr_y:       .res    2
cr_i:       .res    2
cr_wy:      .res    2
cr_xs:      .res    2
cr_ye:      .res    2           ; band end (exclusive)
cr_x:       .res    2           ; segment
cr_xe:      .res    2
cr_w:       .res    2           ; its window*2, NONE = the desktop
cr_l:       .res    2           ; line (software path)
bl_on:      .res    2           ; the blitter is used (REV $08 and not turned off)
bl_mode:    .res    2           ; 1: the compositor sleeps on the blitter interrupt
bl_force:   .res    2           ; ws_config: bit 0 blitter off, bit 1 interrupt wait
bl_done:    .res    2
ws_dtile:   .res    642         ; the desktop dither row (blitter source)
wb_n:       .res    2           ; button changes for the window manager
wb_h:       .res    2
wb_last:    .res    2
wb_btn:     .res    8*2
wb_x:       .res    8*2
wb_y:       .res    8*2
wm_btn:     .res    2
wm_x:       .res    2
wm_y:       .res    2
drag_w:     .res    2           ; window*2 being dragged, NONE
drag_dx:    .res    2
drag_dy:    .res    2
drag_lx:    .res    2
drag_ly:    .res    2
drag_nx:    .res    2
drag_ny:    .res    2
ws_t0:      .res    4
ws_busy:    .res    2           ; ws_paint running
ws_last:    .res    4

; ---- screen ----
scr_ctrl:   .res    2           ; NV_CTRL while the desktop is shown
scr_on:     .res    2
scr_col:    .res    2
scr_row:    .res    2           ; cursor row in the window (0-44)
scr_top:    .res    2           ; first text row shown (0-45)
scr_coop:   .res    2
scr_hold:   .res    2
scr_esc:    .res    2           ; escape sequence state (0 none)
scr_invoff: .res    2           ; 0 normal, 32 inverse video (offset into the nibble tables)
scr_curoff: .res    2           ; 1: text cursor off (ESC f)
scr_owner:  .res    2           ; slot*2+1 of the task that last set ESC f / ESC p           ; cursor hidden by scr_hide (until scr_show)           ; 1: long operations may service interrupts and yield
scr_i:      .res    2
scr_n:      .res    2
scr_m:      .res    2
scr_src:    .res    4
scr_dst:    .res    4

; ---- 0.14 ----
ws_mbank:   .res    2           ; the window system's menu bank (menus, drops, the Windows menu)
w_st:       .res    16*2        ; WS_MIN 1 minimized (out of the z list), WS_MAX 2 maximized
w_rx:       .res    16*2        ; the geometry before maximizing (outer x, y, w, h)
w_ry:       .res    16*2
w_rw:       .res    16*2
w_rh:       .res    16*2
tb_w:       .res    2           ; the window whose title was last pressed, and when (ticks)
tb_t:       .res    2
mb_sx:      .res    2           ; the status text's left end in the bar
mb_sys:     .res    2           ; the bar shows system menus (then Windows, a divider, the name)
mb_nx:      .res    2           ; the program name's place in the bar (0: none), its end
mb_nx1:     .res    2
mb_name:    .res    18          ; the focused program's name, as drawn in the bar
mn_noev:    .res    2           ; (sys_wmenu reopening a menu: no WE_MENUOPEN)
mn_re:      .res    2           ; the bar entry to reopen, its sticky state
mn_rs:      .res    2
wl_n:       .res    2           ; the Windows menu: its items' windows
wl_ids:     .res    16*2
t_dname:    .res    NSLOT*16    ; per task: its display name (task_name), "" = from t_name
clk_sec:    .res    4           ; the clock: seconds since 2000-01-01 00:00 (time_get)
clk_sub:    .res    2           ; ticks into the second
clk_st:     .res    2           ; 0 not set, 1 provisional (a saved value), 2 set
cb_done:    .res    2           ; (0.19) the boot cartridge was asked for (the first exec)
next_id:    .res    2           ; next task id to try
rr_pos:     .res    2           ; round robin position (slot*2)
; ---- 0.15 ----
wm_nbtn:    .res    2           ; wm_button: the buttons now (kg_e is reused meanwhile)
pop_w:      .res    2           ; win_popup: its window, the point, the answer, the caller
pop_x:      .res    2
pop_y:      .res    2
pop_res:    .res    2
pop_task:   .res    2           ; (slot*2, NONE: no pop-up open)
fo_w:       .res    2           ; the window that got WE_FOCUS last (NONE)
hk_x:       .res    2
hk_kt:      .res    2           ; (wm_key) the key while the window manager looks at it
hk_ku:      .res    2
hk_u:       .res    8*2         ; keys held by a window: usage, window (NONE free, HK_GONE)
hk_w:       .res    8*2
snd_own:    .res    9*2         ; sound owners (slot*2 + 1, 0 none): channels 1-4, the
                                ; rest (AUDCTL, SKCTL, ...), DACs 0-3
snd_sh:     .res    $14*2       ; the registers as programs wrote them (register * 2)
ch_n:       .res    2           ; the chime: its channel's AUDF register (NONE: none playing)
ch_t:       .res    2           ; its tick
ch_f:       .res    2           ; its notes (AUDF of note 1, note 2)
ch_pk:      .res    2           ; its peak volume
ch_amask:   .res    2           ; AUDCTL without the bits that change its channel
opl_owner:  .res    2           ; (REV $0C) OPL2 owner (slot*2 + 1, 0 = none)
opl_bsh:    .res    12          ; (0.27) the last values written to $B0-$B8 and $BD (bytes 0-9)
vs_armed:   .res    2           ; vsync: a vertical blank is awaited
vs_frame:   .res    2           ; vertical blanks waited for
au_own:     .res    8*2         ; (0.17) Lau voices: owner (slot*2 + 1, 0 none)
au_b0:      .res    8*2         ;   the physical banks its sample lies in: first, last
au_b1:      .res    8*2
au_seq:     .res    8*2         ;   when it was started (au_cnt then)
au_cnt:     .res    2
au_t:       .res    4
au_blk:     .res    16          ;   sample_play's block
au_keep:    .res    2           ; (0.26) voices started with SPF_KEEP: they play on while the classic Atari shows
mt_own:     .res    2           ; (0.26) the music timer (TIMER1): its owner (slot*2 + 1, 0 = off)
mt_port:    .res    2           ;   the port its ticks go to (port*2)
mt_cnt:     .res    2           ;   expiries since it started
mt_gen:     .res    2           ;   + 1 at every start: byte 1 of its messages
mt_per:     .res    4           ;   the period (us), its half
mt_half:    .res    4
mt_due:     .res    4           ;   UPTIME when the next one is due
joy_tx:     .res    2           ; joystick test aid: directions, triggers ORed in
joy_ty:     .res    2
bss_end:

; ---- past the video-state block ($01:F400): BSS2, cleared at boot ----
        .segment "BSS2"
t_args:     .res    NSLOT*128   ; argument string, copied to the top of the window (slot*128)
cl_names:   .res    6*128       ; mounted classic items: D1:-D4:, executable, cartridge

; kfar.s - (0.18) the bank $01 side of the second code segment (k2.s, run from bank 0):
; the bank $01 routines it may call, as JSL / RTL wrappers, and the variables it reads. k2.s is
; its own assembly unit, so it sees only what is exported here: a JSR from bank 0 to a bank $01
; label would go to bank 0 (ca65 cuts the address to 16 bits); imported as far, such a JSR is an
; assembly error, and only these wrappers can be called (with JSL). Each keeps what its routine
; keeps.

        .export f_set_ok: far, f_set_err: far, f_k_block: far, f_win_arg: far, f_win_visible: far, f_damage: far
        .export f_damage_all: far, f_win_target: far, f_bl_wait: far, f_bl_flush: far, f_uaccess: far, f_wev_push: far
        .export f_nv_ctrl: far, f_win_minimize: far, f_wm_motx: far, f_ws_desk_mode: far, f_irq_poll: far, f_vs_arm: far
        .export f_ws_paint_req: far
f_set_ok:       jsr     set_ok
                rtl
f_set_err:      jsr     set_err
                rtl
f_k_block:      jsr     k_block
                rtl
f_win_arg:      jsr     win_arg
                rtl
f_win_visible:  jsr     win_visible
                rtl
f_damage:       jsr     damage
                rtl
f_damage_all:   jsr     damage_all
                rtl
f_win_target:   jsr     win_target
                rtl
f_bl_wait:      jsr     bl_wait
                rtl
f_bl_flush:     jsr     bl_flush
                rtl
f_uaccess:      jsr     uaccess
                rtl
f_wev_push:     jsr     wev_push
                rtl
f_nv_ctrl:      jsr     nv_ctrl
                rtl
f_win_minimize: jsr     win_min
                rtl
f_wm_motx:      jsr     wm_motx
                rtl
f_ws_desk_mode: jsr     ws_desk_mode
                rtl
f_irq_poll:     jsr     irq_poll
                rtl
f_vs_arm:       jsr     vs_arm
                rtl
f_ws_paint_req: lda     #W_WS                   ; the window-system thread goes round its loop
                ldy     #0
                jsr     k_wake_all
                rtl

; the variables (bank $01, absolute: k2.s reads them with DBR = $01 as usual)
        .export t_id, t_a, t_x, t_y, t_wbank, t_killed, bank_st, k_rev
        .export ws_on, cls_on, w_used, w_fl, w_owner, w_x, w_y, w_cx
        .export w_cy, w_st, w_qn, ws_palette, vs_pal, vs_seq, vs_frame, vs_stride
        .export vs_base, bl_on, fo_w, ms_x, ms_y, scr_ctrl, wo_x, wo_y
        .export wo_dir, wm_x, wm_y, wm_btn, wm_nbtn, ws_mods, cap_w, ws_mbank, ws_scr

; what k2.s keeps that bank $01 reads
        .import fs_act, ls_task

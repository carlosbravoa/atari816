; k2.inc - (0.18) what the second code segment (k2.s) sees of bank $01: the wrappers of
; kfar.s (call them with JSL) and the variables (read with DBR = $01, absolute).
        .import f_set_ok: far, f_set_err: far, f_k_block: far, f_win_arg: far, f_win_visible: far, f_damage: far
        .import f_damage_all: far, f_win_target: far, f_bl_wait: far, f_bl_flush: far, f_uaccess: far, f_wev_push: far
        .import f_nv_ctrl: far, f_win_minimize: far, f_wm_motx: far, f_ws_desk_mode: far, f_irq_poll: far, f_vs_arm: far
        .import f_ws_paint_req: far
        .import t_id, t_a, t_x, t_y, t_wbank, t_killed, bank_st, k_rev
        .import ws_on, cls_on, w_used, w_fl, w_owner, w_x, w_y, w_cx
        .import w_cy, w_st, w_qn, ws_palette, vs_pal, vs_seq, vs_frame, vs_stride
        .import vs_base, bl_on, fo_w, ms_x, ms_y, scr_ctrl, wo_x, wo_y
        .import wo_dir, wm_x, wm_y, wm_btn, wm_nbtn, ws_mods, cap_w, ws_mbank, ws_scr
        .export fs_act, ls_task, fs_on

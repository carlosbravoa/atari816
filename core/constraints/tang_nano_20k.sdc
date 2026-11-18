# Tang Nano 20K timing constraints
# sys_clk: 27 MHz onboard oscillator (pin 4, LPLL1_T_in, Bank 7)
create_clock -name sys_clk -period 37.037 [get_ports {sys_clk}]

# clk_5x: Phase A 720-line freq-lock — 286.875 MHz from rpll_287m (cascaded off clk_108m). HDMI 5x.
create_clock -name clk_5x -period 2.7887 [get_nets {clk_5x}]

# clk_pix: Phase A 720-line freq-lock — 57.375 MHz CLKDIV output (286.875 ÷ 5 = 2*clk_core).
# Custom 1216x786 (active 1056x720, integer 3x) locked to the Atari frame.
create_clock -name clk_pix -period 13.943 -waveform {0 6.971} [get_pins {clkdiv_hdmi/CLKOUT}]
# Require 1 ns of setup margin on clk_pix (P&R only optimizes until constraints barely
# pass; without this, unrelated source changes can land the TMDS path at ~0 ns slack).
set_clock_uncertainty -setup -from [get_clocks {clk_pix}] -to [get_clocks {clk_pix}] 1.0

# (clk_usb, 12 MHz, removed with the USB-HID host: the PLL output has no load now.)

# clk_core: 54 MHz CLKDIV output (216 MHz ÷ 4) — Atari core + SDRAM arbiter + iosys CDC.
# Previously UNCONSTRAINED, so P&R never closed timing on this domain (achievable Fmax
# was only ~43 MHz vs the 54 MHz it is actually clocked at). Constrain it so the tool
# optimizes these paths and reports the true critical path.
# clk_108m: 114.75 MHz PLL output, common source of clk_core and clk_mem. Defining
# clk_core/clk_mem as generated clocks from it lets STA analyse the 2:1 synchronous
# clk_core<->clk_mem crossing (otherwise TA1117: relationship cannot be calculated and
# the whole SDRAM datapath crossing is unanalysed).
create_clock -name clk_108m -period 8.7146 [get_pins {pll_core_inst/rpll_inst/CLKOUT}]
create_generated_clock -name clk_core -source [get_pins {pll_core_inst/rpll_inst/CLKOUT}] -divide_by 4 [get_pins {clkdiv_core/CLKOUT}]

# clk_mem: 57.375 MHz (114.75 ÷ 2) — SDRAM controller. 2:1 synchronous with clk_core (same
# clk_108m source) — kept in the SAME clock group so the tool analyses the crossing.
create_generated_clock -name clk_mem -source [get_pins {pll_core_inst/rpll_inst/CLKOUT}] -divide_by 2 [get_pins {clkdiv_mem/CLKOUT}]

# Treat system clock, USB clock, core+mem clocks, and HDMI clocks as asynchronous clock groups
set_clock_groups -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks {clk_pix clk_5x}] -group [get_clocks {clk_108m clk_core clk_mem}]

# Extra visibility in the P&R timing report: the TMDS/pixel domain (history of landing at
# ~0 ns slack) and the clk_core<->clk_mem SDRAM crossing (history of being unanalysed).
# Check these after every build — NEVER flash a bitstream whose report shows negative slack.
report_timing -setup -from_clock [get_clocks {clk_pix}] -to_clock [get_clocks {clk_pix}] -max_paths 50
report_timing -setup -from_clock [get_clocks {clk_core}] -to_clock [get_clocks {clk_mem}] -max_paths 30
report_timing -setup -from_clock [get_clocks {clk_mem}] -to_clock [get_clocks {clk_core}] -max_paths 30
report_timing -setup -from_clock [get_clocks {clk_core}] -to_clock [get_clocks {clk_core}] -max_paths 40

# 65C816: the microcode ROM output register and the CPU registers only change on a CPU
# clock enable, and the bus FSM (a816_sys) never gives two enables in consecutive clk_core
# cycles (S_A always sits between). So microcode -> CPU register paths have two cycles.
set_multicycle_path -setup -from [get_pins {a816/cpu/MCode/M_TAB_M_TAB_0_*_s/CLK}] -to [get_regs {a816/cpu/A_*_s* a816/cpu/X_*_s* a816/cpu/Y_*_s* a816/cpu/P_*_s* a816/cpu/T_*_s* a816/cpu/AddrGen/PCr_*_s*}] 2
set_multicycle_path -hold  -from [get_pins {a816/cpu/MCode/M_TAB_M_TAB_0_*_s/CLK}] -to [get_regs {a816/cpu/A_*_s* a816/cpu/X_*_s* a816/cpu/Y_*_s* a816/cpu/P_*_s* a816/cpu/T_*_s* a816/cpu/AddrGen/PCr_*_s*}] 1
# Same two-cycle argument for the system block's registers: they are only written in the bus
# FSM's S_B state (io_wr), never in the cycle right after a CPU enable.
set_multicycle_path -setup -from [get_pins {a816/cpu/MCode/M_TAB_M_TAB_0_*_s/CLK}] -to [get_regs {a816/tm_count* a816/tm_reload* a816/tm_run* a816/tm_rep* a816/irq_en* a816/irq_status* a816/nmi_status* a816/wd_* a816/mb_req_* a816/mb_rsp_* a816/pt_index* a816/b0win* a816/cur_task* a816/fr_* a816/kb_route*}] 2
set_multicycle_path -hold  -from [get_pins {a816/cpu/MCode/M_TAB_M_TAB_0_*_s/CLK}] -to [get_regs {a816/tm_count* a816/tm_reload* a816/tm_run* a816/tm_rep* a816/irq_en* a816/irq_status* a816/nmi_status* a816/wd_* a816/mb_req_* a816/mb_rsp_* a816/pt_index* a816/b0win* a816/cur_task* a816/fr_* a816/kb_route*}] 1
# The same two-cycle argument from the CPU's own registers: every register of P65C816 /
# AddrGen changes only on a CPU enable (EN = CE & ...), and CE never comes in two consecutive
# clk_core cycles. So a path that starts at one of them (e.g. AddrGen AAL -> address -> I/O
# read mux -> D_IN -> ALU -> P/A/PCr, the clk_core critical path in 2026-11) and ends at a
# register that is also only written on a CPU enable or in S_B has two cycles.
set_multicycle_path -setup -from [get_regs {a816/cpu/AddrGen/AAL_*_s* a816/cpu/AddrGen/AAH_*_s* a816/cpu/AddrGen/AB_*_s* a816/cpu/AddrGen/DL_*_s* a816/cpu/AddrGen/DH_*_s* a816/cpu/AddrGen/PCr_*_s* a816/cpu/A_*_s* a816/cpu/X_*_s* a816/cpu/Y_*_s* a816/cpu/P_*_s* a816/cpu/T_*_s* a816/cpu/D_*_s* a816/cpu/DR_*_s* a816/cpu/DBR_*_s* a816/cpu/PBR_*_s* a816/cpu/SP_*_s* a816/cpu/IR_*_s* a816/cpu/STATE_*_s* a816/cpu/IsResetInterrupt_s* a816/cpu/IsNMIInterrupt_s* a816/cpu/IsIRQInterrupt_s* a816/cpu/IsABORTInterrupt_s* a816/cpu/GotInterrupt_s*}] -to [get_regs {a816/cpu/AddrGen/AAL_*_s* a816/cpu/AddrGen/AAH_*_s* a816/cpu/AddrGen/AB_*_s* a816/cpu/AddrGen/DL_*_s* a816/cpu/AddrGen/DH_*_s* a816/cpu/D_*_s* a816/cpu/DR_*_s* a816/cpu/DBR_*_s* a816/cpu/PBR_*_s* a816/cpu/SP_*_s* a816/cpu/A_*_s* a816/cpu/X_*_s* a816/cpu/Y_*_s* a816/cpu/P_*_s* a816/cpu/T_*_s* a816/cpu/AddrGen/PCr_*_s* a816/tm_count* a816/tm_reload* a816/tm_run* a816/tm_rep* a816/irq_en* a816/irq_status* a816/nmi_status* a816/wd_* a816/mb_req_* a816/mb_rsp_* a816/pt_index* a816/b0win* a816/cur_task* a816/fr_* a816/kb_route*}] 2
set_multicycle_path -hold -from [get_regs {a816/cpu/AddrGen/AAL_*_s* a816/cpu/AddrGen/AAH_*_s* a816/cpu/AddrGen/AB_*_s* a816/cpu/AddrGen/DL_*_s* a816/cpu/AddrGen/DH_*_s* a816/cpu/AddrGen/PCr_*_s* a816/cpu/A_*_s* a816/cpu/X_*_s* a816/cpu/Y_*_s* a816/cpu/P_*_s* a816/cpu/T_*_s* a816/cpu/D_*_s* a816/cpu/DR_*_s* a816/cpu/DBR_*_s* a816/cpu/PBR_*_s* a816/cpu/SP_*_s* a816/cpu/IR_*_s* a816/cpu/STATE_*_s* a816/cpu/IsResetInterrupt_s* a816/cpu/IsNMIInterrupt_s* a816/cpu/IsIRQInterrupt_s* a816/cpu/IsABORTInterrupt_s* a816/cpu/GotInterrupt_s*}] -to [get_regs {a816/cpu/AddrGen/AAL_*_s* a816/cpu/AddrGen/AAH_*_s* a816/cpu/AddrGen/AB_*_s* a816/cpu/AddrGen/DL_*_s* a816/cpu/AddrGen/DH_*_s* a816/cpu/D_*_s* a816/cpu/DR_*_s* a816/cpu/DBR_*_s* a816/cpu/PBR_*_s* a816/cpu/SP_*_s* a816/cpu/A_*_s* a816/cpu/X_*_s* a816/cpu/Y_*_s* a816/cpu/P_*_s* a816/cpu/T_*_s* a816/cpu/AddrGen/PCr_*_s* a816/tm_count* a816/tm_reload* a816/tm_run* a816/tm_rep* a816/irq_en* a816/irq_status* a816/nmi_status* a816/wd_* a816/mb_req_* a816/mb_rsp_* a816/pt_index* a816/b0win* a816/cur_task* a816/fr_* a816/kb_route*}] 1
# The interrupt flags IsReset/IsNMI/IsIRQ/IsABORTInterrupt and GotInterrupt are written only
# under RDY_IN & CE (P65C816.v), so they are start points of the same two-cycle paths
# (IsIRQInterrupt -> P / PCr became the clk_core critical path in step 17).
# Microcode -> the CPU registers the first pair above leaves out (all written only on EN).
set_multicycle_path -setup -from [get_pins {a816/cpu/MCode/M_TAB_M_TAB_0_*_s/CLK}] -to [get_regs {a816/cpu/D_*_s* a816/cpu/DR_*_s* a816/cpu/DBR_*_s* a816/cpu/PBR_*_s* a816/cpu/SP_*_s* a816/cpu/AddrGen/AAL_*_s* a816/cpu/AddrGen/AAH_*_s* a816/cpu/AddrGen/AB_*_s* a816/cpu/AddrGen/DL_*_s* a816/cpu/AddrGen/DH_*_s*}] 2
set_multicycle_path -hold  -from [get_pins {a816/cpu/MCode/M_TAB_M_TAB_0_*_s/CLK}] -to [get_regs {a816/cpu/D_*_s* a816/cpu/DR_*_s* a816/cpu/DBR_*_s* a816/cpu/PBR_*_s* a816/cpu/SP_*_s* a816/cpu/AddrGen/AAL_*_s* a816/cpu/AddrGen/AAH_*_s* a816/cpu/AddrGen/AB_*_s* a816/cpu/AddrGen/DL_*_s* a816/cpu/AddrGen/DH_*_s*}] 1

/* FREDDIE II (native side) — a line-by-line model of the FREDDIE II part of a816_sys.sv.
 *
 * Per bus access (the RTL's S_B cycle with cpu_step and a valid address):
 *   sync  = opcode fetch, vpull = vector pull, pop = sync && rti_seen
 *   user_eff = vpull ? 0 : pop ? mstack[0] : mode_user
 *   refuse   = !(int_seq && read) && ((PROT_EN && (u_io|u_nvalid|u_nowner|u_ro)) || s_wpvec)
 *   blocked  = refuse || (wr_block && write)
 * A refused read returns $EA. The first refusal of an instruction (wr_block still clear)
 * sets ABORT_ADDR and ORs ABORT_CAUSE; wr_block then blocks every later write until the
 * next opcode fetch.
 */
#include "machine.h"
#include <string.h>

void freddie_reset(void)
{
    Freddie *f = &M.fr;
    uint8_t pt[256];
    memcpy(pt, f->pt, sizeof pt);           /* the table is block RAM: not reset */
    memset(f, 0, sizeof *f);
    memcpy(f->pt, pt, sizeof pt);
}

static inline int is_io(uint32_t a) { return (a & 0xFFF000) == 0x00D000; }

/* protection check; returns the cause bits {s_wpvec,u_io,u_nvalid,u_nowner,is_write} or 0 */
static inline int check(Freddie *f, uint32_t a, int user, int write)
{
    int cause = 0;
    if (user && f->prot_en) {
        int io = is_io(a);
        int b0_hit = f->b0win_en && a < 0x8000;
        if (io) cause = 0x08;
        else if (!b0_hit) {
            uint8_t e = f->pt[a >> 16];
            int own_ok = (e & 0x3F) == f->cur_task || (e & 0x3F) == 63;
            if (!(e & 0x80)) cause = 0x04;
            else if (!own_ok) cause = 0x02;
            else if (write && !(e & 0x40)) cause = 0x20;    /* u_ro: no cause bit of its own */
        }
    }
    if (!user && f->wp_vec && write && (a & 0xFFE000) == 0x00E000) cause |= 0x10;
    if (cause) cause = (cause & 0x1E) | (write ? 1 : 0) | 0x100;   /* 0x100 = refused */
    return cause;
}

static inline void refused(Freddie *f, uint32_t a, int cause, int flags, int old_block)
{
    if (!old_block) {
        f->abort_addr = a;
        f->abort_cause |= cause & 0x1F;
    }
    f->wr_block = 1;
    f->n_refused++;
    if (!(flags & BUS_INTSEQ)) M.cpu.abort = 1;   /* the CPU ignores ABORT in a sequence anyway */
}

static uint8_t io_read(uint32_t a)
{
    machine_sync_slow();
    switch ((a >> 8) & 0xF) {
    case 0x8: return freddie_io_read(a);
    case 0x9: return nvc_read(a);
    case 0xA: return blitter_read(a);
    case 0xB: return audio_read(a);
    case 0xC: return sv_read(a);
    case 0xD: return mailbox_read(a);
    case 0xE: return sys_read(a);
    }
    return 0;
}

static void io_write(uint32_t a, uint8_t v)
{
    machine_sync_slow();
    switch ((a >> 8) & 0xF) {
    case 0x8: freddie_io_write(a, v); break;
    case 0x9: nvc_write(a, v); break;
    case 0xA: blitter_write(a, v); break;
    case 0xB: sound_write(a, v); break;
    case 0xC: sv_write(a, v); break;
    case 0xD: mailbox_write(a, v); break;
    case 0xE: sys_write(a, v); break;
    }
    machine_update_irq();
}

static inline uint32_t phys(Freddie *f, uint32_t a)
{
    if (f->b0win_en && a < 0x8000) return (uint32_t)(f->b0win & 0x7F) << 16 | a;
    return a;
}

uint8_t bus_peek(uint32_t a)
{
    if (is_io(a) || a >= RAM_SIZE) return 0;
    return M.ram[phys(&M.fr, a)];
}

uint8_t bus_read(void *ctx, uint32_t a, int flags)
{
    (void)ctx;
    Freddie *f = &M.fr;
    int sync = flags & BUS_SYNC, intseq = flags & BUS_INTSEQ;
    /* a816_sys.sv: vpull = ~cpu_vpb && !(wr_block && !cpu_int_seq). The vector pull of a
     * BRK/COP that already had a refused access neither enters supervisor mode nor pushes
     * the mode stack; it is checked like any user-mode read. */
    int vpull = (flags & BUS_VECTOR) && !(f->wr_block && !intseq);
    int pop = sync && f->rti_seen;
    int user = vpull ? 0 : (pop ? (f->mstack & 1) : f->mode_user);
    int cause = intseq ? 0 : check(f, a, user, 0);
    uint8_t v, old_block = f->wr_block;

    if (sync) f->wr_block = 0;               /* an opcode fetch ends the write block */
    if (cause) {
        v = 0xEA;
        refused(f, a, cause, flags, old_block);
    } else {
        if (is_io(a)) v = io_read(a);
        else if (a >= RAM_SIZE) v = 0;
        else {
            uint32_t pa = phys(f, a);
            if (M.bl.stale) blitter_stale_read(pa);
            v = M.ram[pa];
        }
    }

    /* mode tracking */
    if (vpull) {
        if (!f->in_pull) f->mstack = (uint8_t)(f->mstack << 1) | f->mode_user;
        if (!f->in_pull && f->mode_user) { f->nmi_hold = 1; sys_nmi_line(); }
        f->mode_user = 0;
        f->in_pull = 1;
        f->rti_seen = 0;
    } else {
        f->in_pull = 0;
        if (sync) {
            if (pop) {
                f->mode_user = f->mstack & 1;
                f->mstack >>= 1;
            }
            f->rti_seen = (v == 0x40) && !user && !intseq && !cause;
        }
    }
    return v;
}

void bus_write(void *ctx, uint32_t a, uint8_t v, int flags)
{
    (void)ctx;
    Freddie *f = &M.fr;
    f->in_pull = 0;
    int cause = check(f, a, f->mode_user, 1);
    if (cause) { refused(f, a, cause, flags, f->wr_block); return; }
    if (f->wr_block) return;
    if (is_io(a)) io_write(a, v);
    else if (a < RAM_SIZE) M.ram[phys(f, a)] = v;
}

uint8_t freddie_io_read(uint32_t a)
{
    Freddie *f = &M.fr;
    switch (a & 0xFFF) {
    case 0x800: return f->mode_user << 7 | f->wp_vec << 3 | f->b0win_en << 2 | (f->mstack & 1) << 1 | f->prot_en;
    case 0x801: return f->pt_index;
    case 0x802: return f->pt[f->pt_index];
    case 0x803: return f->cur_task;
    case 0x804: return f->abort_addr & 0xFF;
    case 0x805: return (f->abort_addr >> 8) & 0xFF;
    case 0x806: return (f->abort_addr >> 16) & 0xFF;
    case 0x807: return f->abort_cause;
    case 0x808: return f->b0win;
    case 0x809: return (RAM_SIZE >> 16) - 1;
    }
    return 0;
}

void freddie_io_write(uint32_t a, uint8_t v)
{
    Freddie *f = &M.fr;
    switch (a & 0xFFF) {
    case 0x800:
        f->nmi_hold = 0;                    /* any FR_CTRL write releases a held NMI */
        sys_nmi_line();
        f->prot_en = v & 1;
        f->mstack = (f->mstack & ~1) | ((v >> 1) & 1);
        f->b0win_en = (v >> 2) & 1;
        f->wp_vec = (v >> 3) & 1;
        break;
    case 0x801: f->pt_index = v; break;
    case 0x802: f->pt[f->pt_index] = v; break;
    case 0x803: f->cur_task = v & 0x3F; break;
    case 0x807: f->abort_cause &= ~v & 0x1F; break;
    case 0x808: f->b0win = v; break;
    case 0x80A: blitter_flush(); break;     /* CACHE_FLUSH: only the blitter's stale lines are modelled */
    }
}

/* Ali, the blitter — register spec "Ali (blitter)". Executed in full when START is written, so BUSY is
 * never seen set. Addresses are physical (no bank 0 window, no protection).
 *
 * Timing (--ideal-timing: the model before Horizon 0.19), from the RTL simulation (clk_core
 * cycles per pixel; a CPU cycle is 2 clk_core):
 * FILL 2.0, EXPAND / EXPAND_KEY 2.2, COPY / COPY_KEY 2.9 with the classic machine frozen
 * (16-byte bursts) or 3.5 running, plus about 0.8 with the video on. The pixels are
 * written at START; BUSY then reads 1 for 8 + 2 per line + that many cycles, and the
 * BLITTER interrupt (IRQ_EN) comes when it drops. The CPU is not slowed.
 * Hardware rules the emulator enforces by counting (and reporting on stderr):
 *  - START while BUSY is ignored;
 *  - writing $DA00-$DA12 while BUSY is illegal (the blitter reads them while it runs);
 *  - the CPU must write CACHE_FLUSH ($00:D80A) before reading memory the blitter wrote.
 * Only on a REV >= $08 machine (--rev).
 *
 * REV $09 (core/src/a816/a816_blit.sv): command lists. BL_LIST ($DA14-16, 8-byte aligned)
 * and BL_COUNT ($DA17-18); BL_CTRL write bit 2 LIST, bit 3 ABORT; read bit 2 LIST, 3 WAITING,
 * 4 DONE, 5 ABORTED. Each 24-byte record is read REC_CYC cycles after the previous blit has
 * finished (its bytes 0-18 go to $DA00-$DA12, BL_LIST += 24, BL_COUNT - 1); a record with
 * RFLAGS bit 0 then waits for the next VBLANK event (nvc_vbl_after); its pixels are written
 * when it starts, and it is busy for blit_cost cycles. One interrupt at the end of the list.
 * ABORT: the list stops, BUSY drops at once (the pixels of the blit that was running are all
 * written, unlike the hardware, which stops it within one memory access), no interrupt.
 * From REV $09 register writes while BUSY are ignored (and counted).
 *
 * Choices where the spec is open:
 *  - BACKWARDS walks lines from the last to the first and pixels from right to left; the
 *    addresses still name the first (top-left) byte of each rectangle.
 *  - EXPAND sources: each line starts at BL_SRC + y * BL_SRC_STRIDE at bit SRC_BIT
 *    (7 = leftmost); the bit position runs on into the following bytes.
 *  - WIDTH / HEIGHT 0 mean 4096 is NOT assumed: a 0 does nothing.
 */
#include "machine.h"
#include <string.h>
#include <stdlib.h>

void blitter_reset(void) { memset(&M.bl, 0, sizeof M.bl); }

static uint32_t r24(int i) { return M.bl.r[i] | M.bl.r[i + 1] << 8 | (uint32_t)M.bl.r[i + 2] << 16; }
static uint32_t r16(int i) { return M.bl.r[i] | M.bl.r[i + 1] << 8; }

/* (Horizon 0.30) a FILL writes aligned 32-bit words with a byte mask (a816_blit.sv: no reads,
 * one word a request), so its time follows the words a line touches, not its pixels: a short
 * run that starts or ends inside a word pays for the whole word. The words of h lines of w
 * pixels from dst, lines dstr apart. */
static uint64_t fill_words(uint32_t dst, uint32_t dstr, uint32_t w, uint32_t h)
{
    uint64_t n = 0;
    if ((dstr & 3) == 0 || h == 1)
        return (uint64_t)(((dst & 3) + w + 3) >> 2) * h;
    for (uint32_t y = 0; y < h; y++, dst += dstr)
        n += ((dst & 3) + w + 3) >> 2;
    return n;
}

static uint64_t blit_cost(uint32_t w, uint32_t h, uint8_t op, uint32_t dst, uint32_t dstr)
{
    uint64_t px = (uint64_t)w * h;
    if (M.fr.ideal) {                                   /* the model before Horizon 0.19 */
        uint32_t clk10;                                 /* clk_core x 10 per pixel */
        if (op == 0) clk10 = 20;
        else if (op == 1 || op == 2) clk10 = (M.sys.sv_ctrl & 0x04 ? 29 : 35) + (M.nvc.ctrl & 1 ? 8 : 0);
        else clk10 = 22;
        return 8 + 2 * (uint64_t)h + px * clk10 / 20;
    }
    /* clk_core x 100 per pixel, measured on the board (core/sw/a816/timing.s), by the classic
     * machine's state (frozen / running), Marga's mode (off, 0, 1, 2) and the operation (fill,
     * copy and keyed copy, expand). Measured: frozen off / mode 0 / mode 2 and running mode 0;
     * the rest interpolated. Copies have no per-line cost. */
    static const uint16_t clk[2][4][3] = {
        { { 190, 275, 209 }, { 295, 420, 325 }, { 263, 378, 290 }, { 231, 335, 254 } },
        { { 256, 361, 282 }, { 630, 975, 693 }, { 536, 821, 590 }, { 443, 668, 488 } } };
    int k = op == 0 ? 0 : (op == 1 || op == 2) ? 1 : 2, v = 0;
    if (M.nvc.ctrl & 1) { v = 1 + ((M.nvc.ctrl >> 1) & 3); if (v > 3) v = 3; }
    uint32_t clk100 = clk[!(M.sys.sv_ctrl & 0x04)][v][k];
    if (k == 0)                                         /* (0.30) a fill: by its words */
        px = 4 * fill_words(dst, dstr, w, h);
    return 8 + (k == 1 ? 0 : 2 * (uint64_t)h) + px * clk100 / 200;
}

#define STALE_BYTES (RAM_SIZE / 8 / 8)

static void stale_mark(uint32_t a)
{
    if (a >= RAM_SIZE) return;
    if (!M.bl.stale) M.bl.stale = calloc(STALE_BYTES, 1);
    if (M.bl.stale) M.bl.stale[a >> 6] |= 1 << ((a >> 3) & 7);
}

void blitter_flush(void) { if (M.bl.stale) memset(M.bl.stale, 0, STALE_BYTES); }

void blitter_stale_read(uint32_t a)
{
    uint8_t *p = M.bl.stale ? &M.bl.stale[a >> 6] : NULL, bit = 1 << ((a >> 3) & 7);
    if (!p || !(*p & bit)) return;
    *p &= ~bit;                                         /* once per line until the next blit */
    if (M.bl.n_stale_reads++ < 10)
        fprintf(stderr, "emu816: blitter: CPU read of %06X written by the blitter, no CACHE_FLUSH since\n", a);
}

/* reading and loading a record: a816_blit.sv's list sequencer reads it as three 8-byte bursts
 * one after the other through the blitter's port (the lowest priority), each followed by 8
 * clk_core of loading its bytes into the registers (L_RD, L_WT, L_LD), then L_CHK, L_GO and
 * the blit's line set-up (S_LS0, S_LS2): about 60 clk_core with an idle port = 30 CPU cycles,
 * then blit_cost's 8 + 2 a line. (0.30: checked against the RTL for fill_runs, whose lists
 * are thousands of one-line fills; a 23-pixel run costs about 30 + 10 + 7 words.) */
#define REC_CYC 30

static int busy(void) { return M.bl.list || M.cpu.cycles < M.bl.busy_until; }

static void blit(uint64_t at)
{
    Blitter *b = &M.bl;
    uint32_t src = r24(0x00), sstr = r16(0x03), dst = r24(0x05), dstr = r16(0x08);
    uint32_t w = r16(0x0A), h = r16(0x0C);
    uint8_t fg = b->r[0x0E], bg = b->r[0x0F], key = b->r[0x10], op = b->r[0x11];
    int back = b->r[0x12] & 1, sbit = (b->r[0x12] >> 4) & 7;
    if (w > 4096) w = 4096;
    if (h > 4096) h = 4096;
    b->n_blits++;
    for (uint32_t yy = 0; yy < h; yy++) {
        uint32_t y = back ? h - 1 - yy : yy;
        uint32_t s = src + y * sstr, d = dst + y * dstr;
        for (uint32_t xx = 0; xx < w; xx++) {
            uint32_t x = back ? w - 1 - xx : xx;
            uint32_t da = (d + x) & 0xFFFFFF;
            switch (op) {
            case 0: phys_wr(da, fg); stale_mark(da); break;
            case 1: phys_wr(da, phys_rd((s + x) & 0xFFFFFF)); stale_mark(da); break;
            case 2: { uint8_t c = phys_rd((s + x) & 0xFFFFFF); if (c != key) { phys_wr(da, c); stale_mark(da); } break; }
            case 3: case 4: {
                uint32_t bitn = (7 - sbit) + x;                  /* bits from the leftmost */
                uint8_t byte = phys_rd((s + bitn / 8) & 0xFFFFFF);
                int on = (byte >> (7 - (bitn & 7))) & 1;
                if (on) { phys_wr(da, fg); stale_mark(da); }
                else if (op == 3) { phys_wr(da, bg); stale_mark(da); }
                break;
            }
            default: goto out;
            }
        }
    }
    b->n_pixels += (uint64_t)w * h;
out:;
    uint64_t c = (w && h && op <= 4) ? blit_cost(w, h, op, dst, dstr) : 8;
    b->busy_cycles += c;
    b->busy_until = at + c;
}

/* REV $09 list: one step at list_next (read a record, or start it, or end the list) */
static void list_step(void)
{
    Blitter *b = &M.bl;
    uint64_t t = b->list_next;
    uint32_t cnt = b->r[0x17] | b->r[0x18] << 8;
    if (b->lphase == 1) {                               /* the loaded record starts */
        b->lwait = 0;
        blit(t);
        b->lphase = 0;
        b->list_next = b->busy_until;
        return;
    }
    if (cnt == 0) {                                     /* end of the list */
        b->list = 0;
        b->done = 1;
        if (b->r[0x13] & 2) sys_raise_irq(IRQ_BLITTER);
        return;
    }
    uint32_t la = (b->r[0x14] & 0xF8) | b->r[0x15] << 8 | (uint32_t)b->r[0x16] << 16;
    for (int i = 0; i < 19; i++) b->r[i] = phys_rd((la + i) & 0xFFFFFF);
    int wait = phys_rd((la + 19) & 0xFFFFFF) & 1;
    la = (la + 24) & 0xFFFFFF;
    b->r[0x14] = la & 0xFF; b->r[0x15] = (la >> 8) & 0xFF; b->r[0x16] = la >> 16;
    cnt--;
    b->r[0x17] = cnt & 0xFF; b->r[0x18] = cnt >> 8;
    b->n_records++;
    b->lphase = 1;
    b->lwait = wait;
    b->list_next = wait ? nvc_vbl_after(t + REC_CYC) : t + REC_CYC;
}

void blitter_update(uint64_t now)
{
    while (M.bl.list && now >= M.bl.list_next) list_step();
    if (M.bl.irq_due && now >= M.bl.busy_until) {
        M.bl.irq_due = 0;
        sys_raise_irq(IRQ_BLITTER);
    }
}

uint64_t blitter_next_event(void)
{
    uint64_t e = M.bl.irq_due ? M.bl.busy_until : UINT64_MAX;
    if (M.bl.list && M.bl.list_next < e) e = M.bl.list_next;
    return e;
}

uint8_t blitter_read(uint32_t a)
{
    Blitter *b = &M.bl;
    int i = a & 0xFF;
    if (M.sys.rev < 8) return 0;
    if (i < 0x13) return b->r[i];
    if (i == 0x13) {
        int bz = busy();
        uint8_t v = (b->r[0x13] & 0x02) | bz;
        if (M.sys.rev >= 9)
            v |= (b->list ? 0x04 : 0) | (b->list && b->lwait ? 0x08 : 0) |
                 (b->done && !bz ? 0x10 : 0) | (b->aborted ? 0x20 : 0);
        return v;
    }
    if (M.sys.rev >= 9 && i <= 0x18) return i == 0x14 ? (b->r[i] & 0xF8) : b->r[i];
    return 0;
}

void blitter_write(uint32_t a, uint8_t v)
{
    Blitter *b = &M.bl;
    int i = a & 0xFF;
    if (M.sys.rev < 8 || i > (M.sys.rev >= 9 ? 0x18 : 0x13)) return;
    if (i == 0x13) {
        b->r[i] = v & 0x02;
        if (M.sys.rev >= 9 && (v & 0x08)) {                 /* ABORT */
            if (busy()) {
                b->list = 0;
                b->lwait = 0;
                b->aborted = 1;
                b->done = 0;
                b->irq_due = 0;
                b->busy_until = M.cpu.cycles;
                machine_reschedule();
            }
            return;
        }
        if (M.sys.rev >= 9 && (v & 0x04)) {                 /* LIST */
            if (busy()) {
                if (b->n_busy_starts++ < 10) fprintf(stderr, "emu816: blitter: LIST while BUSY (ignored)\n");
                return;
            }
            b->list = 1;
            b->lphase = 0;
            b->lwait = 0;
            b->done = b->aborted = 0;
            b->list_next = M.cpu.cycles;
            b->n_lists++;
            blitter_update(M.cpu.cycles);
            machine_reschedule();
            return;
        }
        if (v & 1) {
            if (busy()) {                                   /* ignored by the hardware */
                if (b->n_busy_starts++ < 10) fprintf(stderr, "emu816: blitter: START while BUSY (ignored)\n");
                return;
            }
            b->done = 1;                                    /* (DONE reads 1 once BUSY drops) */
            b->aborted = 0;
            blit(M.cpu.cycles);
            b->irq_due = (v & 2) != 0;
            machine_reschedule();
        }
        return;
    }
    if (busy()) {
        if (b->n_busy_writes++ < 10)
            fprintf(stderr, "emu816: blitter: register $%02X written while BUSY%s\n", 0xDA00 + i,
                    M.sys.rev >= 9 ? " (ignored)" : "");
        if (M.sys.rev >= 9) return;
    }
    b->r[i] = v;
}

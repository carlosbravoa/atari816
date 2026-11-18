/* cputest — runs cpu65816.c against SingleStepTests/65816 files converted by fetch_sst.py.
 *
 *   tests/cputest [-v] FILE...
 *
 * Hard checks: final registers, final RAM, total cycle count.
 * Soft check (reported separately): the sequence of valid bus cycles (VDA/VPA/VPB), i.e.
 * address, data and direction of every access the emulator makes.
 */
#include "../cpu65816.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint8_t *mem;
typedef struct { uint32_t a; int v; char rw; } Acc;
static Acc acc[4096];
static int nacc;

static uint8_t rd(void *ctx, uint32_t a, int f)
{
    (void)ctx; (void)f;
    if (nacc < 4096) acc[nacc++] = (Acc){ a, mem[a], 'r' };
    return mem[a];
}
static void wr(void *ctx, uint32_t a, uint8_t v, int f)
{
    (void)ctx; (void)f;
    if (nacc < 4096) acc[nacc++] = (Acc){ a, v, 'w' };
    mem[a] = v;
}

static char *line;
static size_t cap;

static int nums(const char *s, long *out, int max)
{
    int n = 0;
    char *e;
    while (n < max) {
        long v = strtol(s, &e, 10);
        if (e == s) break;
        out[n++] = v;
        s = e;
    }
    return n;
}

int main(int argc, char **argv)
{
    int verbose = 0;
    long total = 0, fail = 0, busfail = 0, files = 0;
    mem = calloc(1 << 24, 1);
    static long ram_i[2 * 4096], ram_f[2 * 4096], bus[3 * 4096];
    static char busrw[4096];
    for (int ai = 1; ai < argc; ai++) {
        if (!strcmp(argv[ai], "-v")) { verbose = 1; continue; }
        FILE *f = fopen(argv[ai], "r");
        if (!f) { perror(argv[ai]); continue; }
        files++;
        long ffail = 0, fbus = 0, ftotal = 0;
        char name[64] = "";
        long I[10], F[10], C = 0;
        int nri = 0, nrf = 0, nb = 0;
        while (getline(&line, &cap, f) > 0) {
            char k = line[0];
            if (k == 'T') { snprintf(name, sizeof name, "%s", line + 2); name[strcspn(name, "\n")] = 0; }
            else if (k == 'I') nums(line + 1, I, 10);
            else if (k == 'F') nums(line + 1, F, 10);
            else if (k == 'R') nri = nums(line + 1, ram_i, 2 * 4096);
            else if (k == 'M') nrf = nums(line + 1, ram_f, 2 * 4096);
            else if (k == 'C') C = atol(line + 1);
            else if (k == 'B') {
                /* "addr val rw" triples */
                nb = 0;
                char *s = line + 1, *e;
                while (nb < 4096) {
                    long a = strtol(s, &e, 10); if (e == s) break; s = e;
                    long v = strtol(s, &e, 10); s = e;
                    while (*s == ' ') s++;
                    busrw[nb] = *s++;
                    bus[3 * nb] = a; bus[3 * nb + 1] = v; nb++;
                }
                /* run the test */
                Cpu65816 c;
                cpu_init(&c, NULL, rd, wr);
                c.pc = I[0]; c.s = I[1]; c.p = I[2]; c.a = I[3]; c.x = I[4]; c.y = I[5];
                c.dbr = I[6]; c.d = I[7]; c.pbr = I[8]; c.e = I[9];
                if (c.e) { c.s = 0x0100 | (c.s & 0xFF); c.x &= 0xFF; c.y &= 0xFF; }
                for (int i = 0; i < nri; i += 2) mem[ram_i[i]] = ram_i[i + 1];
                nacc = 0;
                uint8_t op = mem[(uint32_t)c.pbr << 16 | c.pc];
                uint16_t pc0 = c.pc;
                cpu_exec(&c);
                if (op == 0x44 || op == 0x54)
                    while (c.pc == pc0 && c.cycles < (uint64_t)C) cpu_exec(&c);
                int bad = 0;
                long got[10] = { c.pc, c.s, c.p, c.a, c.x, c.y, c.dbr, c.d, c.pbr, c.e };
                static const char *rn[10] = { "pc", "s", "p", "a", "x", "y", "dbr", "d", "pbr", "e" };
                char msg[512];
                int ml = 0;
                msg[0] = 0;
                for (int i = 0; i < 10; i++)
                    if (got[i] != F[i]) { bad = 1; ml += snprintf(msg + ml, sizeof msg - ml, " %s=%lx/%lx", rn[i], got[i], F[i]); }
                for (int i = 0; i < nrf; i += 2)
                    if (mem[ram_f[i]] != ram_f[i + 1]) { bad = 1; ml += snprintf(msg + ml, sizeof msg - ml, " [%06lx]=%02x/%02lx", ram_f[i], mem[ram_f[i]], ram_f[i + 1]); if (ml > 400) break; }
                /* WAI/STP: the suite counts one cycle into the halted state; the data sheet says 3 */
                if ((op == 0xCB || op == 0xDB) && (long)c.cycles == C - 1) C--;
                if ((long)c.cycles != C) { bad = 1; ml += snprintf(msg + ml, sizeof msg - ml, " cycles=%llu/%ld", (unsigned long long)c.cycles, C); }
                int bb = nacc != nb;
                for (int i = 0; !bb && i < nb; i++)
                    if (acc[i].a != (uint32_t)bus[3 * i] || acc[i].rw != busrw[i] ||
                        (bus[3 * i + 1] >= 0 && acc[i].v != bus[3 * i + 1])) bb = 1;
                if (bad) { ffail++; if (verbose || ffail <= 2) printf("FAIL %s:%s\n", name, msg); }
                if (bb) {
                    fbus++;
                    if (verbose && !bad) {
                        printf("BUS %s: emu", name);
                        for (int i = 0; i < nacc; i++) printf(" %06x%c%02x", acc[i].a, acc[i].rw, acc[i].v);
                        printf("\n    sst");
                        for (int i = 0; i < nb; i++) printf(" %06lx%c%02lx", bus[3 * i], busrw[i], bus[3 * i + 1] & 0xFF);
                        printf("\n");
                    }
                }
                for (int i = 0; i < nri; i += 2) mem[ram_i[i]] = 0;
                for (int i = 0; i < nrf; i += 2) mem[ram_f[i]] = 0;
                for (int i = 0; i < nacc; i++) mem[acc[i].a] = 0;
                ftotal++;
            }
        }
        fclose(f);
        total += ftotal; fail += ffail; busfail += fbus;
        if (ffail || verbose) printf("%s: %ld/%ld failed, %ld bus-sequence differences\n", argv[ai], ffail, ftotal, fbus);
        else if (fbus) printf("%s: ok, %ld/%ld bus-sequence differences\n", argv[ai], fbus, ftotal);
    }
    printf("cputest: %ld files, %ld tests, %ld failed (state/memory/cycles), %ld with bus-sequence differences\n",
           files, total, fail, busfail);
    return fail ? 1 : 0;
}

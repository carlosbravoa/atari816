/* emu816 — software model of the Atari816 native side (65C816 + FREDDIE II + system I/O).
 *
 *   emu816 [--sd DIR] [--load FILE@ADDR]... [--max-seconds N] [--trace]
 *          [--shot FILE.ppm] [--shot-at SECONDS] [--stats] [--headless] [--fast] PROGRAM.BIN
 */
#include "machine.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>
#ifdef HAVE_SDL
#include <SDL.h>
#endif

Machine M;

#define MAXSHOTS 16
static const char *shot_path[MAXSHOTS];
static double shot_at[MAXSHOTS];
static int shot_done[MAXSHOTS], nshots;
#ifdef HAVE_SDL
static int sdl_on = 1, fast;
#endif

/* ── host keyboard: SDL or --keys ── */
#define HID_F12 0x45
static void host_key(int usage, int down)
{
    if (usage <= 0 || usage > 0xFF) return;
    if (usage == HID_F12 && down) sys_raise_nmi(1);     /* F12: SYSTEM_KEY NMI and a KEY event */
    mailbox_key(usage, down);
}

/* scripted input (--keys, --mouse), sorted by time */
typedef struct { uint64_t cycle; int seq; uint8_t mouse, usage, down, btn; int16_t dx, dy, wheel; } KeyAt;
static KeyAt *keys;
static int nkeys, nextkey;

static void keys_due(uint64_t now)
{
    while (nextkey < nkeys && keys[nextkey].cycle <= now) {
        KeyAt *k = &keys[nextkey++];
        if (k->mouse) mailbox_mouse(k->btn, k->dx, k->dy, k->wheel);
        else host_key(k->usage, k->down);
    }
}

static int cmpkey(const void *a, const void *b)
{
    const KeyAt *x = a, *y = b;
    if (x->cycle != y->cycle) return x->cycle < y->cycle ? -1 : 1;
    return x->seq - y->seq;                            /* keep the given order */
}

/* --keys "t_ms:usage:down,...": usage in hex, down 1/0 */
static void parse_keys(const char *s)
{
    while (*s) {
        double ms; unsigned u, d; int n = 0;
        if (sscanf(s, "%lf:%x:%u%n", &ms, &u, &d, &n) != 3) { fprintf(stderr, "emu816: bad --keys at \"%s\"\n", s); exit(1); }
        keys = realloc(keys, (nkeys + 1) * sizeof *keys);
        keys[nkeys] = (KeyAt){ .cycle = (uint64_t)(ms * CPU_HZ / 1000.0), .seq = nkeys, .usage = u, .down = d != 0 };
        nkeys++;
        s += n;
        if (*s == ',') s++;
    }
}

/* --mouse "t_ms:dx:dy:wheel:buttons,...": decimal motion (desktop pixels, dy > 0 = down,
 * wheel > 0 = away from the user), buttons = bit 0 left, 1 right, 2 middle */
static void parse_mouse(const char *s)
{
    while (*s) {
        double ms; int dx, dy, w, b, n = 0;
        if (sscanf(s, "%lf:%d:%d:%d:%i%n", &ms, &dx, &dy, &w, &b, &n) != 5) { fprintf(stderr, "emu816: bad --mouse at \"%s\"\n", s); exit(1); }
        keys = realloc(keys, (nkeys + 1) * sizeof *keys);
        keys[nkeys] = (KeyAt){ .cycle = (uint64_t)(ms * CPU_HZ / 1000.0), .seq = nkeys, .mouse = 1, .btn = b, .dx = dx, .dy = dy, .wheel = w };
        nkeys++;
        s += n;
        if (*s == ',') s++;
    }
}

/* ── scheduling ─────────────────────────────────────────────────────────── */
void machine_update_irq(void)
{
    M.cpu.irq = (sys_irq_now() & M.sys.irq_en) != 0;
}

void machine_reschedule(void)
{
    uint64_t n = nvc_next_event();
    if (M.mb.next_poll < n) n = M.mb.next_poll;
    uint64_t se = sys_next_event();
    if (se < n) n = se;
    se = blitter_next_event();
    if (se < n) n = se;
    se = audio_next_event();
    if (se < n) n = se;
    if (nextkey < nkeys && keys[nextkey].cycle < n) n = keys[nextkey].cycle;
    M.next_event = n;
}

void machine_sync_slow(void)
{
    uint64_t now = M.cpu.cycles;
    sys_update(now);
    blitter_update(now);
    audio_update(now);
    nvc_update(now);
    keys_due(now);
    mailbox_poll(now);
    machine_reschedule();
    machine_update_irq();
}

/* ── video output ───────────────────────────────────────────────────────── */
#ifdef HAVE_SDL
static SDL_Window *win;
static SDL_Renderer *ren;
static SDL_Texture *tex;
static double t_start_real;
static int mouse_dx, mouse_dy, mouse_wheel;

static double now_real(void) { return SDL_GetPerformanceCounter() / (double)SDL_GetPerformanceFrequency(); }


static void sdl_events(void)
{
    SDL_Event ev;
    while (SDL_PollEvent(&ev)) {
        switch (ev.type) {
        case SDL_QUIT: M.cpu.stopped = 1; break;
        case SDL_KEYDOWN: case SDL_KEYUP: {
            int down = ev.type == SDL_KEYDOWN;
            if (ev.key.repeat) break;
            /* SDL scancodes are USB HID usage IDs (keyboard page, modifiers $E0-$E7) */
            host_key(ev.key.keysym.scancode, down);
            break;
        }
        case SDL_MOUSEMOTION: mouse_dx += ev.motion.xrel; mouse_dy += ev.motion.yrel; break;
        case SDL_MOUSEWHEEL: mouse_wheel += ev.wheel.y; break;
        }
    }
    uint32_t b = SDL_GetMouseState(NULL, NULL);
    int btn = (b & SDL_BUTTON_LMASK ? 1 : 0) | (b & SDL_BUTTON_RMASK ? 2 : 0) | (b & SDL_BUTTON_MMASK ? 4 : 0);
    /* window pixels -> desktop pixels: 2x in modes 0/1, 4x in mode 2; the remainder stays */
    int sc = ((M.nvc.ctrl >> 1) & 3) == 2 ? 4 : 2;
    int dx = mouse_dx / sc, dy = mouse_dy / sc;
    mouse_dx -= dx * sc; mouse_dy -= dy * sc;
    mailbox_mouse(btn, dx, dy, mouse_wheel);           /* the I/O processor accumulates */
    mouse_wheel = 0;
}

static void sdl_frame(void)
{
    nvc_render();
    SDL_UpdateTexture(tex, NULL, M.nvc.out, NV_OUT_W * 4);
    SDL_RenderClear(ren);
    SDL_RenderCopy(ren, tex, NULL, NULL);
    SDL_RenderPresent(ren);
    sdl_events();
    if (!fast) {                                  /* keep emulated time at real time */
        double emu = M.cpu.cycles / CPU_HZ, real = now_real() - t_start_real;
        if (emu > real) SDL_Delay((uint32_t)((emu - real) * 1000));
    }
}
#endif

static void on_frame(void)
{
    /* Marga only fetches and keeps lines when someone will look at them */
    double now = M.cpu.cycles / CPU_HZ;
    for (int i = 0; i < nshots; i++) {
        if (shot_done[i]) continue;
        if (now >= shot_at[i] - 0.1) M.nvc.want = 1;
        if (now >= shot_at[i]) {
            nvc_render();
            if (nvc_write_ppm(shot_path[i])) fprintf(stderr, "emu816: cannot write %s\n", shot_path[i]);
            shot_done[i] = 1;
        }
    }
#ifdef HAVE_SDL
    if (sdl_on) sdl_frame();
#endif
}

/* ── loading ────────────────────────────────────────────────────────────── */
static long load_file(const char *path, uint32_t addr, uint32_t max)
{
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); exit(1); }
    long n = fread(M.ram + addr, 1, max < RAM_SIZE - addr ? max : RAM_SIZE - addr, f);
    fclose(f);
    return n;
}

/* bank 0 as the I/O processor sets it up before releasing the CPU: reset stub, vectors */
static void reset_stub(void)
{
    static const uint8_t stub[] = { 0x18, 0xFB, 0x5C, 0x00, 0x00, 0x01 };   /* CLC XCE JML $010000 */
    memcpy(M.ram + 0xFF00, stub, sizeof stub);
    M.ram[0xFF10] = 0xDB;                                                    /* STP */
    for (uint32_t i = 0xFFE0; i < 0x10000; i += 2) { M.ram[i] = 0x10; M.ram[i + 1] = 0xFF; }
    M.ram[0xFFFC] = 0x00;                                                    /* RESET -> $FF00 */
}

/* SYS_RESTART (mailbox op $1B, answered): the I/O processor holds the CPU, loads
 * /SYSTEM/HORIZON.SYS from the card again (the program given on the command line when the
 * card has none) and releases it. RAM keeps its contents, as on the board. */
static const char *restart_prog;
static void machine_restart(void)
{
    char path[4400];
    int mode = M.mb.restart - 1;
    M.mb.restart = 0;
    snprintf(path, sizeof path, "%s/SYSTEM/HORIZON.SYS", M.mb.root ? M.mb.root : ".");
    FILE *f = M.mb.root ? fopen(path, "rb") : NULL;
    if (f) fclose(f); else snprintf(path, sizeof path, "%s", restart_prog);
    fprintf(stderr, "emu816: restart (%s): %s\n", mode ? "full" : "Horizon", path);
    reset_stub();
    load_file(path, 0x010000, 0xFF00);
    freddie_reset();
    sys_reset();
    nvc_reset();
    blitter_reset();
    audio_reset();
    mailbox_reset();
    cpu_reset(&M.cpu);
    machine_reschedule();
}

static uint32_t parse_addr(const char *s)
{
    char buf[32];
    int j = 0;
    if (*s == '$') s++;
    else if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) s += 2;
    for (; *s && j < 30; s++) if (*s != ':') buf[j++] = *s;
    buf[j] = 0;
    return (uint32_t)strtoul(buf, NULL, 16);
}

static void trace_line(void)
{
    Cpu65816 *c = &M.cpu;
    uint32_t pa = (uint32_t)c->pbr << 16 | c->pc;
    uint8_t op = bus_peek(pa), o[3];
    for (int i = 0; i < 3; i++) o[i] = bus_peek((pa & 0xFF0000) | ((pa + 1 + i) & 0xFFFF));
    int len = cpu_insn_len(c, op);
    char hex[16], dis[32], pf[9];
    int k = sprintf(hex, "%02X", op);
    for (int i = 0; i < len - 1; i++) k += sprintf(hex + k, " %02X", o[i]);
    cpu_format(c, op, o, dis, sizeof dis);
    const char *fl = "nvmxdizc";
    for (int i = 0; i < 8; i++) pf[i] = (c->p & (0x80 >> i)) ? (fl[i] - 32) : fl[i];
    pf[8] = 0;
    if (c->e) { pf[2] = '1'; pf[3] = (c->p & P_X) ? 'B' : 'b'; }
    fprintf(stderr, "%10llu %02X:%04X  %-11s %-16s A=%04X X=%04X Y=%04X S=%04X D=%04X DB=%02X P=%s %c %c%s\n",
            (unsigned long long)c->cycles, c->pbr, c->pc, hex, dis, c->a, c->x, c->y, c->s, c->d, c->dbr, pf,
            c->e ? 'E' : 'N', M.fr.mode_user ? 'U' : 'S', c->waiting ? " WAI" : "");
}

static void usage(void)
{
    fprintf(stderr,
        "usage: emu816 [options] PROGRAM.BIN\n"
        "  --sd DIR             host directory served as the SD card (mailbox)\n"
        "  --load FILE@ADDR     load FILE at 24-bit hex address ADDR (e.g. data.bin@02:0000)\n"
        "  --max-seconds N      stop after N seconds of emulated time (exit code 3)\n"
        "  --trace              one line per instruction on stderr\n"
        "  --shot FILE.ppm      write the 1280x720 output frame (at exit, or at --shot-at); repeatable\n"
        "  --shot-at SECONDS    emulated time for the preceding --shot (first VBLANK at or after it)\n"
        "  --stats              print speed and counters on stderr at exit\n"
        "  --boot-cart PATH     a cartridge (FAT path on --sd) the I/O processor loaded at power-on\n"
        "                       (boot=ash): CLASSIC_STATE ($1E) reports it\n"
        "  --card-date YYYY-MM-DDTHH:MM  the date STAT reports for every file this run did not write\n"
        "                       (the tests: a fresh copy of the card has no meaningful dates;\n"
        "                       also the files of --pc-folder)\n"
        "  --pc-folder DIR      the PC volume (PC link): /PC: paths are served from DIR\n"
        "  --pc-time YYYY-MM-DDTHH:MM  the PC's clock at power-on (it counts on with emulated time;\n"
        "                       default: the host's clock)\n"
        "  --pc-drop-at SECONDS the PC link drops at this emulated time\n"
        "  --pc-back-at SECONDS and comes back at this one (a new session)\n"
        "  --ideal-timing       every CPU cycle ideal: no cache misses, SDRAM write or sweep stalls,\n"
        "                       the blitter's older speed model (the timing before Horizon 0.19)\n"
        "  --console-us N       DBG_OUT busy for N us after each byte; bytes written while busy are dropped\n"
        "  --keys LIST          inject keys: \"t_ms:usage:down,...\" (usage in hex, e.g. 100:04:1,150:04:0)\n"
        "  --mouse LIST         inject mouse: \"t_ms:dx:dy:wheel:buttons,...\" (e.g. 100:5:-3:0:1)\n"
        "  --rev N              SYS_REV to report: 6 (no sound, no blitter), 7 (sound), 8 (+ blitter),\n"
        "                       9 (+ blitter lists, raster events at the beam, NV_FRAME),\n"
        "                       10 (+ sample player), 11 (default: + sprites, fine scrolling)\n"
        "  --wav FILE.wav       write the sample player's output (48 kHz stereo, without the POKEY sound)\n"
        "  --log-sound          print every accepted sound write ($DB00-$DB13) on stderr\n"
        "  --log-lau            print every write to Lau, the sample player ($DB20-$DBFF, REV 10), on stderr\n"
        "  --headless           no window (SDL builds open a 1280x720 window by default)\n"
#ifdef HAVE_SDL
        "  --fast               window open, but do not throttle to real time\n"
#endif
        );
    exit(1);
}

int main(int argc, char **argv)
{
    const char *prog = NULL, *sd = NULL;
    const char *loads[64];
    int nloads = 0, stats = 0;
    double console_us = 0;
    double max_sec = -1;
    const char *wav_path = NULL;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (!strcmp(a, "--sd") && i + 1 < argc) sd = argv[++i];
        else if (!strcmp(a, "--load") && i + 1 < argc && nloads < 64) loads[nloads++] = argv[++i];
        else if (!strcmp(a, "--max-seconds") && i + 1 < argc) max_sec = atof(argv[++i]);
        else if (!strcmp(a, "--trace")) M.trace = 1;
        else if (!strcmp(a, "--shot") && i + 1 < argc && nshots < MAXSHOTS) {
            shot_path[nshots] = argv[++i];
            shot_at[nshots++] = 1e30;                  /* at exit unless --shot-at follows */
        }
        else if (!strcmp(a, "--shot-at") && i + 1 < argc && nshots) shot_at[nshots - 1] = atof(argv[++i]);
        else if (!strcmp(a, "--stats")) stats = 1;
        else if (!strcmp(a, "--ideal-timing")) M.fr.ideal = 1;
        else if (!strcmp(a, "--boot-cart") && i + 1 < argc) mailbox_boot_cart = argv[++i];
        else if ((!strcmp(a, "--card-date") || !strcmp(a, "--pc-time")) && i + 1 < argc) {
            struct tm tm = { 0 };
            if (sscanf(argv[++i], "%d-%d-%dT%d:%d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday, &tm.tm_hour, &tm.tm_min) != 5) usage();
            tm.tm_year -= 1900; tm.tm_mon -= 1; tm.tm_isdst = -1;
            if (a[2] == 'c') mailbox_card_date = mktime(&tm); else mailbox_pc_time = mktime(&tm);
        }
        else if (!strcmp(a, "--pc-folder") && i + 1 < argc) mailbox_pc_root = argv[++i];
        else if (!strcmp(a, "--pc-drop-at") && i + 1 < argc) mailbox_pc_drop = atof(argv[++i]);
        else if (!strcmp(a, "--pc-back-at") && i + 1 < argc) mailbox_pc_back = atof(argv[++i]);
        else if (!strcmp(a, "--console-us") && i + 1 < argc) console_us = atof(argv[++i]);
        else if (!strcmp(a, "--keys") && i + 1 < argc) parse_keys(argv[++i]);
        else if (!strcmp(a, "--mouse") && i + 1 < argc) parse_mouse(argv[++i]);
        else if (!strcmp(a, "--rev") && i + 1 < argc) M.sys.rev = (uint8_t)strtol(argv[++i], NULL, 0);
        else if (!strcmp(a, "--log-sound")) M.sys.snd_log |= 1;
        else if (!strcmp(a, "--log-lau")) M.sys.snd_log |= 2;
        else if (!strcmp(a, "--wav") && i + 1 < argc) wav_path = argv[++i];
#ifdef HAVE_SDL
        else if (!strcmp(a, "--headless")) sdl_on = 0;
        else if (!strcmp(a, "--fast")) fast = 1;
#else
        else if (!strcmp(a, "--headless")) ;
#endif
        else if (a[0] == '-' && a[1]) usage();
        else if (!prog) prog = a;
        else usage();
    }
    if (!prog) usage();
    if (nkeys) qsort(keys, nkeys, sizeof *keys, cmpkey);

    /* memory as the I/O processor leaves it: junk, reset stub, vectors, program */
    M.ram = malloc(RAM_SIZE);
    M.nvc.out = calloc(NV_OUT_W * NV_OUT_H, 4);
    if (!M.ram || !M.nvc.out) { fprintf(stderr, "emu816: out of memory\n"); return 1; }
    for (uint32_t i = 0; i < RAM_SIZE; i++) M.ram[i] = 0xEA ^ (i & 0xFF);
    reset_stub();
    load_file(prog, 0x010000, 0xFF00);              /* the firmware reads at most $FF00 bytes */
    for (int i = 0; i < nloads; i++) {
        char path[4096];
        snprintf(path, sizeof path, "%s", loads[i]);
        char *at = strrchr(path, '@');
        if (!at) usage();
        *at = 0;
        uint32_t addr = parse_addr(at + 1);
        if (addr >= RAM_SIZE) { fprintf(stderr, "emu816: %s: address beyond RAM\n", loads[i]); return 1; }
        load_file(path, addr, RAM_SIZE);
    }

    M.mb.root = sd;
    if (mailbox_pc_root) {                              /* the PC volume's folder must exist */
        struct stat st;
        if (stat(mailbox_pc_root, &st) || !S_ISDIR(st.st_mode)) {
            fprintf(stderr, "emu816: --pc-folder %s: not a folder\n", mailbox_pc_root);
            return 1;
        }
    }
    restart_prog = prog;
    M.nvc.on_frame = on_frame;
    for (int i = 0; i < nshots; i++) if (shot_at[i] > 1e29 || shot_at[i] < 0.1) M.nvc.want = 1;
#ifdef HAVE_SDL
    if (sdl_on) M.nvc.want = 1;
#endif
    if (wav_path && audio_wav_open(wav_path)) { fprintf(stderr, "emu816: cannot write %s\n", wav_path); return 1; }
    cpu_init(&M.cpu, NULL, bus_read, bus_write);
    freddie_reset();
    M.sys.console_cycles = (uint64_t)(console_us * CPU_HZ / 1e6 + 0.5);
    sys_reset();
    nvc_reset();
    blitter_reset();
    audio_reset();
    mailbox_reset();
    cpu_reset(&M.cpu);
    machine_reschedule();

#ifdef HAVE_SDL
    if (sdl_on) {
        if (SDL_Init(SDL_INIT_VIDEO)) { fprintf(stderr, "SDL: %s\n", SDL_GetError()); return 1; }
        win = SDL_CreateWindow("Atari816 (emu816)", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                               NV_OUT_W, NV_OUT_H, 0);
        ren = SDL_CreateRenderer(win, -1, 0);
        tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, NV_OUT_W, NV_OUT_H);
        t_start_real = now_real();
    }
#endif

    uint64_t limit = max_sec >= 0 ? (uint64_t)(max_sec * CPU_HZ) : UINT64_MAX;
    clock_t t0 = clock();
    Cpu65816 *c = &M.cpu;
    int rc = 0;

    while (!c->stopped) {
        if (c->cycles >= M.next_event) {
            machine_sync_slow();
            if (M.mb.restart) machine_restart();
        }
        if (c->waiting && !c->nmi && !c->irq) {     /* WAI: jump to the next device event */
            c->cycles = M.next_event > c->cycles ? M.next_event : c->cycles + 1;
            if (c->cycles >= limit) { rc = 3; break; }
            continue;
        }
        if (M.trace) {
            if (!c->just_int && (c->nmi || (c->irq && !c->poll_i)))
                fprintf(stderr, "%10llu *** %s\n", (unsigned long long)c->cycles, c->nmi ? "NMI" : "IRQ");
            else trace_line();
        }
        uint64_t na = c->n_abort;
        cpu_step(c);
        if (M.trace && c->n_abort != na)
            fprintf(stderr, "%10llu *** ABORT at %06X cause %02X\n", (unsigned long long)c->cycles,
                    M.fr.abort_addr, M.fr.abort_cause);
        if (c->cycles >= limit) { rc = 3; break; }
    }
    fflush(stdout);
    audio_wav_close();

    for (int i = 0; i < nshots; i++) if (!shot_done[i]) {
        nvc_render();
        if (nvc_write_ppm(shot_path[i])) fprintf(stderr, "emu816: cannot write %s\n", shot_path[i]);
    }
    if (stats) {
        double host = (double)(clock() - t0) / CLOCKS_PER_SEC, emu = c->cycles / CPU_HZ;
        fprintf(stderr, "emu816: %s after %.3f s emulated (%llu cycles), %.3f s host: %.1f MHz (%.1fx real time)\n",
                rc == 3 ? "time limit" : "STP", emu, (unsigned long long)c->cycles, host,
                host > 0 ? c->cycles / host / 1e6 : 0, host > 0 ? emu / host : 0);
        fprintf(stderr, "emu816: %llu instructions, %llu IRQ, %llu NMI, %llu ABORT, %llu refused accesses, "
                "%llu mailbox requests, %llu blits, %llu frames\n",
                (unsigned long long)c->n_insn, (unsigned long long)c->n_irq, (unsigned long long)c->n_nmi,
                (unsigned long long)c->n_abort, (unsigned long long)M.fr.n_refused, (unsigned long long)M.mb.n_req,
                (unsigned long long)M.bl.n_blits, (unsigned long long)M.nvc.frames);
        fprintf(stderr, "emu816: REV $%02X, %llu blit pixels, %llu blitter busy cycles, %llu STARTs while busy, "
                "%llu register writes while busy, %llu stale reads, "
                "%llu sound writes (%llu ignored: not frozen)\n", M.sys.rev,
                (unsigned long long)M.bl.n_pixels, (unsigned long long)M.bl.busy_cycles,
                (unsigned long long)M.bl.n_busy_starts, (unsigned long long)M.bl.n_busy_writes,
                (unsigned long long)M.bl.n_stale_reads, (unsigned long long)M.sys.snd_writes,
                (unsigned long long)M.sys.snd_ignored);
        fprintf(stderr, "emu816: %llu blitter lists (%llu records), %llu audio samples, %llu KEYON writes\n",
                (unsigned long long)M.bl.n_lists, (unsigned long long)M.bl.n_records,
                (unsigned long long)M.au.n_samples, (unsigned long long)M.au.n_keyon);
        fprintf(stderr, "emu816: memory timing%s: %llu cache fills, %llu RAM writes, %llu cache sweeps, "
                "%llu stall cycles (%.1f%%)\n", M.fr.ideal ? " off (--ideal-timing)" : "",
                (unsigned long long)M.fr.n_fills, (unsigned long long)M.fr.n_wrs,
                (unsigned long long)M.fr.n_sweeps, (unsigned long long)M.fr.n_stall,
                c->cycles ? 100.0 * M.fr.n_stall / c->cycles : 0.0);
        if (M.sys.console_cycles)
            fprintf(stderr, "emu816: %llu DBG_OUT bytes dropped (console busy)\n", (unsigned long long)M.sys.dbg_dropped);
    }
#ifdef HAVE_SDL
    if (sdl_on) SDL_Quit();
#endif
    return rc;
}

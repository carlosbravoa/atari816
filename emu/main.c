/* emu816 — software model of the Atari816 native side (65C816 + FREDDIE II + system I/O).
 *
 *   emu816 [--sd DIR] [--load FILE@ADDR]... [--max-seconds N] [--trace] [--prof FILE]
 *          [--shot FILE.ppm] [--shot-at SECONDS] [--stats] [--headless] [--fast] PROGRAM.BIN
 */
#include "machine.h"
#include "net.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>
#ifdef HAVE_SDL
#include <SDL.h>
#endif

Machine M;

/* --stop-on TEXT (repeatable), --stop-on-delay MS: the run ends when the program prints a
 * console line holding one of the texts (MS ms of emulated time later; --max-seconds stays
 * the upper limit); exit code 4 and a line on stderr say so (run816.py reads it). The line
 * is matched in emu_console_byte */
#define MAXSTOP 16
static const char *stop_text[MAXSTOP];
static int nstop, stop_hit = -1;                /* the text met (-1: none yet) */
static double stop_delay_ms;
static uint64_t run_limit = UINT64_MAX, stop_cycle;

#define MAXSHOTS 16
static const char *shot_path[MAXSHOTS];
static double shot_at[MAXSHOTS];
static int shot_done[MAXSHOTS], nshots;
#ifdef HAVE_SDL
static int sdl_on = 1, fast, mute;
static SDL_AudioDeviceID adev;      /* the live sound (0: none) */
#endif

/* ── --prof: the CPU's cycles by address (user mode), by syscall, in the kernel, idle ──
 * Written at exit as text (sdk/c/game/tests/tools/prof816.py reads it): a header, then
 * "u BBPPPP cycles opcode" for every user-mode instruction address that ran, "s NN cycles
 * calls" for every syscall (COP #NN: the kernel's cycles from the COP to the return to
 * user mode), "k cycles" (the kernel otherwise: interrupts, other tasks) and "i cycles"
 * (WAI). Only between --prof-from and --prof-to (emulated seconds). */
static const char *prof_path;
static const char *dump_ram;            /* --dump-ram: the RAM written at exit */
static double prof_from, prof_to = 1e30;
static uint32_t *prof_u;            /* cycles by 24-bit address (user mode) */
static uint8_t *prof_op;            /* the opcode seen there */
static uint64_t prof_sys[256], prof_sysn[256], prof_k, prof_i;
static int prof_insys = -1;

/* --cpu-slow PCT, --kernel-slow PCT: every instruction (--kernel-slow: every one run in
 * supervisor mode) takes PCT % more cycles (negative: fewer, down to -50). A test aid: it
 * moves the timing of all the CPU does, to show which tests depend on it; waiting (WAI),
 * the devices and the scripted input keep their times */
static int cpu_slow, kernel_slow;
static int64_t slow_acc;

static void slow_adjust(Cpu65816 *c, uint64_t c0, int user)
{
    int pct = cpu_slow + (user ? 0 : kernel_slow);
    if (!pct || c->cycles <= c0) return;
    slow_acc += (int64_t)(c->cycles - c0) * pct;
    int64_t q = slow_acc / 100;
    slow_acc -= q * 100;
    if (q < 0 && (uint64_t)-q >= c->cycles - c0) q = -(int64_t)(c->cycles - c0 - 1);
    c->cycles += q;
}

static void prof_write(void)
{
    FILE *f = fopen(prof_path, "w");
    if (!f) { fprintf(stderr, "emu816: cannot write %s\n", prof_path); return; }
    fprintf(f, "# emu816 --prof: %.3f to %.3f s; cycles a second %.0f\n", prof_from,
            prof_to > 1e29 ? -1.0 : prof_to, CPU_HZ);
    for (uint32_t a = 0; a < 0x1000000; a++)
        if (prof_u[a]) fprintf(f, "u %06X %u %02X\n", a, prof_u[a], prof_op[a]);
    for (int n = 0; n < 256; n++)
        if (prof_sys[n] || prof_sysn[n])
            fprintf(f, "s %02X %llu %llu\n", n, (unsigned long long)prof_sys[n],
                    (unsigned long long)prof_sysn[n]);
    fprintf(f, "k %llu\ni %llu\n", (unsigned long long)prof_k, (unsigned long long)prof_i);
    fclose(f);
}

/* ── host keyboard: SDL or --keys ── */
#define HID_F12 0x45
/* --kbd-release MS: the I/O processor's firmware before 2026-11 released every key when no
 * keyboard report had come for 1 s; a USB keyboard (through the CH9350 or the Pico/TinyUSB
 * bridge) reports only when its keys change, so a key held longer went up by itself. This
 * models it (a report = any key change), to reproduce that board's behaviour. 0: off */
static uint64_t kbd_release, kbd_last;
static void host_key(int usage, int down)
{
    if (usage <= 0 || usage > 0xFF) return;
    kbd_last = M.cpu.cycles;
    if (usage == HID_F12 && down) sys_raise_nmi(1);     /* F12: SYSTEM_KEY NMI and a KEY event */
    mailbox_key(usage, down);
}

/* scripted input (--keys, --mouse), sorted by time. More kinds in --keys, so a script can
 * follow the program's progress instead of the clock:
 *   t:W:HEX  a wait: from t on, nothing more until the program prints a console line
 *            holding that text; then the rest comes as late as the wait took
 *   t:Q:HEX  a wait for a still screen (HEX = a frame count N in decimal, as text): from t
 *            on, nothing more until the picture sent to the monitor stayed the same for N
 *            frames in a row; the rest as late as the wait took
 *   t:C:     a wait for a change: from t on, until a frame differs from the one before it
 *            (it ends at that frame's start: the rest keeps its place in the frames)
 *   t:A:     a wait for a sound: from t on, until a voice of Lau, the sample player, is
 *            started (KEYON); the rest as late as the wait took (to the cycle)
 *   t:S:HEX  a screenshot (that file, two vertical blanks later)
 *   t:M:     a step mark: an input script's line starts here */
enum { K_KEY, K_MOUSE, K_WAIT, K_SHOT, K_MARK, K_STILL, K_CHANGE, K_SOUND };
typedef struct { uint64_t cycle; int seq; uint8_t mouse, usage, down, btn; int16_t dx, dy, wheel; uint8_t kind; char *text; } KeyAt;
static KeyAt *keys;
static int nkeys, nextkey;
static const char *key_wait;            /* the text being waited for, NULL: none */
static uint64_t key_wait_at;
static const char *key_shot;            /* a screenshot due (its file), in key_shot_req frames */
static int key_shot_req, key_shot_tries;
static int key_still, key_still_n;      /* a still-screen wait: its frames (0: none), met so far */
static uint64_t key_still_hash;         /* the last frame's hash */
static int key_change;                  /* a wait for a changed frame */
static int key_sound;                   /* a wait for a Lau KEYON */
/* the console's lines since the script's last step mark (the start of the last input line
 * before a wait): a wait is also met by a line that came before its own time (the program
 * may be quicker than the script thought, or answer while that line's keys are still being
 * sent). Key and mouse events do not forget lines; a mark does. A line that meets a wait is
 * used up (two waits for one text need two lines); the others stay for the waits after it.
 * Without marks in the list every line since the start counts */
#define KH_N 64
static char key_hist[KH_N][128];
static int key_hist_n;

static int key_hist_take(const char *text)
{
    for (int i = 0; i < key_hist_n; i++)
        if (strstr(key_hist[i], text)) {
            memmove(key_hist + i, key_hist + i + 1, sizeof key_hist[0] * (key_hist_n - i - 1));
            key_hist_n--;
            return 1;
        }
    return 0;
}

/* a wait is over: the rest of the script moves on by as long as it took */
static void keys_wait_over(void)
{
    uint64_t d = M.cpu.cycles > key_wait_at ? M.cpu.cycles - key_wait_at : 0;
    for (int i = nextkey; i < nkeys; i++) keys[i].cycle += d;
    key_wait = NULL;
    key_still = key_change = key_sound = 0;
    machine_reschedule();
}

#define KEYS_WAITING (key_wait || key_still || key_change || key_sound)

/* (each frame of a still-screen or change wait) the picture as the monitor gets it,
 * compared with the frame before by a 64-bit FNV-1a hash of its pixels */
static uint64_t frame_hash(void)
{
    uint64_t h = 1469598103934665603ULL;
    nvc_render();
    const uint32_t *p = M.nvc.out;
    for (int i = 0; i < NV_OUT_W * NV_OUT_H; i++) h = (h ^ p[i]) * 1099511628211ULL;
    return h;
}

/* A still-screen wait forgives a frame that differs alone (the next one is the picture again:
 * a raster colour change landing a line late, now and then): it neither counts nor restarts
 * the count. The picture it settled on is kept (still_ref) for the screenshot that follows
 * it: that one is taken from a frame showing that picture. */
static uint64_t key_odd_hash;           /* a frame that differed, not yet known to be a glitch */
static int key_odd;
static int still_ref_ok;                /* still_ref: the picture of the last still-screen wait */
static uint64_t still_ref;

static void keys_still_frame(void)
{
    uint64_t h = frame_hash();
    if (key_still_n < 0) {                  /* the first two frames only set the hash (the */
        key_still_n++;                      /* first may be fetched in part, when nobody */
        key_still_hash = h;                 /* looked at the output before) */
        key_odd = 0;
        return;
    }
    int same = h == key_still_hash;
    if (key_change) {
        key_still_hash = h;
        if (!same) keys_wait_over();
        return;
    }
    if (same) {                             /* (a frame that differed alone: forgiven) */
        key_odd = 0;
        if (++key_still_n >= key_still) {
            still_ref = h;
            still_ref_ok = 1;
            keys_wait_over();
        }
    } else if (key_odd && h == key_odd_hash) {  /* a new picture, two frames: start again */
        key_still_hash = h;
        key_still_n = 1;
        key_odd = 0;
    } else {
        key_odd = 1;
        key_odd_hash = h;
    }
}

/* (audio.c) a Lau voice was started */
void emu_lau_keyon(void)
{
    if (key_sound) keys_wait_over();
}

static void keys_due(uint64_t now)
{
    while (!KEYS_WAITING && nextkey < nkeys && keys[nextkey].cycle <= now) {
        KeyAt *k = &keys[nextkey++];
        if (k->kind == K_MARK) { key_hist_n = 0; continue; }
        if (k->kind == K_STILL || k->kind == K_CHANGE) {
            if (k->kind == K_STILL) key_still = atoi(k->text) > 0 ? atoi(k->text) : 1;
            else key_change = 1;
            key_still_n = -2;                           /* (two frames only start the count) */
            key_wait_at = k->cycle;
            M.nvc.want = 1;                             /* the next frames fetched whole */
            continue;
        }
        if (k->kind == K_SOUND) {
            key_sound = 1;
            key_wait_at = k->cycle;
            continue;
        }
        if (k->kind == K_WAIT) {
            if (key_hist_take(k->text)) continue;       /* met already */
            key_wait = k->text; key_wait_at = k->cycle;
            continue;
        }
        if (k->kind == K_SHOT) { key_shot = k->text; key_shot_req = 3; key_shot_tries = 0; continue; }
        still_ref_ok = 0;                               /* (input: the picture may change) */
        if (k->mouse) mailbox_mouse(k->btn, k->dx, k->dy, k->wheel);
        else host_key(k->usage, k->down);
    }
}

/* (a console line) kept for the waits to come, or the wait is over: the rest of the script
 * moves on by the time it took */
static void keys_wait_line(const char *line)
{
    if (!key_wait || !strstr(line, key_wait)) {
        if (key_hist_n == KH_N) { memmove(key_hist, key_hist + 1, sizeof key_hist[0] * (KH_N - 1)); key_hist_n--; }
        snprintf(key_hist[key_hist_n++], sizeof key_hist[0], "%s", line);
        return;
    }
    keys_wait_over();
}

static char *unhex(const char *s, int n)
{
    char *t = malloc(n / 2 + 1);
    for (int i = 0; i < n / 2; i++) { unsigned v; sscanf(s + 2 * i, "%2x", &v); t[i] = (char)v; }
    t[n / 2] = 0;
    return t;
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
        char kind;
        if (sscanf(s, "%lf:%c:%n", &ms, &kind, &n) == 2 && n && (kind == 'W' || kind == 'S' || kind == 'M' || kind == 'Q' || kind == 'C' || kind == 'A')) {
            int h = (int)strspn(s + n, "0123456789abcdefABCDEF");
            keys = realloc(keys, (nkeys + 1) * sizeof *keys);
            keys[nkeys] = (KeyAt){ .cycle = (uint64_t)(ms * CPU_HZ / 1000.0), .seq = nkeys,
                                   .kind = kind == 'W' ? K_WAIT : kind == 'S' ? K_SHOT : kind == 'Q' ? K_STILL :
                                           kind == 'C' ? K_CHANGE : kind == 'A' ? K_SOUND : K_MARK,
                                   .text = unhex(s + n, h) };
            nkeys++;
            s += n + h;
            if (*s == ',') s++;
            continue;
        }
        n = 0;
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
        keys[nkeys] = (KeyAt){ .cycle = (uint64_t)(ms * CPU_HZ / 1000.0), .seq = nkeys, .mouse = 1, .btn = b, .dx = dx, .dy = dy, .wheel = w, .kind = K_MOUSE };
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
    se = opl_next_event();
    if (se < n) n = se;
    if (!KEYS_WAITING && nextkey < nkeys && keys[nextkey].cycle < n) n = keys[nextkey].cycle;
    if (kbd_release && kbd_last && kbd_last + kbd_release < n) n = kbd_last + kbd_release;
    if (stop_hit >= 0 && run_limit < n) n = run_limit;  /* (a WAI ends the run on time) */
    M.next_event = n;
}

void machine_sync_slow(void)
{
    uint64_t now = M.cpu.cycles;
    sys_update(now);
    blitter_update(now);
    audio_update(now);
    opl_update(now);
    nvc_update(now);
    keys_due(now);
    if (kbd_release && kbd_last && now >= kbd_last + kbd_release) {
        Mailbox *m = &M.mb;                             /* the old firmware's timeout */
        for (int i = 0; i < 4; i++)
            if (m->kb_now[i]) mailbox_key(m->kb_now[i], 0);
        for (int i = 0; i < 8; i++)
            if (m->kb_now_mods & (1 << i)) mailbox_key(0xE0 + i, 0);
        kbd_last = 0;
    }
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

/* the live sound: the samples made since the last frame, queued for the host. The device waits
 * until 60 ms are queued (at the start, and again after running dry: emulated time trails real
 * time a little); when emulated time runs ahead (--fast) the queue is kept to about 100 ms and
 * the rest is dropped */
static void sdl_audio(void)
{
    static int primed;
    int16_t buf[2 * 1024];
    int n;
    if (primed && SDL_GetQueuedAudioSize(adev) == 0) { SDL_PauseAudioDevice(adev, 1); primed = 0; }
    while ((n = audio_live_take(buf, 1024)) > 0)
        if (SDL_GetQueuedAudioSize(adev) < 48000 / 10 * 4) SDL_QueueAudio(adev, buf, n * 4);
    if (!primed && SDL_GetQueuedAudioSize(adev) >= 48000 * 6 / 100 * 4) { SDL_PauseAudioDevice(adev, 0); primed = 1; }
}

static void sdl_frame(void)
{
    if (adev) sdl_audio();
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

/* --shot-on TEXT, --shot-on-prefix PATH: a screenshot when the program prints a console line
 * holding TEXT (PATH1.ppm, PATH2.ppm, ...): taken two vertical blanks later (the frame then
 * fetched whole), so a program shows what it wants seen, prints the line and holds the
 * picture for a few frames: pictures at given points of a program's own progress, whatever
 * its timing */
static const char *shoton_text, *shoton_prefix;
static char shoton_line[256];
static int shoton_len, shoton_req, shoton_n;

/* --dump-ram-on TEXT, --dump-ram-prefix PATH: the 8 MB of RAM written (PATH1.bin, PATH2.bin, ...)
 * each time the program prints a console line holding TEXT, at once (the state at that point
 * of the program's progress) */
static const char *dumpon_text, *dumpon_prefix;
static int dumpon_n;

static void dump_ram_to(const char *path)
{
    FILE *f = fopen(path, "wb");
    if (!f || fwrite(M.ram, 1, RAM_SIZE, f) != RAM_SIZE) fprintf(stderr, "emu816: cannot write %s\n", path);
    if (f) fclose(f);
}

/* --watch ADDR[:LEN]: every write into the physical range is logged on stderr:
 *   watch T_US PC=BB:PPPP U|S task N DB=BB $AAAAAA = $VV (was $OO)
 * (PC the instruction's own address; "dma" for the I/O processor's or the blitter's writes) */
static unsigned long watch_max = 200000, watch_n;

void watch_hit(uint32_t a, uint8_t v, int dma)
{
    if (watch_n >= watch_max) return;
    if (++watch_n == watch_max) fprintf(stderr, "watch: --watch-max %lu lines reached\n", watch_max);
    unsigned long long us = (unsigned long long)(M.cpu.cycles / CPU_HZ * 1e6);
    if (dma)
        fprintf(stderr, "watch %llu dma $%06X = $%02X\n", us, a, v);
    else
        fprintf(stderr, "watch %llu PC=%02X:%04X %c task %u DB=%02X $%06X = $%02X (was $%02X)\n", us,
                M.ipc >> 16, M.ipc & 0xFFFF, M.fr.mode_user ? 'U' : 'S', M.fr.cur_task, M.cpu.dbr,
                a, v, M.ram[a]);
}


/* --console-times: every console line on stdout starts with the emulated time of its first
 * byte, "[SSSS.UUUUUU] ", in seconds since power-on: the base of --log-lau-us, --log-opl-us,
 * --log-sound-us and --watch (their microseconds are SSSSUUUUUU) */
static int console_times, con_bol = 1, con_esc;

static unsigned long long emu_us(void) { return (unsigned long long)(M.cpu.cycles * 1e6 / CPU_HZ); }

/* a byte written to DBG_OUT (sysblock.c): stdout, and the console's lines watched */
void emu_console_byte(uint8_t v)
{
    if (console_times) {
        /* a line starts after LF, CR or FF (the shell's clear screen) outside an escape
         * (ESC x, ESC Y r c); empty lines get no time */
        if (con_esc) con_esc = con_esc == 1 && v == 'Y' ? 3 : con_esc - 1;
        else if (v == 10 || v == 13 || v == 12) con_bol = 1;
        else {
            if (con_bol) {
                unsigned long long us = emu_us();
                printf("[%4llu.%06llu] ", us / 1000000, us % 1000000);
                con_bol = 0;
            }
            if (v == 27) con_esc = 1;
        }
    }
    putchar(v);
    if (v == 10) fflush(stdout);
    if (!shoton_text && !nkeys && !dumpon_text && !nstop) return;
    if (v == 10 || v == 13) {
        shoton_line[shoton_len] = 0;
        for (int i = 0; i < nstop && stop_hit < 0 && shoton_len; i++)
            if (strstr(shoton_line, stop_text[i])) {
                stop_hit = i;
                stop_cycle = M.cpu.cycles;
                uint64_t at = M.cpu.cycles + (uint64_t)(stop_delay_ms * CPU_HZ / 1000.0);
                if (at < run_limit) run_limit = at;
            }
        if (shoton_text && shoton_len && strstr(shoton_line, shoton_text) && !shoton_req) shoton_req = 3;
        if (dumpon_text && shoton_len && strstr(shoton_line, dumpon_text)) {
            char path[1024];
            snprintf(path, sizeof path, "%s%d.bin", dumpon_prefix ? dumpon_prefix : "dumpon", ++dumpon_n);
            dump_ram_to(path);
        }
        if (shoton_len) keys_wait_line(shoton_line);
        shoton_len = 0;
    } else if (shoton_len < (int)sizeof shoton_line - 1)
        shoton_line[shoton_len++] = (char)v;
}

static void on_frame(void)
{
    /* Marga only fetches and keeps lines when someone will look at them */
    double now = M.cpu.cycles / CPU_HZ;
    if (key_still || key_change) {
        M.nvc.want = 1;
        keys_still_frame();
    }
    if (key_shot_req) {
        M.nvc.want = 1;
        if (--key_shot_req == 0) {
            /* after a still-screen wait: from a frame that shows the picture it settled on
             * (not one a glitch touched; 60 frames at most) */
            if (still_ref_ok && frame_hash() != still_ref && ++key_shot_tries < 60)
                key_shot_req = 1;
            else {
                nvc_render();
                if (nvc_write_ppm(key_shot)) fprintf(stderr, "emu816: cannot write %s\n", key_shot);
            }
        }
    }
    if (shoton_req) {
        M.nvc.want = 1;
        if (--shoton_req == 0) {
            char path[1024];
            snprintf(path, sizeof path, "%s%d.ppm", shoton_prefix ? shoton_prefix : "shoton", ++shoton_n);
            nvc_render();
            if (nvc_write_ppm(path)) fprintf(stderr, "emu816: cannot write %s\n", path);
        }
    }
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
    opl_reset();
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
        "  --max-seconds N      stop after N seconds of emulated time (exit code 3; STP: 0)\n"
        "  --trace              one line per instruction on stderr\n"
        "  --prof FILE          the CPU's cycles by instruction address, syscall, kernel, idle (at exit)\n"
        "  --prof-from S, --prof-to S  only between these emulated seconds\n"
        "  --shot FILE.ppm      write the 1280x720 output frame (at exit, or at --shot-at); repeatable\n"
        "  --dump-ram FILE      write the 8 MB of RAM at exit (as a PC tool reading memory sees it)\n"
        "  --dump-ram-on TEXT   write it each time the program prints a console line holding TEXT, at once:\n"
        "                       PREFIXn.bin, n = 1, 2, ... (--dump-ram-prefix PREFIX; default dumpon)\n"
        "  --watch ADDR[:LEN]   log every write into physical RAM ADDR..ADDR+LEN-1 (hex; LEN default 1;\n"
        "                       repeatable, 16 at most) on stderr: the time (us), the instruction's\n"
        "                       PBR:PC, user/supervisor, the task, DBR, the value and the old value;\n"
        "                       \"dma\" for the I/O processor's and the blitter's writes\n"
        "  --watch-max N        at most N watch lines (default 200000)\n"
        "  --ram-fill HH        the RAM at power-on all HH (hex) instead of the pattern $EA ^ (address & $FF)\n"
        "  --ram-random SEED    ... or pseudo-random bytes from SEED: memory a program never wrote is\n"
        "                       whatever the board's was (programs that read it differ from run to run)\n"
        "  --shot-at SECONDS    emulated time for the preceding --shot (first VBLANK at or after it)\n"
        "  --shot-on TEXT       a screenshot each time the program prints a console line holding TEXT\n"
        "                       (two frames later): PREFIXn.ppm, n = 1, 2, ... (--shot-on-prefix PREFIX)\n"
        "  --stop-on TEXT       end the run when the program prints a console line holding TEXT\n"
        "                       (repeatable: any of them; --max-seconds stays the upper limit): exit\n"
        "                       code 4 and on stderr: emu816: stopped on \"TEXT\" at S.UUUUUU s\n"
        "  --stop-on-delay MS   ... MS ms of emulated time after that line (default 0: at once)\n"
        "  --console-times      each console line on stdout starts with its emulated time since\n"
        "                       power-on, \"[SSSS.UUUUUU] \" (the base of the --log-*-us microseconds)\n"
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
        "  --no-pc-print        the gateway cannot make PDFs (STAT /PC: without the PRINT bit 4)\n"
        "  --classic-print FILE@SECONDS  the classic Atari prints FILE (ATASCII, as P: sends it) at that\n"
        "                       emulated time: a print job /Printouts/... Atari.txt, finished 3 s later\n"
        "                       (through core/firmware/prnconv.c, as the firmware); repeatable\n"
        "  --net                the internet (PC link step 2): tcp://host:port are real host connections\n"
        "  --net-root DIR       ... and http://, https://, ftp:// URLs are served from DIR/host/path\n"
        "  --net-delay MS       the PC's time to answer a URL OPEN or STAT (default 0)\n"
        "  --card-kbps R:W      slow card: READ / LOAD at R KB/s, WRITE at W KB/s, + 1 ms a request\n"
        "  --card-free BYTES    the card has room for BYTES more (written in the run): then a WRITE writes\n"
        "                       short, as on a full card, and MKDIR is denied (tests)\n"
        "                       (0:0 = instant, the default; the board: about 170:100)\n"
        "  --card-board         the board's card, request by request, as the firmware of Horizon 0.30\n"
        "                       runs it (10.7 MHz): an OPEN or STAT 1.25 ms a folder level + the\n"
        "                       folder sectors scanned, a READ 0.5 ms + 0.86 ms a sector, ...:\n"
        "                       emu/README.md \"The card's speed\"; run816.py's default.\n"
        "                       --card-kbps instead: its simpler model\n"
        "  --card-board-old     --card-board as the firmware of v0.29 (the card at 1.34 MHz)\n"
        "  --card-board-at S    --card-board from S emulated seconds on (run816.py: from the\n"
        "                       program's start; the boot keeps the instant card its tests expect)\n"
        "  --card-costs O:S:C:CW:SK:X:R:W:RK:WK[:LV:SF:CR]  --card-board with these costs (ms: OPEN,\n"
        "                       STAT, CLOSE, CLOSE of a written file, SEEK, other; READ, WRITE fixed;\n"
        "                       KB/s: READ (a sector), WRITE; ms: a folder level, a SEEK into\n"
        "                       another cluster, a create; without the last three: 0)\n"
        "  --log-card           each card request's --card-board time on stderr\n"
        "  --pc-kbps R:W        slow PC volume: the same, + 6 ms a request (the board: about 100:55)\n"
        "  --ideal-timing       every CPU cycle ideal: no cache misses, SDRAM write or sweep stalls,\n"
        "                       the blitter's older speed model (the timing before Horizon 0.19)\n"
        "  --cpu-slow PCT       (test aid) every instruction takes PCT %% more cycles (-50 .. 1000; negative:\n"
        "                       fewer): the CPU's timing moved, the devices' and the script's kept\n"
        "  --kernel-slow PCT    the same for the instructions run in supervisor mode (the kernel) only\n"
        "  --console-us N       DBG_OUT busy for N us after each byte; bytes written while busy are dropped\n"
        "  --keys LIST          inject keys: \"t_ms:usage:down,...\" (usage in hex, e.g. 100:04:1,150:04:0)\n"
        "                       (also t_ms:W:HEX: wait until the console shows a line holding that text,\n"
        "                       the rest later by as long, or at once if one came since the last\n"
        "                       t_ms:M: (a step mark: an input line starts); t_ms:Q:HEX: wait until the\n"
        "                       picture stayed the same for N frames (HEX: N in decimal, as text), the\n"
        "                       rest later by as long; t_ms:C: wait until a frame differs from the one\n"
        "                       before; t_ms:A: wait until a Lau voice starts; t_ms:S:HEX: a screenshot)\n"
        "  --mouse LIST         inject mouse: \"t_ms:dx:dy:wheel:buttons,...\" (e.g. 100:5:-3:0:1)\n"
        "  --rev N              SYS_REV to report: 6 (no sound, no blitter), 7 (sound), 8 (+ blitter),\n"
        "                       9 (+ blitter lists, raster events at the beam, NV_FRAME),\n"
        "                       10 (+ sample player), 11 (+ sprites, fine scrolling),\n"
        "                       12 (+ OPL2 at $DB30, POKEY's native bank, no DACs),\n"
        "                       13 (default: + the blitter's colour remap: OPs 5 TABLE, 6-7 COPY(_KEY)_REMAP)\n"
        "  --wav FILE.wav       write the sound as the board's HDMI mixes it, without the classic machine's\n"
        "                       (POKEY, GTIA): Lau, the sample player, plus the OPL2 (48 kHz, 16-bit stereo)\n"
        "  --log-sound          print every accepted sound write ($DB00-$DB13; REV 12 $DB00-$DB0F) on stderr\n"
        "  --log-lau            print every write to Lau, the sample player ($DB20-$DBFF, REV 10), on stderr\n"
        "  --log-lau-us         the same, each line with the emulated time in microseconds: lau US $DBxx = $yy\n"
        "  --log-sound-us       as --log-sound, each line with the emulated time in microseconds: sound US $DBxx = $yy\n"
        "  --kbd-release MS     release the keys held when no key changed for MS ms (the firmware before 2026-11 did,\n"
        "                       after 1000 ms: a key held longer went up by itself on the board)\n"
        "  --log-opl            print every OPL2 data write ($DB31, REV 12) on stderr: opl $RR = $yy\n"
        "                       (RR the register selected at $DB30)\n"
        "  --log-opl-us         the same, with the emulated time in microseconds: opl US $RR = $yy\n"
        "  --headless           no window (SDL builds open a 1280x720 window by default)\n"
#ifdef HAVE_SDL
        "  --fast               window open, but do not throttle to real time\n"
        "  --mute               no live sound (the window plays Lau and the OPL2, as --wav records them)\n"
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
    int ram_fill = -1;                  /* -1: the pattern; -2: --ram-random; else the byte */
    uint32_t ram_seed = 0;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (!strcmp(a, "--sd") && i + 1 < argc) sd = argv[++i];
        else if (!strcmp(a, "--load") && i + 1 < argc && nloads < 64) loads[nloads++] = argv[++i];
        else if (!strcmp(a, "--max-seconds") && i + 1 < argc) max_sec = atof(argv[++i]);
        else if (!strcmp(a, "--trace")) M.trace = 1;
        else if (!strcmp(a, "--prof") && i + 1 < argc) prof_path = argv[++i];
        else if (!strcmp(a, "--prof-from") && i + 1 < argc) prof_from = atof(argv[++i]);
        else if (!strcmp(a, "--prof-to") && i + 1 < argc) prof_to = atof(argv[++i]);
        else if (!strcmp(a, "--shot") && i + 1 < argc && nshots < MAXSHOTS) {
            shot_path[nshots] = argv[++i];
            shot_at[nshots++] = 1e30;                  /* at exit unless --shot-at follows */
        }
        else if (!strcmp(a, "--shot-at") && i + 1 < argc && nshots) shot_at[nshots - 1] = atof(argv[++i]);
        else if (!strcmp(a, "--stats")) stats = 1;
        else if (!strcmp(a, "--dump-ram") && i + 1 < argc) dump_ram = argv[++i];
        else if (!strcmp(a, "--dump-ram-on") && i + 1 < argc) dumpon_text = argv[++i];
        else if (!strcmp(a, "--dump-ram-prefix") && i + 1 < argc) dumpon_prefix = argv[++i];
        else if (!strcmp(a, "--watch") && i + 1 < argc) {
            char buf[64];
            snprintf(buf, sizeof buf, "%s", argv[++i]);
            /* ADDR is BBAAAA or BB:AAAA; a last ':' after BBAAAA (or a second ':') starts LEN */
            char *colon = strrchr(buf, ':'), *b = buf + (buf[0] == '$');
            uint32_t len = 1;
            if (colon && (strchr(buf, ':') != colon || colon - b > 2)) {
                *colon = 0;
                len = (uint32_t)strtoul(colon + 1 + (colon[1] == '$'), NULL, 16);
            }
            uint32_t lo = parse_addr(buf);
            if (M.nwatch >= 16 || !len || lo >= RAM_SIZE) usage();
            M.watch_lo[M.nwatch] = lo;
            M.watch_hi[M.nwatch++] = lo + len;
        }
        else if (!strcmp(a, "--ram-fill") && i + 1 < argc) ram_fill = (int)(strtoul(argv[++i], NULL, 16) & 0xFF);
        else if (!strcmp(a, "--ram-random") && i + 1 < argc) { ram_fill = -2; ram_seed = (uint32_t)strtoul(argv[++i], NULL, 0); }
        else if (!strcmp(a, "--watch-max") && i + 1 < argc) watch_max = strtoul(argv[++i], NULL, 0);
        else if (!strcmp(a, "--ideal-timing")) M.fr.ideal = 1;
        else if ((!strcmp(a, "--cpu-slow") || !strcmp(a, "--kernel-slow")) && i + 1 < argc) {
            int v = atoi(argv[++i]);
            if (v < -50 || v > 1000) usage();
            if (a[2] == 'c') cpu_slow = v; else kernel_slow = v;
        }
        else if (!strcmp(a, "--boot-cart") && i + 1 < argc) mailbox_boot_cart = argv[++i];
        else if ((!strcmp(a, "--card-date") || !strcmp(a, "--pc-time")) && i + 1 < argc) {
            struct tm tm = { 0 };
            if (sscanf(argv[++i], "%d-%d-%dT%d:%d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday, &tm.tm_hour, &tm.tm_min) != 5) usage();
            tm.tm_year -= 1900; tm.tm_mon -= 1; tm.tm_isdst = -1;
            if (a[2] == 'c') mailbox_card_date = mktime(&tm); else mailbox_pc_time = mktime(&tm);
        }
        else if (!strcmp(a, "--pc-folder") && i + 1 < argc) mailbox_pc_root = argv[++i];
        else if (!strcmp(a, "--no-pc-print")) mailbox_no_pc_print = 1;
        else if (!strcmp(a, "--classic-print") && i + 1 < argc) { if (mailbox_classic_print(argv[++i])) usage(); }
        else if (!strcmp(a, "--net")) mailbox_net = 1;
        else if (!strcmp(a, "--net-root") && i + 1 < argc) mailbox_net_root = argv[++i];
        else if (!strcmp(a, "--net-delay") && i + 1 < argc) {
            mailbox_net_delay = atof(argv[++i]);
            if (mailbox_net_delay < 0) usage();
        }
        else if (!strcmp(a, "--pc-drop-at") && i + 1 < argc) mailbox_pc_drop = atof(argv[++i]);
        else if (!strcmp(a, "--pc-back-at") && i + 1 < argc) mailbox_pc_back = atof(argv[++i]);
        else if ((!strcmp(a, "--card-kbps") || !strcmp(a, "--pc-kbps")) && i + 1 < argc) {
            double *k = a[2] == 'c' ? mailbox_card_kbps : mailbox_pc_kbps;
            if (sscanf(argv[++i], "%lf:%lf", &k[0], &k[1]) != 2 || k[0] < 0 || k[1] < 0) usage();
        }
        else if (!strcmp(a, "--card-board")) mailbox_card_board = 1;
        else if (!strcmp(a, "--card-board-at") && i + 1 < argc) {
            mailbox_card_board = 1;
            mailbox_card_board_at = atof(argv[++i]);
        }
        else if (!strcmp(a, "--card-board-old")) {
            mailbox_card_board = 1;
            memcpy(mailbox_card_cost, mailbox_card_cost_old, sizeof mailbox_card_cost);
        }
        else if (!strcmp(a, "--log-card")) mailbox_log_card = 1;
        else if (!strcmp(a, "--card-costs") && i + 1 < argc) {
            double *c = mailbox_card_cost;
            mailbox_card_board = 1;
            c[CC_LEVEL] = c[CC_SEEKFAR] = c[CC_CREATE] = 0;     /* (the 10-value form: none) */
            int n = sscanf(argv[++i], "%lf:%lf:%lf:%lf:%lf:%lf:%lf:%lf:%lf:%lf:%lf:%lf:%lf", &c[0], &c[1], &c[2], &c[3],
                           &c[4], &c[5], &c[6], &c[7], &c[8], &c[9], &c[10], &c[11], &c[12]);
            if ((n != CC_N10 && n != CC_N) || c[CC_RKBPS] <= 0 || c[CC_WKBPS] <= 0) usage();
        }
        else if (!strcmp(a, "--card-free") && i + 1 < argc) mailbox_card_free = atoll(argv[++i]);
        else if (!strcmp(a, "--console-us") && i + 1 < argc) console_us = atof(argv[++i]);
        else if (!strcmp(a, "--keys") && i + 1 < argc) parse_keys(argv[++i]);
        else if (!strcmp(a, "--mouse") && i + 1 < argc) parse_mouse(argv[++i]);
        else if (!strcmp(a, "--rev") && i + 1 < argc) M.sys.rev = (uint8_t)strtol(argv[++i], NULL, 0);
        else if (!strcmp(a, "--log-sound")) M.sys.snd_log |= 1;
        else if (!strcmp(a, "--log-sound-us")) M.sys.snd_log |= 32;
        else if (!strcmp(a, "--shot-on") && i + 1 < argc) shoton_text = argv[++i];
        else if (!strcmp(a, "--shot-on-prefix") && i + 1 < argc) shoton_prefix = argv[++i];
        else if (!strcmp(a, "--stop-on") && i + 1 < argc) {
            if (nstop == MAXSTOP) usage();
            stop_text[nstop++] = argv[++i];
        }
        else if (!strcmp(a, "--stop-on-delay") && i + 1 < argc) {
            stop_delay_ms = atof(argv[++i]);
            if (stop_delay_ms < 0) usage();
        }
        else if (!strcmp(a, "--console-times")) console_times = 1;
        else if (!strcmp(a, "--kbd-release") && i + 1 < argc) kbd_release = (uint64_t)(atof(argv[++i]) * CPU_HZ / 1000.0);
        else if (!strcmp(a, "--log-lau")) M.sys.snd_log |= 2;
        else if (!strcmp(a, "--log-lau-us")) M.sys.snd_log |= 4;
        else if (!strcmp(a, "--log-opl")) M.sys.snd_log |= 8;
        else if (!strcmp(a, "--log-bankwrap")) cpu_log_bankwrap = 1;
        else if (!strcmp(a, "--log-opl-us")) M.sys.snd_log |= 16;
        else if (!strcmp(a, "--wav") && i + 1 < argc) wav_path = argv[++i];
#ifdef HAVE_SDL
        else if (!strcmp(a, "--headless")) sdl_on = 0;
        else if (!strcmp(a, "--fast")) fast = 1;
        else if (!strcmp(a, "--mute")) mute = 1;
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
    if (ram_fill == -1)
        for (uint32_t i = 0; i < RAM_SIZE; i++) M.ram[i] = 0xEA ^ (i & 0xFF);
    else if (ram_fill == -2) {                         /* --ram-random SEED: xorshift32 */
        uint32_t x = ram_seed ? ram_seed : 1;
        for (uint32_t i = 0; i < RAM_SIZE; i++) {
            x ^= x << 13; x ^= x >> 17; x ^= x << 5;
            M.ram[i] = (uint8_t)x;
        }
    } else
        memset(M.ram, ram_fill, RAM_SIZE);
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
    if (mailbox_net_root) {                             /* the Fetch service's folder too */
        struct stat st;
        if (stat(mailbox_net_root, &st) || !S_ISDIR(st.st_mode)) {
            fprintf(stderr, "emu816: --net-root %s: not a folder\n", mailbox_net_root);
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
    opl_reset();
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
        if (!mute && !SDL_InitSubSystem(SDL_INIT_AUDIO)) {   /* no sound device: play on silently */
            SDL_AudioSpec want = { .freq = 48000, .format = AUDIO_S16SYS, .channels = 2, .samples = 1024 };
            adev = SDL_OpenAudioDevice(NULL, 0, &want, NULL, 0);
            if (adev) audio_live_on();          /* (unpaused by sdl_audio) */
        }
        if (!mute && !adev) fprintf(stderr, "emu816: no live sound: %s\n", SDL_GetError());
        t_start_real = now_real();
    }
#endif

    uint64_t limit = max_sec >= 0 ? (uint64_t)(max_sec * CPU_HZ) : UINT64_MAX;
    run_limit = limit;                  /* (lowered by a --stop-on line) */
    clock_t t0 = clock();
    Cpu65816 *c = &M.cpu;
    int rc = 0;
    uint64_t wai_cycles = 0;            /* (--stats) cycles the CPU spent waiting in WAI */
    uint64_t prof_c0 = (uint64_t)(prof_from * CPU_HZ), prof_c1 = (uint64_t)(prof_to * CPU_HZ);
    if (prof_to > 1e29) prof_c1 = UINT64_MAX;
    if (prof_path) {
        prof_u = calloc(0x1000000, sizeof *prof_u);
        prof_op = calloc(0x1000000, 1);
        if (!prof_u || !prof_op) { fprintf(stderr, "emu816: out of memory (--prof)\n"); return 1; }
    }

    while (!c->stopped) {
        if (c->cycles >= M.next_event) {
            machine_sync_slow();
            if (M.mb.restart) machine_restart();
        }
        if (c->waiting && !c->nmi && !c->irq) {     /* WAI: jump to the next device event */
            uint64_t w0 = c->cycles;
            c->cycles = M.next_event > c->cycles ? M.next_event : c->cycles + 1;
            wai_cycles += c->cycles - w0;
            if (prof_u && w0 >= prof_c0 && w0 < prof_c1) prof_i += c->cycles - w0;
            if (c->cycles >= run_limit) break;
            continue;
        }
        if (M.trace) {
            if (!c->just_int && (c->nmi || (c->irq && !c->poll_i)))
                fprintf(stderr, "%10llu *** %s\n", (unsigned long long)c->cycles, c->nmi ? "NMI" : "IRQ");
            else trace_line();
        }
        uint64_t na = c->n_abort;
        M.ipc = (uint32_t)c->pbr << 16 | c->pc;
        if (prof_u) {
            uint64_t p0 = c->cycles;
            uint32_t pa = (uint32_t)c->pbr << 16 | c->pc;
            int user = M.fr.mode_user, wasw = c->waiting;
            uint8_t op = user ? bus_peek(pa) : 0;
            if (user) prof_insys = -1;
            cpu_step(c);
            if (p0 >= prof_c0 && p0 < prof_c1) {
                uint64_t d = c->cycles - p0;
                if (wasw) prof_i += d;
                else if (user) {
                    prof_u[pa] += (uint32_t)d;
                    prof_op[pa] = op;
                } else if (prof_insys >= 0) prof_sys[prof_insys] += d;
                else prof_k += d;
            }
            if (user && op == 0x02) {                         /* COP #n: a syscall */
                prof_insys = bus_peek((pa & 0xFF0000) | ((pa + 1) & 0xFFFF));
                if (p0 >= prof_c0 && p0 < prof_c1) prof_sysn[prof_insys]++;
            }
        } else if (cpu_slow || kernel_slow) {
            uint64_t s0 = c->cycles;
            int user = M.fr.mode_user;
            cpu_step(c);
            slow_adjust(c, s0, user);
        } else
            cpu_step(c);
        if (M.trace && c->n_abort != na)
            fprintf(stderr, "%10llu *** ABORT at %06X cause %02X\n", (unsigned long long)c->cycles,
                    M.fr.abort_addr, M.fr.abort_cause);
        if (c->cycles >= run_limit) break;
    }
    if (c->cycles >= run_limit) rc = stop_hit >= 0 && run_limit < limit ? 4 : 3;
    if (stop_hit >= 0) {                                /* (run816.py looks for this line) */
        unsigned long long us = (unsigned long long)(stop_cycle * 1e6 / CPU_HZ);
        fprintf(stderr, "emu816: stopped on \"%s\" at %llu.%06llu s%s\n", stop_text[stop_hit],
                us / 1000000, us % 1000000, rc == 4 ? "" : " (the run ended before its delay)");
    }
    fflush(stdout);
    audio_wav_close();
    if (prof_u) prof_write();
    if (key_wait)                                       /* (run816.py looks for this line) */
        fprintf(stderr, "emu816: the script still waits for \"%s\"\n", key_wait);
    if (key_still)
        fprintf(stderr, "emu816: the script still waits for a still screen (%d frames)\n", key_still);
    if (key_change)
        fprintf(stderr, "emu816: the script still waits for the screen to change\n");
    if (key_sound)
        fprintf(stderr, "emu816: the script still waits for a sound (a Lau KEYON)\n");

    for (int i = 0; i < nshots; i++) if (!shot_done[i] && (rc != 4 || shot_at[i] > 1e29)) {
        nvc_render();
        if (nvc_write_ppm(shot_path[i])) fprintf(stderr, "emu816: cannot write %s\n", shot_path[i]);
    }
    if (dump_ram) dump_ram_to(dump_ram);                /* the RAM at the end (tool tests) */
    if (stats) {
        double host = (double)(clock() - t0) / CLOCKS_PER_SEC, emu = c->cycles / CPU_HZ;
        fprintf(stderr, "emu816: %s after %.3f s emulated (%llu cycles), %.3f s host: %.1f MHz (%.1fx real time)\n",
                rc == 3 ? "time limit" : rc == 4 ? "--stop-on" : "STP", emu, (unsigned long long)c->cycles, host,
                host > 0 ? c->cycles / host / 1e6 : 0, host > 0 ? emu / host : 0);
        fprintf(stderr, "emu816: the CPU waited (WAI) %llu cycles: busy %.1f%%\n", (unsigned long long)wai_cycles,
                c->cycles ? 100.0 * (c->cycles - wai_cycles) / c->cycles : 0.0);
        fprintf(stderr, "emu816: %llu instructions, %llu IRQ, %llu NMI, %llu ABORT, %llu refused accesses, "
                "%llu mailbox requests, %llu blits, %llu frames\n",
                (unsigned long long)c->n_insn, (unsigned long long)c->n_irq, (unsigned long long)c->n_nmi,
                (unsigned long long)c->n_abort, (unsigned long long)M.fr.n_refused, (unsigned long long)M.mb.n_req,
                (unsigned long long)M.bl.n_blits, (unsigned long long)M.nvc.frames);
        {
            static const char *const nm[32] = { [1] = "OPEN", [2] = "CLOSE", [3] = "READ", [4] = "WRITE",
                [5] = "SEEK", [6] = "STAT", [7] = "READDIR", [8] = "MKDIR", [9] = "DELETE", [10] = "RENAME",
                [16] = "LOAD" };
            fprintf(stderr, "emu816: mailbox requests by kind:");
            for (int k = 0; k < 32; k++)
                if (M.mb.n_op[k])
                    fprintf(stderr, " %s %llu (%llu bytes)", nm[k] ? nm[k] : "op", (unsigned long long)M.mb.n_op[k],
                            (unsigned long long)M.mb.op_bytes[k]);
            fprintf(stderr, "\n");
        }
        fprintf(stderr, "emu816: REV $%02X, %llu blit pixels, %llu blitter busy cycles, %llu STARTs while busy, "
                "%llu register writes while busy, %llu stale reads, "
                "%llu sound writes (%llu ignored: not frozen)\n", M.sys.rev,
                (unsigned long long)M.bl.n_pixels, (unsigned long long)M.bl.busy_cycles,
                (unsigned long long)M.bl.n_busy_starts, (unsigned long long)M.bl.n_busy_writes,
                (unsigned long long)M.bl.n_stale_reads, (unsigned long long)M.sys.snd_writes,
                (unsigned long long)M.sys.snd_ignored);
        fprintf(stderr, "emu816: %llu blitter lists (%llu records), %llu remap tables loaded, %llu remapped "
                "copies, %llu audio samples, %llu KEYON writes, %llu OPL2 data writes\n",
                (unsigned long long)M.bl.n_lists, (unsigned long long)M.bl.n_records,
                (unsigned long long)M.bl.n_tables, (unsigned long long)M.bl.n_remaps,
                (unsigned long long)M.au.n_samples, (unsigned long long)M.au.n_keyon,
                (unsigned long long)M.opl.n_writes);
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

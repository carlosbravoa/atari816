/* hz_sys.c - the rest of upstream's seg009 on the Atari816: time (SDLPoP's 60-a-second
 * timers are the vertical blanks), the keyboard and the joystick (SDLPoP's key_states and
 * last_key_scancode, from hgame's events), files and folders, the start-up calls that
 * set SDL up upstream, and the handful of SDL calls the game makes itself. */
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <hgame.h>
#include "common.h"
#include "hz_plat.h"

char hz_prog[128];
unsigned char hz_busy_ms;

/* ---------------------------------------------------------------- time */

int fps = BASE_FPS;
int wait_time[NUM_TIMERS];
static unsigned timer_last[NUM_TIMERS];

unsigned hzt_frame(void)
{
    return hz_frame();
}

/* one vertical blank: the blitter's queue sent, the input, the view and palette, sound */
static void pump(void)
{
    hzv_flush();
    if (!hg_frame())
        quit(0);                        /* (the window closed: Alt+F4) */
    hzv_show();
    hzs_poll();
    hz_events();
}

void hzt_wait_frames(unsigned n)
{
    unsigned f = hz_frame();
    while ((unsigned)(hz_frame() - f) < n)
        pump();
}

void init_timer(int frequency)
{
    (void)frequency;
}

void reset_timer(int timer_index)
{
    timer_last[timer_index] = hz_frame();
}

void start_timer(int timer_index, int length)
{
#ifdef USE_REPLAY
    if (replaying && skipping_replay)
        return;
#endif
    timer_last[timer_index] = hz_frame();
    wait_time[timer_index] = length;
}

int has_timer_stopped(int timer_index)
{
    unsigned now;
    int elapsed, overshoot;
#ifdef USE_REPLAY
    if ((replaying && skipping_replay) || is_validate_mode)
        return 1;
#endif
    now = hz_frame();
    elapsed = (int)(now - timer_last[timer_index]);
    overshoot = elapsed - wait_time[timer_index];
    if (overshoot >= 0) {
        if (overshoot > 0 && overshoot <= 3)
            now -= (unsigned)overshoot;
        timer_last[timer_index] = now;
        return 1;
    }
    return 0;
}

/* a slower machine for the tests (/BUSY:ms): the CPU kept busy that long each game frame */
static void busy(void)
{
    if (hz_busy_ms) {
        unsigned long t = hg_us();
        while (hg_us() - t < (unsigned long)hz_busy_ms * 1000UL)
            ;
    }
}

/* Frame statistics (stats=N: a line every N game frames, and at the end): the time the
 * game's frame took from the end of the last wait (logic, drawing, the sends), and frames
 * later than their tick */
unsigned hz_stats_every;
static unsigned long st_last, st_sum, st_max, st_n, st_late, st_total_n, st_total_sum, st_total_late;
static unsigned long st_total_max;

void hz_stats_print(const char *when)
{
    if (st_n)
        printf("prince: stats %s: %lu frames, %lu.%lu ms average, %lu.%lu ms worst, %lu late; "
               "level %d room %d\n", when, st_n, st_sum / st_n / 1000, st_sum / st_n / 100 % 10,
               st_max / 1000, st_max / 100 % 10, st_late, current_level, drawn_room);
    st_total_n += st_n;
    st_total_sum += st_sum;
    st_total_late += st_late;
    if (st_max > st_total_max)
        st_total_max = st_max;
    st_n = st_sum = st_max = st_late = 0;
}

void hz_stats_end(void)
{
    if (!hz_stats_every)
        return;
    hz_stats_print("last");
    if (st_total_n)
        printf("prince: stats all: %lu frames, %lu.%lu ms average, %lu.%lu ms worst, %lu late\n",
               st_total_n, st_total_sum / st_total_n / 1000, st_total_sum / st_total_n / 100 % 10,
               st_total_max / 1000, st_total_max / 100 % 10, st_total_late);
}

static void stats_frame(int timer_index)
{
    unsigned long now = hg_us(), d;
    if (st_last) {
        d = now - st_last;
        st_sum += d;
        ++st_n;
        if (d > st_max)
            st_max = d;
        if (d > (unsigned long)wait_time[timer_index] * 16683UL)
            ++st_late;
        if (st_n >= hz_stats_every)
            hz_stats_print("frames");
    }
}

void do_simple_wait(int timer_index)
{
#ifdef USE_REPLAY
    if ((replaying && skipping_replay) || is_validate_mode)
        return;
#endif
    busy();
    if (hz_stats_every)
        stats_frame(timer_index);
    update_screen();
    while (!has_timer_stopped(timer_index))
        pump();
    if (hz_stats_every)
        st_last = hg_us();
}

int do_wait(int timer_index)
{
#ifdef USE_REPLAY
    if ((replaying && skipping_replay) || is_validate_mode)
        return 0;
#endif
    update_screen();
    while (!has_timer_stopped(timer_index)) {
        int key;
        pump();
        key = do_paused();
        if (key != 0)
            return 1;
    }
    return 0;
}

void idle(void)
{
    pump();
}

void SDL_Delay(Uint32 ms)
{
    hzt_wait_frames((unsigned)((ms * 60UL + 999) / 1000));
}

Uint64 SDL_GetPerformanceCounter(void)
{
    return (Uint64)hg_us();
}

Uint64 SDL_GetPerformanceFrequency(void)
{
    return 1000000ULL;
}

Uint32 SDL_GetTicks(void)
{
    return hg_ms();
}

/* ---------------------------------------------------------------- input */

static unsigned joy_now;

/* (used once, for Shift: the shared buffer) */
const Uint8 *SDL_GetKeyboardState(int *n)
{
    unsigned k;
    if (n)
        *n = SDL_NUM_SCANCODES;
    for (k = 0; k < SDL_NUM_SCANCODES; k++)
        hzd_buf[k] = (Uint8)(hg_key(k) != 0);
    return hzd_buf;
}

/* the joystick's directions and button as the arrows and Shift */
static const unsigned char joy_keys[5] = {
    SDL_SCANCODE_UP, SDL_SCANCODE_DOWN, SDL_SCANCODE_LEFT, SDL_SCANCODE_RIGHT, SDL_SCANCODE_LSHIFT};

static int joy_holds(unsigned k)
{
    unsigned i;
    for (i = 0; i < 5; i++)
        if (joy_keys[i] == k && (joy_now & (1u << i)))
            return 1;
    return 0;
}

static int is_modifier(unsigned k)
{
    return (k >= SDL_SCANCODE_LCTRL && k <= SDL_SCANCODE_RGUI) || k == SDL_SCANCODE_CAPSLOCK ||
           k == SDL_SCANCODE_SCROLLLOCK || k == SDL_SCANCODE_NUMLOCKCLEAR ||
           k == SDL_SCANCODE_PRINTSCREEN || k == SDL_SCANCODE_PAUSE;
}

void hz_events(void)
{
    unsigned e, k, i, d, t;
    /* presses, in order */
    while ((e = hg_key_next()) != 0) {
        unsigned c = e >> 8;
        k = e & 0xFF;
        key_states[k] |= KEYSTATE_HELD | KEYSTATE_HELD_NEW;
        last_any_key_scancode = (int)k;
        if (!is_modifier(k)) {
            last_key_scancode = (int)k;
            if (hg_mods & HG_MOD_SHIFT) last_key_scancode |= WITH_SHIFT;
            if (hg_mods & HG_MOD_CTRL) last_key_scancode |= WITH_CTRL;
            if (hg_mods & HG_MOD_ALT) last_key_scancode |= WITH_ALT;
            last_text_input = (char)(c >= 0x20 && c <= 0x7E ? c : 0);
        }
    }
    /* the joystick (port 1) */
    d = hz_joystick();
    t = hz_x;
    if (hz_errno)
        d = t = 0;
    joy_now = (d & 15) | ((t & 1) ? 16 : 0);
    for (i = 0; i < 5; i++) {
        k = joy_keys[i];
        if ((joy_now & (1u << i)) && !(key_states[k] & KEYSTATE_HELD))
            key_states[k] |= KEYSTATE_HELD | KEYSTATE_HELD_NEW;
    }
    /* releases */
    for (k = 1; k < SDL_NUM_SCANCODES; k++)
        if ((key_states[k] & KEYSTATE_HELD) && !hg_key(k) && !joy_holds(k))
            key_states[k] &= ~KEYSTATE_HELD;
}

void process_events(void)
{
    if (!hg_poll())
        quit(0);
    hzs_poll();
    hz_events();
}

int set_joy_mode(void)
{
    is_joyst_mode = 0;
    is_keyboard_mode = 1;
    return 0;
}

/* ---------------------------------------------------------------- start and end */

void set_gr_mode(byte grmode)
{
    (void)grmode;
    if (hzv_init() < 0) {
        printf("prince: no full screen (%u banks free)\n", hz_mem_info());
        exit(1);
    }
    graphics_mode = gmMcgaVga;
    load_font();
}

void apply_aspect_ratio(void) {}
void window_resized(void) {}

void sdlperror(const char *header)
{
    printf("%s\n", header);
}

void restore_stuff(void)
{
    hzs_stop();
    hg_close();
}

void quit(int exit_code)
{
    restore_stuff();
    exit(exit_code);
}

/* ---------------------------------------------------------------- files */

bool file_exists(const char *filename)
{
    hz_fileinfo st;
    return hz_stat_path(filename, &st) == 0;
}

int stat(const char *path, struct stat *st)
{
    hz_fileinfo fi;
    if (hz_stat_path(path, &fi) < 0)
        return -1;
    st->st_mode = (fi.attr & HZ_ATTR_DIR) ? S_IFDIR : S_IFREG;
    st->st_size = (long)fi.size;
    return 0;
}

int mkdir(const char *path, ...)
{
    return hz_mkdir(path) ? -1 : 0;
}

/* every file of the game is in the program's folder (the current folder: hz_main.c) */
const char *locate_file_(const char *filename, char *path_buffer, int buffer_size)
{
    (void)path_buffer; (void)buffer_size;
    return filename;
}

const char *locate_save_file_(const char *filename, char *dst, int size)
{
    (void)dst; (void)size;
    return filename;
}

directory_listing_type *create_directory_listing_and_find_first_file(const char *directory, const char *extension)
{
    (void)directory; (void)extension;
    return NULL;
}

char *get_current_filename_from_directory_listing(directory_listing_type *data)
{
    (void)data;
    return NULL;
}

bool find_next_file(directory_listing_type *data)
{
    (void)data;
    return false;
}

void close_directory_listing(directory_listing_type *data)
{
    (void)data;
}

/* ---------------------------------------------------------------- the SDL calls left */

Uint32 hz_swap32(Uint32 x)
{
    return (x >> 24) | ((x >> 8) & 0xFF00UL) | ((x << 8) & 0xFF0000UL) | (x << 24);
}

SDL_RWops *SDL_RWFromMem(void *mem, int size)
{
    SDL_RWops *rw = malloc(sizeof(SDL_RWops));
    if (rw) {
        rw->base = mem;
        rw->pos = 0;
        rw->size = (unsigned)size;
    }
    return rw;
}

size_t SDL_RWread(SDL_RWops *rw, void *ptr, size_t size, size_t n)
{
    size_t got = 0;
    while (got < n && rw->pos + size <= rw->size) {
        memcpy((char *)ptr + got * size, rw->base + rw->pos, size);
        rw->pos += size;
        ++got;
    }
    return got;
}

size_t SDL_RWwrite(SDL_RWops *rw, const void *ptr, size_t size, size_t n)
{
    size_t put = 0;
    while (put < n && rw->pos + size <= rw->size) {
        memcpy(rw->base + rw->pos, (const char *)ptr + put * size, size);
        rw->pos += size;
        ++put;
    }
    return put;
}

Sint64 SDL_RWtell(SDL_RWops *rw)
{
    return (Sint64)rw->pos;
}

int SDL_RWclose(SDL_RWops *rw)
{
    free(rw);
    return 0;
}

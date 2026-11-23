/* host/refhook.c - the reference build's state and picture hook (host/Makefile inserts a
 * call of ref_hook() after draw_game_frame() in upstream's play_level_2, and of
 * ref_opl() in midi.c's opl_write_reg).
 *
 *   POP_REF_EVERY=N     print "ref: ..." (the game's state) every N replay ticks
 *   POP_REF_TICKS=a,b   ... and at these ticks
 *   POP_REF_SHOTS=a,b   write the screen (320 x 200, onscreen_surface_) at these ticks as
 *                       POP_REF_DIR/frame-TICK.png
 *   POP_REF_OPL=FILE    every OPL register write of the music: "us reg value" lines
 *   POP_REF_LEVEL=1     at the first replay tick of each level: "lvl: level N room R sum S"
 *                       (S: FNV-1a of the whole level structure, 2,305 bytes)
 *
 * The port prints the same line (horizon/hz_ref.c): tests/state.sh compares them. */
#include "common.h"

static int in_list(const char *env, int tick)
{
    const char *s = getenv(env);
    while (s && *s) {
        if (atoi(s) == tick)
            return 1;
        s = strchr(s, ',');
        if (s)
            ++s;
    }
    return 0;
}


/* every variable of the savestate (quick_process), in hex: POP_REF_DUMP=a,b */
static int ref_dump_n;
static int ref_dump_func(void *data, size_t size)
{
    size_t i;
    printf("dump %d %u:", ref_dump_n++, (unsigned)size);
    for (i = 0; i < size; i++)
        printf("%02x", ((unsigned char *)data)[i]);
    printf("\n");
    return 1;
}
extern int quick_process(int (*f)(void *, size_t));

void ref_print_state(void)
{
    printf("ref: tick %d level %d room %d kid %d %d %d %d %d alive %d hp %d/%d "
           "guard %d %d %d %d alive %d hp %d/%d seed %u time %d %d\n",
           (int)curr_tick, current_level, drawn_room,
           Kid.room, Kid.x, Kid.y, Kid.frame, Kid.direction, Kid.alive, hitp_curr, hitp_max,
           Guard.room, Guard.x, Guard.y, Guard.frame, Guard.alive, guardhp_curr, guardhp_max,
           (unsigned)random_seed, rem_min, rem_tick);
    fflush(stdout);
}

static void ref_level_sum(void)
{
    static int last_level = -1;
    const unsigned char *p = (const unsigned char *)&level;
    unsigned long sum = 2166136261UL;
    size_t i;
    if (!getenv("POP_REF_LEVEL") || current_level == last_level)
        return;
    last_level = current_level;
    for (i = 0; i < sizeof(level); i++)
        sum = ((sum ^ p[i]) * 16777619UL) & 0xFFFFFFFFUL;
    printf("lvl: level %d room %d sum %08lx size %u\n", current_level, drawn_room, sum,
           (unsigned)sizeof(level));
}

void ref_hook(void)
{
    static int last = -1;
    const char *every = getenv("POP_REF_EVERY");
    int tick = (int)curr_tick;
    if (!(replaying || recording) || tick == last)
        return;
    last = tick;
    ref_level_sum();
    if ((every && atoi(every) > 0 && tick % atoi(every) == 0) || in_list("POP_REF_TICKS", tick))
        ref_print_state();
    if (in_list("POP_REF_DUMP", tick)) {
        ref_dump_n = 0;
        printf("dump tick %d\n", tick);
        quick_process(ref_dump_func);
    }
    if (in_list("POP_REF_SHOTS", tick)) {
        char path[512];
        const char *dir = getenv("POP_REF_DIR");
        snprintf(path, sizeof path, "%s/frame-%d.png", dir ? dir : ".", tick);
        IMG_SavePNG(onscreen_surface_, path);
        printf("ref: shot %s\n", path);
    }
}

/* Scripted recordings (POP_REF_INPUT=FILE with "prince-ref record LEVEL", POP_REF_SILENT
 * and POP_REF_FAST set): each line "COUNT KEYS" holds KEYS (L R U D S = left right up down
 * shift, - none) for COUNT game ticks; "#" lines are comments. When the script ends the
 * recording is saved as POP_REF_REC and the program ends. */
void ref_input(void)
{
    static FILE *f;
    static int left, done;
    static char keys[32];
    const char *path = getenv("POP_REF_INPUT");
    if (!path || !recording || done)
        return;
    if (!f && !(f = fopen(path, "r"))) {
        printf("ref: no %s\n", path);
        exit(1);
    }
    while (left <= 0) {
        char line[128];
        if (!fgets(line, sizeof line, f)) {
            const char *out = getenv("POP_REF_REC");
            done = 1;
            recording = 0;
            if (out && save_recorded_replay(out))
                printf("ref: recorded %s, %d ticks\n", out, (int)curr_tick);
            ref_print_state();
            exit(0);
        }
        if (line[0] == '#' || sscanf(line, "%d %31s", &left, keys) != 2)
            left = 0;
    }
    --left;
    control_x = strchr(keys, 'L') ? CONTROL_HELD_LEFT : strchr(keys, 'R') ? CONTROL_HELD_RIGHT
                                                                       : CONTROL_RELEASED;
    control_y = strchr(keys, 'U') ? CONTROL_HELD_UP : strchr(keys, 'D') ? CONTROL_HELD_DOWN
                                                                    : CONTROL_RELEASED;
    control_shift = strchr(keys, 'S') ? CONTROL_HELD : CONTROL_RELEASED;
}

/* the OPL writes of the music, with the music's own clock (microseconds since it started) */
static FILE *opl_log;
void ref_opl(int reg, int value, double us)
{
    const char *f = getenv("POP_REF_OPL");
    if (!f)
        return;
    if (!opl_log)
        opl_log = fopen(f, "w");
    if (opl_log) {
        fprintf(opl_log, "%.0f %03x %02x\n", us, reg, value);
        fflush(opl_log);
    }
}

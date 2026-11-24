/* gt_keymods.c - hgame's test: each key event's modifiers (hg_key_next, hg_key_mods). A
 * modifier and a key pressed and released within one batch of events (Ctrl+G typed
 * quickly; a keyboard adapter that reports both in one HID report): hg_mods is the state at
 * the last event read (Ctrl up), hg_key_mods the one at G's press. The program reads no
 * events for 400 ms after each "ready" line while the script sends its four key changes at
 * one instant, then one hg_poll takes them all: one batch, whatever the frame timing. */
#include <stdio.h>
#include <hgame.h>

#define KEY_G 0x0A

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s keymods: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

/* one case: the script's batch after "ready N"; G's press from the queue: its modifiers and
 * its character; 1 if G was pressed and released within the batch (hg_key_pressed and
 * _released in the same frame, not held) */
static int batch(unsigned n, unsigned *mods, unsigned *ch, unsigned *after, unsigned *keys)
{
    unsigned long t;
    unsigned e;
    int one;

    while (hg_key_next())                       /* nothing left from before */
        ;
    hg_frame();
    hg_frame();
    printf("gt_keymods: ready %u\n", n);
    t = hg_ms();
    while (hg_ms() - t < 400)                   /* no events read: the script's go in */
        ;
    hg_poll();
    one = hg_key_pressed(KEY_G) && hg_key_released(KEY_G) && !hg_key(KEY_G);
    *after = hg_mods;
    *mods = 0xFFFF;
    *ch = 0;
    *keys = 0;
    while ((e = hg_key_next()) != 0) {
        ++*keys;
        if ((e & 0xFF) == KEY_G) {
            *mods = hg_key_mods;
            *ch = e >> 8;
        }
    }
    printf("gt_keymods: case %u: %u presses, G's modifiers %u, char %u, hg_mods after %u, "
           "one batch %d\n", n, *keys, *mods, *ch, *after, one);
    return one;
}

int main(void)
{
    unsigned m, c, a, k;
    int one;

    if (hg_screen(HG_320X180, "gt_keymods") < 0) {
        printf("FAIL keymods: hg_screen\n");
        return 1;
    }
    hg_clear(17);
    hg_text(8, 8, "keymods: each key's modifiers", 1);
    hg_frame();

    /* 1. Ctrl down, G down, Ctrl up, G up: G typed with Ctrl */
    one = batch(1, &m, &c, &a, &k);
    check("Ctrl, G, Ctrl up, G up in one batch", one && k == 2);
    check("G's press carries Ctrl (hg_key_mods)", m == HG_MOD_CTRL);
    check("hg_mods after the batch: Ctrl up (its meaning kept)", a == 0);
    /* 2. G down, Ctrl down, G up, Ctrl up: G before Ctrl, typed without it */
    one = batch(2, &m, &c, &a, &k);
    check("G, Ctrl, G up, Ctrl up in one batch", one && k == 2);
    check("G's press without Ctrl", m == 0 && c == 'g');
    /* 3. Shift down, G down, Shift up, G up: a capital, with Shift */
    one = batch(3, &m, &c, &a, &k);
    check("Shift, G, Shift up, G up in one batch", one && k == 2);
    check("G's press carries Shift, its character 'G'", m == HG_MOD_SHIFT && c == 'G' && a == 0);
    /* 4. G down, Shift down, G up, Shift up: a small g */
    one = batch(4, &m, &c, &a, &k);
    check("G, Shift, G up, Shift up in one batch", one && k == 2);
    check("G's press without Shift, its character 'g'", m == 0 && c == 'g');
    /* 5. Ctrl down, G down, G up (Ctrl still held after the batch): Ctrl in both */
    one = batch(5, &m, &c, &a, &k);
    check("Ctrl still held: G's press carries it, hg_mods too", one && k == 2 &&
          m == HG_MOD_CTRL && a == HG_MOD_CTRL);
    /* the queue empty: hg_key_next 0 and hg_key_mods 0 */
    check("an empty queue: 0, hg_key_mods 0", hg_key_next() == 0 && hg_key_mods == 0);
    printf("gt_keymods: %u failed\n", fails);
    return 0;
}

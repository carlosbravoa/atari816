/* gt_input.c - hgame's test: input in full screen 640 x 360 with the pointer: the key
 * table (held, pressed, released), typed characters, player 1 (arrows and W A S D merged),
 * the joystick (none in the emulator: 0), the mouse (position, buttons, clicks). The
 * script presses the keys and moves and clicks the mouse at known times. */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s input: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

int main(void)
{
    unsigned long t0 = hg_ms();
    unsigned held_right = 0, press_right = 0, rel_right = 0, p1r = 0, p1d = 0, p1edge = 0;
    unsigned fire = 0, clicks = 0, joy = 0, frames = 0, c;
    char typed[16];
    unsigned nt = 0;
    int cx = -1, cy = -1;

    if (hg_screen(HG_640X360 | HG_POINTER, "gt_input") < 0) {
        printf("FAIL input: hg_screen\n");
        return 1;
    }
    hg_clear(17);
    hg_text(16, 16, "input: keys, player 1, the mouse", 1);
    while (hg_ms() - t0 < 5000 && hg_frame()) {
        ++frames;
        if (hg_key(HG_KEY_RIGHT))
            ++held_right;
        if (hg_key_pressed(HG_KEY_RIGHT))
            ++press_right;
        if (hg_key_released(HG_KEY_RIGHT))
            ++rel_right;
        if (hg_p1() & HG_RIGHT)
            ++p1r;
        if (hg_p1() & HG_DOWN)
            ++p1d;
        if (hg_p1_pressed() & HG_RIGHT)
            ++p1edge;
        if (hg_p1_pressed() & HG_FIRE)
            ++fire;
        joy |= hg_joy(1) | hg_joy(2);
        while ((c = hg_getchar()) != 0 && nt < sizeof typed - 1)
            typed[nt++] = (char)c;
        if (hg_mouse_clicked() & 1) {
            ++clicks;
            cx = hg_mouse_x;
            cy = hg_mouse_y;
            hg_fill(cx - 4, cy - 4, 9, 9, 196);
        }
    }
    typed[nt] = 0;
    printf("gt_input: right held %u frames, pressed %u, released %u; p1 right %u down %u "
           "edges %u fire %u; %u typed; clicks %u at %d,%d\n", held_right, press_right,
           rel_right, p1r, p1d, p1edge, fire, nt, clicks, cx, cy);
    /* the script: Right held 500 ms; S (down) held 300 ms; "hi" typed; Space; a click */
    check("a key held for its frames", held_right >= 25 && held_right <= 35);
    check("pressed once, released once", press_right == 1 && rel_right == 1);
    check("player 1: the arrow and W A S D", p1r == held_right && p1d >= 15 && p1d <= 21);
    check("player 1: a direction pressed once", p1edge == 1);
    check("player 1: fire (Space)", fire == 1);
    /* (the arrow comes as KEY_RIGHT codes, repeated while held; then s, h, i, Space) */
    check("characters typed", nt >= 4 && !strcmp(typed + nt - 4, "shi "));
    check("no joystick in the emulator", joy == 0);
    check("a click, at the pointer (640 x 360)", clicks == 1 && cx == 400 && cy == 200);
    check("frames ran", frames > 250);
    printf("gt_input: %u failed\n", fails);
    return 0;
}

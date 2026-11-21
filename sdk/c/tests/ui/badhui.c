/* badhui.c - the block's two checks stop a program with a message (tests/run.py):
 *   BADHUI ptr   a control given as a local variable (on the stack, not the code bank)
 *   BADHUI cb    a control routine called inside a list's row function
 * Prints "BADHUI: start" first: the message must come after the program's own output. */
#include <stdio.h>
#include <string.h>
#include <horizon.h>
#include <hui.h>

static const char *row(ui_list *ls, unsigned r, const ui_rowinfo *ri)
{
    ui_lsset(ls, 3);                    /* not allowed here */
    return "x";
}

static ui_list lst = UI_LIST(8, 8, 120, 60, 0, row);
static ui_ctlref ctls[] = { &lst, 0 };

int main(int argc, char **argv)
{
    hz_winopen wo;
    int w;
    ui_button local = UI_BUTTON(8, 8, 64, 0, "Local");

    hz_ws_start();
    ui_init();
    wo.x = 100;
    wo.y = 60;
    wo.w = 200;
    wo.h = 100;
    HZ_U24(wo.title, "Bad");
    wo.flags = 0;
    w = hz_win_open(&wo);
    printf("BADHUI: start\n");
    if (argc > 1 && !strcmp(argv[1], "ptr")) {
        local.win = (unsigned char)w;
        ui_draw(&local);
    } else {
        ui_setwin(ctls, w);
        ui_drawall(ctls);
        ui_lsset(&lst, 3);
    }
    printf("BADHUI: not stopped\n");
    return 0;
}

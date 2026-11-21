/* catch.c - Catch: letters fall in a text screen; move the basket with the arrow keys (or
 * J and L) and catch them. Five missed and the game is over. Written against cc65's
 * conio.h only (no Horizon header): the proof that a conio game comes over as it is.
 * Space starts a game, Q quits. */
#include <conio.h>
#include <stdio.h>                      /* (only for the test's line in the log) */
#include <stdlib.h>

#define DROPS 4

static unsigned char w, h, bx, score, missed, best;
static unsigned char dx[DROPS], dy[DROPS], dc[DROPS], live[DROPS];
static unsigned tick;

static void frame_box(void)
{
    textcolor(COLOR_CYAN);
    cputcxy(0, 1, CH_ULCORNER);
    chline(w - 2);
    cputc(CH_URCORNER);
    cvlinexy(0, 2, h - 3);
    cvlinexy(w - 1, 2, h - 3);
    cputcxy(0, h - 1, CH_LLCORNER);
    chline(w - 2);
    cputc(CH_LRCORNER);
}

static void status(void)
{
    gotoxy(0, 0);
    textcolor(COLOR_YELLOW);
    revers(1);
    cprintf(" CATCH  score %3u  missed %u/5  best %3u", score, missed, best);
    cclear(w - wherex());
    revers(0);
}

static void basket(unsigned char show)
{
    textcolor(COLOR_ORANGE);
    cputsxy(bx - 1, h - 2, show ? "\\_/" : "   ");
}

static void drop(unsigned char i)
{
    dx[i] = (unsigned char)(2 + rand() % (w - 4));
    dy[i] = 2;
    dc[i] = (unsigned char)('A' + rand() % 26);
    live[i] = 1;
}

static void play(void)
{
    unsigned char i, k, speed;
    clrscr();
    frame_box();
    score = missed = 0;
    bx = w / 2;
    for (i = 0; i < DROPS; i++)
        live[i] = 0;
    status();
    basket(1);
    while (missed < 5) {
        waitvsync();
        ++tick;
        if (kbhit()) {
            k = cgetc();
            basket(0);
            if ((k == CH_CURS_LEFT || k == 'j') && bx > 2)
                --bx;
            if ((k == CH_CURS_RIGHT || k == 'l') && bx < w - 3)
                ++bx;
            if (k == 'q')
                exit(0);
            basket(1);
        }
        speed = score < 10 ? 12 : score < 25 ? 8 : 5;
        if (tick % speed)
            continue;
        for (i = 0; i < DROPS; i++) {
            if (!live[i]) {
                if (rand() % 4 == 0)
                    drop(i);
                continue;
            }
            cputcxy(dx[i], dy[i], ' ');
            if (++dy[i] == h - 2) {             /* the basket's row */
                live[i] = 0;
                if (dx[i] >= bx - 1 && dx[i] <= bx + 1)
                    ++score;
                else
                    ++missed;
                basket(1);
                status();
                continue;
            }
            textcolor(COLOR_LIGHTGREEN);
            cputcxy(dx[i], dy[i], (char)dc[i]);
        }
    }
    if (score > best)
        best = score;
    printf("CATCH: game over, score %u\n", score);
    status();
    textcolor(COLOR_WHITE);
    revers(1);
    cputsxy(w / 2 - 8, h / 2, "   GAME  OVER   ");
    revers(0);
}

int main(void)
{
    char k;
    screensize(&w, &h);
    srand(7);
    bgcolor(COLOR_BLUE);
    clrscr();
    frame_box();
    status();
    textcolor(COLOR_WHITE);
    cputsxy(w / 2 - 9, h / 2 - 2, "Catch the letters!");
    cputsxy(w / 2 - 14, h / 2, "Arrows or J/L move the basket");
    cputsxy(w / 2 - 11, h / 2 + 2, "Space: play   Q: quit");
    for (;;) {
        k = cgetc();
        if (k == 'q')
            break;
        if (k == ' ') {
            play();
            cputsxy(w / 2 - 11, h / 2 + 2, "Space: again  Q: quit");
        }
    }
    return 0;
}

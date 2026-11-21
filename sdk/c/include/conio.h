/* conio.h - cc65's console I/O for Horizon (Atari816): a text screen of character cells
 * (40 x 25 by default) in a window or full screen, drawn by hgame. For C games written
 * against cc65's conio, with few changes; hcc links it by itself (the game library).
 *
 *   #include <conio.h>
 *   int main(void) {
 *       clrscr();
 *       gotoxy(10, 5);
 *       cputs("Hello");
 *       cgetc();
 *       return 0;
 *   }
 *
 * What differs from cc65 (sdk/docs/c/games.md, "From cc65"):
 *   - the screen is a window of 40 x 25 cells of 8 x 10 pixels unless conio_screen() says
 *     otherwise before the first call (any size up to 80 x 33 in a window; full screen:
 *     40 x 18 at 320 x 180, 80 x 36 at 640 x 360);
 *   - output is shown at the next kbhit(), cgetc() or waitvsync() (and every 64 characters
 *     when a frame has passed): a program that prints and then waits for a key sees it;
 *   - colours are C64's 16 (COLOR_BLACK .. COLOR_GRAY3); textcolor and bgcolor are per
 *     character, as on the C64; bordercolor does nothing;
 *   - the line characters (CH_HLINE, CH_VLINE, corners, tees, CH_CROSS) are drawn as
 *     '-', '|' and '+'; there is no other graphics character set;
 *   - cgetc() returns ASCII, '\n' for Enter, CH_CURS_* for the arrows, CH_DEL for
 *     Backspace; closing the window ends the program (exit(0)).
 */
#ifndef CONIO_H
#define CONIO_H

#include <stdarg.h>

#define COLOR_BLACK      0
#define COLOR_WHITE      1
#define COLOR_RED        2
#define COLOR_CYAN       3
#define COLOR_PURPLE     4
#define COLOR_VIOLET     4
#define COLOR_GREEN      5
#define COLOR_BLUE       6
#define COLOR_YELLOW     7
#define COLOR_ORANGE     8
#define COLOR_BROWN      9
#define COLOR_LIGHTRED   10
#define COLOR_GRAY1      11
#define COLOR_GRAY2      12
#define COLOR_LIGHTGREEN 13
#define COLOR_LIGHTBLUE  14
#define COLOR_GRAY3      15

#define CH_ENTER     '\n'
#define CH_ESC       27
#define CH_DEL       8
#define CH_CURS_RIGHT 0x80
#define CH_CURS_LEFT  0x81
#define CH_CURS_DOWN  0x82
#define CH_CURS_UP    0x83
#define CH_HOME       0x84
#define CH_HLINE      0x90
#define CH_VLINE      0x91
#define CH_ULCORNER   0x92
#define CH_URCORNER   0x93
#define CH_LLCORNER   0x94
#define CH_LRCORNER   0x95
#define CH_TTEE       0x96
#define CH_BTEE       0x97
#define CH_LTEE       0x98
#define CH_RTEE       0x99
#define CH_CROSS      0x9A

/* Horizon only: the text screen's size and where (0: a window, 1: full screen 320 x 180,
 * 2: full screen 640 x 360); before the first conio call. 0 = the default. */
void conio_screen(unsigned char cols, unsigned char rows, unsigned char full);

void clrscr(void);
unsigned char kbhit(void);
void gotoxy(unsigned char x, unsigned char y);
void gotox(unsigned char x);
void gotoy(unsigned char y);
unsigned char wherex(void);
unsigned char wherey(void);
void cputc(char c);
void cputcxy(unsigned char x, unsigned char y, char c);
void cputs(const char *s);
void cputsxy(unsigned char x, unsigned char y, const char *s);
int cprintf(const char *format, ...);
int vcprintf(const char *format, va_list ap);
char cgetc(void);
unsigned char cursor(unsigned char onoff);
unsigned char revers(unsigned char onoff);
unsigned char textcolor(unsigned char color);
unsigned char bgcolor(unsigned char color);
unsigned char bordercolor(unsigned char color);
void chline(unsigned char length);
void chlinexy(unsigned char x, unsigned char y, unsigned char length);
void cvline(unsigned char length);
void cvlinexy(unsigned char x, unsigned char y, unsigned char length);
void cclear(unsigned char length);
void cclearxy(unsigned char x, unsigned char y, unsigned char length);
void screensize(unsigned char *x, unsigned char *y);
/* wait for the next frame (60 a second): what was printed is shown */
void waitvsync(void);

#endif

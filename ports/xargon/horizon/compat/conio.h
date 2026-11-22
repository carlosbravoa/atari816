/* conio.h - Turbo C's text screen, for Xargon's few uses (the DOS screens before and after
 * the game): cputs goes to the console, the rest does nothing (hz_dos.c). */
#ifndef XCONIO_H
#define XCONIO_H
void clrscr(void);
void window(int l, int t, int r, int b);
void textcolor(int c);
void textbackground(int c);
void gotoxy(int x, int y);
int cputs(const char *s);
#endif

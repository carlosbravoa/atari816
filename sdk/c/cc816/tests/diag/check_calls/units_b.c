/* the other file of check_calls_units.c (hcc --check-calls): the definitions */
int picture_target(char __far *mode) { return mode != 0; }
void blit(char __far *p, int y) { (void)p; (void)y; }
long sum(int a, int b) { return a + b; }
int other(x) long x; { return (int)x; }
int fine(a) int a; { return a; }
static int hidden(long x) { return (int)x; }
int use_hidden(void) { return hidden(1L); }

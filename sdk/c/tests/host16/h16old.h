/* h16old.h - old C declarations, as a DOS program's headers have them (host16.py's
   test of old C: h16old.C, h16lib.c). This comment goes over several lines, names int
   and long, and says what the test doesn't ( do: a comment's words are not code */
extern int twice();             /* defined without a type (implicit int, K&R) */
extern int scale();             /* defined with parameters it does not declare */
extern long widen();            /* defined with a prototype: short and char parameters */
extern void fill_pair();        /* defined with a prototype: int parameters */
int box_area(struct box *);     /* struct box is not declared yet: the prototype's own */
extern int abs(int);            /* the C library's, declared again by the program */
extern char *strcpy();
extern int counted();

/* a 16-bit int's case label: 0x9000 is a negative int on the Atari816 (a fix-up) */
static int is_high_code(int k)
{
    switch (k) {
    case 0x9000:
        return 1;
    }
    return 0;
}

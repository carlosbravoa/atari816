/* -Wunprototyped-args: a call without a prototype (an old declaration, an implicit one, a
 * K&R definition) whose arguments' sizes differ from the definition's parameters in the
 * same file: an int pushed (2 bytes) where a far pointer (4) or a long is read shifts
 * every later parameter (a DOS port's picture_target(0)); fewer arguments than
 * parameters. A pointer or an int of one size agree (the 65816 passes them alike).
 * hcc --check-calls does the same across files (tests/diag/check_calls_*.c) */
// FLAGS: -Wno-implicit-function-declaration
int target();
int user(void)
{
    return target(0, 5)         // EXPECT: warning: the call of 'target' has no prototype: argument 1 is pushed as an int (2 bytes), but the definition (line 18) reads a char __far * (4 bytes): it and every later parameter are read from the wrong place; declare 'target' with a prototype [-Wunprototyped-args]
        + later(1)              // EXPECT: warning: the call of 'later' has no prototype: argument 1 is pushed as an int (2 bytes), but the definition (line 19) reads a long (4 bytes)
        + kr(2L, 3)
        + fewer(1)              // EXPECT: warning: the call of 'fewer' has no prototype and passes 1 argument, but the definition (line 21) takes 2: the missing ones are read from whatever is on the stack
        + fl(1)                 // EXPECT: warning: the call of 'fl' has no prototype: argument 1 is pushed as an int (2 bytes), but the definition (line 22) reads a float (4 bytes)
        + same((char *)0, 'x');
}
int target(char __far *p, int n) { return n + (p != 0); }
int later(long x) { return (int)x; }
int kr(a, b) long a; char b; { return (int)a + b; }
int fewer(a, b) int a, b; { return a + b; }
int fl(x) float x; { return (int)x; }
int same(n, c) int n; char c; { return n + c; }

/* setjmp.h - cc816 (Horizon C SDK): setjmp and longjmp (rt/cc816/setjmp.s).
 *
 * A jmp_buf keeps the hardware stack pointer, the return address, the software stack
 * pointer and the 48 bytes of callee-saved registers (__rg+48..95): 54 bytes. setjmp
 * returns 0, then the value longjmp gives (1 if that is 0). As C says, a local variable
 * of the function that called setjmp that is not volatile and was changed after setjmp
 * has an unknown value after longjmp: declare it volatile to keep its last value. The
 * compiler knows setjmp by its name (also _setjmp and sigsetjmp): call it directly, not
 * through a pointer. */
#ifndef _SETJMP_H
#define _SETJMP_H
typedef unsigned int jmp_buf[27];
typedef jmp_buf sigjmp_buf;
int setjmp(jmp_buf env);
_Noreturn void longjmp(jmp_buf env, int val);
#define setjmp setjmp
#define _setjmp setjmp
#define _longjmp longjmp
#define sigsetjmp(env, savemask) setjmp(env)
#define siglongjmp longjmp
#endif

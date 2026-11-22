/* preproc.c - the preprocessor: #pragma once, #if arithmetic, defined, __has_include,
 * -D, -U, -include (FLAGS below), # and ##, variadic macros, empty arguments, #line. */
// FLAGS: -DLEVEL=3 -DNAME=hero -DUNDEFME=1 -UUNDEFME -include lang_inc.h
#include "lang_once.h"
#include "lang_once.h"

#if (1 << 20) != 0x100000 || -1 >= 0 || 10 / 3 != 3 || -7 % 3 != -1
#error "#if arithmetic"
#endif
#if 0xFFFFFFFF != 4294967295 || (2 > 1 ? 5 : 6) != 5 || !defined(LEVEL) || defined UNDEFME
#error "#if"
#endif
#if LEVEL * 2 != 6 || 'A' != 65
#error "-D"
#endif
#if !__has_include(<stdio.h>) || __has_include("no_such_file.h") || !defined(__has_include)
#error "__has_include"
#endif
#ifdef __CC816__
#define COMPILER 816
#elif defined(__GNUC__)
#define COMPILER 1
#else
#define COMPILER 0
#endif

#define STR(x) #x
#define XSTR(x) STR(x)
#define CAT(a, b) a ## b
#define FIRST(a, ...) a
#define COUNT(...) count_args(0, __VA_ARGS__)
#define OPT(a, b) (a + 0 b)

static int count_args(int z, ...) { return z; }
static int hero = 5;

int main(void)
{
    int CAT(var, 1) = 3;
    if (once_count != 1 || FROM_INCLUDE != 77 || COMPILER != 816)
        return 1;
    if (var1 != 3 || NAME != 5 || FIRST(7, 8, 9) != 7 || COUNT(1, 2) != 0)
        return 2;
    if (sizeof(STR(abc)) != 4 || XSTR(LEVEL)[0] != '3' || STR( a  b )[1] != ' ')
        return 3;
    if (OPT(1, ) != 1 || OPT(1, + 2) != 3)
        return 4;
#line 500
    if (__LINE__ != 500)
        return 5;
    return 0;
}

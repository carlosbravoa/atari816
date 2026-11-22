/* ctype.h - cc816 (Horizon C SDK): ASCII only (the "C" locale). */
#ifndef _CTYPE_H
#define _CTYPE_H
extern const unsigned char __hz_ctype[257];
#define __HZ_U 0x01     /* upper case */
#define __HZ_L 0x02     /* lower case */
#define __HZ_D 0x04     /* digit */
#define __HZ_S 0x08     /* white space */
#define __HZ_P 0x10     /* punctuation */
#define __HZ_C 0x20     /* control */
#define __HZ_X 0x40     /* hex letter */
#define __HZ_B 0x80     /* blank (space, tab) */
#define __hz_ct(c) (__hz_ctype + 1)[(int)(c)]
int isalnum(int c);
int isalpha(int c);
int isblank(int c);
int iscntrl(int c);
int isdigit(int c);
int isgraph(int c);
int islower(int c);
int isprint(int c);
int ispunct(int c);
int isspace(int c);
int isupper(int c);
int isxdigit(int c);
int tolower(int c);
int toupper(int c);
#define isalnum(c) (__hz_ct(c) & (__HZ_U | __HZ_L | __HZ_D))
#define isalpha(c) (__hz_ct(c) & (__HZ_U | __HZ_L))
#define isblank(c) (__hz_ct(c) & __HZ_B)
#define iscntrl(c) (__hz_ct(c) & __HZ_C)
#define isdigit(c) (__hz_ct(c) & __HZ_D)
#define isgraph(c) (__hz_ct(c) & (__HZ_U | __HZ_L | __HZ_D | __HZ_P))
#define islower(c) (__hz_ct(c) & __HZ_L)
#define ispunct(c) (__hz_ct(c) & __HZ_P)
#define isspace(c) (__hz_ct(c) & __HZ_S)
#define isupper(c) (__hz_ct(c) & __HZ_U)
#define isxdigit(c) (__hz_ct(c) & (__HZ_D | __HZ_X))
#endif

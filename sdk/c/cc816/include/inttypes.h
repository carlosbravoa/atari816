/* inttypes.h - cc816 (Horizon C SDK): printf / scanf formats of stdint.h's types, and
 * the intmax_t functions (intmax_t is long long) */
#ifndef _INTTYPES_H
#define _INTTYPES_H
#include <stdint.h>
#include <stdlib.h>
#define PRId8 "d"
#define PRIi8 "i"
#define PRIu8 "u"
#define PRIo8 "o"
#define PRIx8 "x"
#define PRIX8 "X"
#define PRId16 "d"
#define PRIi16 "i"
#define PRIu16 "u"
#define PRIo16 "o"
#define PRIx16 "x"
#define PRIX16 "X"
#define PRId32 "ld"
#define PRIi32 "li"
#define PRIu32 "lu"
#define PRIo32 "lo"
#define PRIx32 "lx"
#define PRIX32 "lX"
#define PRId64 "lld"
#define PRIi64 "lli"
#define PRIu64 "llu"
#define PRIo64 "llo"
#define PRIx64 "llx"
#define PRIX64 "llX"
#define PRIdLEAST8 PRId8
#define PRIuLEAST8 PRIu8
#define PRIdLEAST16 PRId16
#define PRIuLEAST16 PRIu16
#define PRIdLEAST32 PRId32
#define PRIuLEAST32 PRIu32
#define PRIdLEAST64 PRId64
#define PRIuLEAST64 PRIu64
#define PRIdFAST8 PRId16
#define PRIuFAST8 PRIu16
#define PRIdFAST16 PRId16
#define PRIuFAST16 PRIu16
#define PRIdFAST32 PRId32
#define PRIuFAST32 PRIu32
#define PRIdFAST64 PRId64
#define PRIuFAST64 PRIu64
#define PRIdMAX "lld"
#define PRIiMAX "lli"
#define PRIuMAX "llu"
#define PRIoMAX "llo"
#define PRIxMAX "llx"
#define PRIXMAX "llX"
#ifdef __CC816_FAR_DATA__
#define PRIdPTR "ld"
#define PRIiPTR "li"
#define PRIuPTR "lu"
#define PRIxPTR "lx"
#define PRIXPTR "lX"
#else
#define PRIdPTR "d"
#define PRIiPTR "i"
#define PRIuPTR "u"
#define PRIxPTR "x"
#define PRIXPTR "X"
#endif
#define SCNd8 "hhd"
#define SCNu8 "hhu"
#define SCNx8 "hhx"
#define SCNd16 "d"
#define SCNi16 "i"
#define SCNu16 "u"
#define SCNo16 "o"
#define SCNx16 "x"
#define SCNd32 "ld"
#define SCNi32 "li"
#define SCNu32 "lu"
#define SCNo32 "lo"
#define SCNx32 "lx"
#define SCNd64 "lld"
#define SCNi64 "lli"
#define SCNu64 "llu"
#define SCNo64 "llo"
#define SCNx64 "llx"
#define SCNdMAX "lld"
#define SCNuMAX "llu"
#define SCNxMAX "llx"
typedef lldiv_t imaxdiv_t;
#define imaxabs llabs
#define imaxdiv lldiv
#define strtoimax strtoll
#define strtoumax strtoull
#endif

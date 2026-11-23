/* farprog.c - the far data model on its own (hcc --code large --data far; tests/run.py's
 * "far" test, docs/c/reference.md "The far data model"): far data in several banks, the
 * placement rules, the heap over banks, the library with far pointers, files read
 * straight into far memory. Prints "farprog: N checks, F failures" and FARPROG PASS. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#include <fcntl.h>
#include <unistd.h>
#include <horizon.h>

#ifndef __CC816_FAR_DATA__
#error "build this with hcc --code large --data far"
#endif

static int checks, fails;
#define CHECK(c) check((c), __LINE__)
static void check(int ok, int line)
{
    checks++;
    if (!ok) {
        fails++;
        printf("FAIL line %d\n", line);
    }
}

/* three constant tables of 40,000 bytes: three banks of far data; one just under 64 KB */
const unsigned char big1[40000] = { 1, 2, 3, [39999] = 99 };
const unsigned char big2[40000] = { 4, 5, 6, [39999] = 98 };
const unsigned char big3[40000] = { 7, 8, 9, [39999] = 97 };
const unsigned char huge1[65000] = { 11, [64999] = 12 };
/* a writable object put in far data, and a near one */
__far unsigned short fw[1000];
unsigned char __near nearbuf[64];
/* constants that hold addresses of other far objects: relocated at the start */
const unsigned char *const bigs[3] = { big1, big2, big3 + 1 };
const char *const words[] = { "zero", "one", "two", "three", "one" };
/* a writable table of far pointers (in the main bank) to far data */
const unsigned char *ptab[2] = { &huge1[64999], big2 + 39999 };
struct rec { const char *name; int v; struct rec *next; };
struct rec recs[3] = { { "a", 1, &recs[1] }, { "bb", 2, &recs[2] }, { "ccc", 3, 0 } };

static int cmp(const void *a, const void *b)
{
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}

static jmp_buf *jb;
static int depth(int n)
{
    char local[40];
    sprintf(local, "%d", n);
    if (n == 0)
        longjmp(*jb, (int)strlen(local) + 41);
    return depth(n - 1) + local[0];
}

static long sum(const unsigned char *p, unsigned n)
{
    long s = 0;
    while (n--)
        s += *p++;
    return s;
}

int main(void)
{
    char buf[80];
    char *blocks[6];
    unsigned i;
    int k;
    unsigned long a, b;
    char *p, *q;
    const char *sorted[5];
    int fd;
    FILE *f;

    /* the far objects: in banks other than the main one, each whole in its bank */
    CHECK(big1[0] == 1 && big1[39999] == 99 && big2[39999] == 98 && big3[39999] == 97);
    CHECK(huge1[0] == 11 && huge1[64999] == 12);
    CHECK(HZ_BANK(big1) != HZ_BANK(&k) && HZ_BANK(huge1) != HZ_BANK(&k));
    CHECK(HZ_BANK(big1) != HZ_BANK(big2) || HZ_BANK(big2) != HZ_BANK(big3));
    CHECK((unsigned)HZ_OFF(&big1[39999]) - (unsigned)HZ_OFF(big1) == 39999u);
    CHECK(bigs[0][1] == 2 && bigs[1][2] == 6 && bigs[2][0] == 8);
    CHECK(*ptab[0] == 12 && *ptab[1] == 98);
    CHECK(strcmp(words[3], "three") == 0 && words[1] == words[4]);    /* literals merged */
    CHECK(HZ_BANK(words[0]) != HZ_BANK(&k));        /* string literals in far data */
    CHECK(HZ_BANK(nearbuf) == HZ_BANK(&k) && HZ_BANK(&fw[0]) != HZ_BANK(&k));
    CHECK(sizeof(void *) == 4 && sizeof(char __near *) == 2 && sizeof(size_t) == 2);
    for (i = 0; i < 1000; i++)
        fw[i] = (unsigned short)(i * 3);
    CHECK(fw[999] == 2997 && sum(big1, 3) == 6);

    /* pointers: arithmetic, comparisons, NULL, conversions */
    p = (char *)big1 + 39999;
    q = (char *)big1;
    /* (p - q is a ptrdiff_t, 16 bits as in DOS's large model: 39,999 as unsigned) */
    CHECK(p > q && (unsigned)(p - q) == 39999u && q < p && p != q &&
          *(unsigned char *)p == 99);
    CHECK((unsigned)(--p - q) == 39998u);
    p = 0;
    CHECK(p == NULL && !p);
    a = (unsigned long)(void *)&big1[5];
    CHECK((a & 0xFFFF) == HZ_OFF(&big1[5]) && (a >> 16) == HZ_BANK(big1));
    CHECK((char *)a == (char *)&big1[5]);
    p = (char *)hz_farptr(HZ_BANK(big2), HZ_OFF(big2));
    CHECK(*(unsigned char *)p == 4);
    CHECK(recs[0].next->next->v == 3 && strcmp(recs[0].next->name, "bb") == 0);

    /* the library: far strings, sprintf %s and %p, qsort of far pointers */
    sprintf(buf, "%s-%s %p", words[1], "lit", (void *)0x0A1234L);
    CHECK(strcmp(buf, "one-lit 0x0a1234") == 0);
    for (i = 0; i < 5; i++)
        sorted[i] = words[i];
    qsort(sorted, 5, sizeof sorted[0], cmp);
    CHECK(strcmp(sorted[0], "one") == 0 && strcmp(sorted[4], "zero") == 0);
    strcpy((char *)nearbuf, "near");
    CHECK(strlen((char *)nearbuf) == 4 && memcmp(nearbuf, "near", 4) == 0);

    /* the heap over banks: 6 blocks of 40,000 bytes */
    for (i = 0; i < 6; i++) {
        blocks[i] = malloc(40000u);
        CHECK(blocks[i] != NULL);
        if (blocks[i]) {
            memset(blocks[i], (int)i + 1, 40000u);
            blocks[i][39999] = (char)(100 + i);
        }
    }
    CHECK(HZ_BANK(blocks[0]) != HZ_BANK(blocks[1]) && HZ_BANK(blocks[4]) != HZ_BANK(blocks[5]));
    for (i = 0; i < 6; i++)
        CHECK(blocks[i] && blocks[i][0] == (char)(i + 1) && blocks[i][39999] == (char)(100 + i));
    a = hz_heap_peak();
    CHECK(a >= 240000UL);
    free(blocks[2]);
    blocks[2] = realloc(blocks[1], 50000u);
    CHECK(blocks[2] != NULL && blocks[2][0] == 2);
    for (i = 2; i < 6; i++)
        free(blocks[i]);
    free(blocks[0]);
    b = hz_heap_free();
    CHECK(b > 0 && hz_heap_largest() > 60000u);
    p = calloc(30000u, 2);
    CHECK(p != NULL && p[59999] == 0);
    free(p);
    p = malloc(65528u);                 /* the biggest block: a bank */
    CHECK(p != NULL && HZ_OFF(p) + 65527u > HZ_OFF(p));
    free(p);

    /* setjmp with the jmp_buf in far memory, recursion with locals passed to sprintf */
    jb = malloc(sizeof(jmp_buf));
    CHECK(jb != NULL);
    k = setjmp(*jb);
    if (k == 0)
        depth(30);
    CHECK(k == 42);
    free(jb);

    /* files: written from far memory, read straight into far memory */
    p = malloc(3000);
    for (i = 0; i < 3000; i++)
        p[i] = (char)i;
    f = fopen("/FARTEST.BIN", "wb");
    CHECK(f != NULL);
    if (f) {
        CHECK(fwrite(p, 1, 3000, f) == 3000);
        fclose(f);
    }
    memset(p, 0, 3000);
    fd = open("/FARTEST.BIN", O_RDONLY);
    CHECK(fd >= 3);
    if (fd >= 0) {
        CHECK(read(fd, p, 2000) == 2000 && read(fd, p + 2000, 1000) == 1000);
        close(fd);
    }
    CHECK((unsigned char)p[1999] == (1999 & 255) && (unsigned char)p[2999] == (2999 & 255));
    f = fopen("/FARTEST.BIN", "rb");
    if (f) {
        CHECK(fgets(buf, 10, f) != NULL && fread(p, 1, 100, f) == 100);
        fclose(f);
    }
    remove("/FARTEST.BIN");
    free(p);

    printf("farprog: %d checks, %d failures\n", checks, fails);
    if (!fails)
        printf("FARPROG PASS\n");
    return fails != 0;
}

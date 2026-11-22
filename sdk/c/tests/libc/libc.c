/* libc.c - the C library on Horizon, checked in the emulator (both models).
 *
 * Run by tests/run.py with the arguments  one "two words" 3  and the typed input
 * "42 apples" Enter, "a line" Enter. Prints a line for every failure and at the end
 * "libc: N checks, M failures" and LIBC PASS or LIBC FAIL.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <time.h>
#include <dirent.h>
#include <horizon.h>

static unsigned checks, fails;

static void check(int ok, const char *what)
{
    ++checks;
    if (!ok) {
        ++fails;
        printf("FAIL: %s\n", what);
    }
}

static void checks_eq(const char *got, const char *want, const char *what)
{
    ++checks;
    if (strcmp(got, want) != 0) {
        ++fails;
        printf("FAIL: %s: got [%s] want [%s]\n", what, got, want);
    }
}

static char buf[256];

static void t_printf(void)
{
    sprintf(buf, "%d %i %u %x %X %o", -123, 45, 65535u, 0xBEEF, 0xBEEF, 8);
    checks_eq(buf, "-123 45 65535 beef BEEF 10", "printf ints");
    sprintf(buf, "%ld %lu %lx %li", -1234567L, 4000000000UL, 0xDEADBEEFUL, 2147483647L);
    checks_eq(buf, "-1234567 4000000000 deadbeef 2147483647", "printf longs");
    sprintf(buf, "[%5d] [%-5d] [%05d] [%+d] [% d]", 42, 42, 42, 42, 42);
    checks_eq(buf, "[   42] [42   ] [00042] [+42] [ 42]", "printf widths");
    sprintf(buf, "[%s] [%10s] [%-10s] [%.3s] [%c%c]", "abc", "abc", "abc", "abcdef", 'x', 'y');
    checks_eq(buf, "[abc] [       abc] [abc       ] [abc] [xy]", "printf strings");
    sprintf(buf, "%#x %#o %%", 255, 8);
    checks_eq(buf, "0xff 010 %", "printf alternate forms");
    sprintf(buf, "%*d|%-*d|", 6, 7, 4, 8);
    checks_eq(buf, "     7|8   |", "printf star widths");
    check(snprintf(buf, 6, "%s", "abcdefgh") == 8 && strcmp(buf, "abcde") == 0, "snprintf truncates");
    sprintf(buf, "%hd %hu", (short)-5, (unsigned short)65000);
    checks_eq(buf, "-5 65000", "printf h");
}

static int cmpint(const void *a, const void *b)
{
    int x = *(const int *)a, y = *(const int *)b;
    return x < y ? -1 : x > y;
}

static void t_stdlib(void)
{
    static int v[50];
    int i, ok;
    char *end;
    for (i = 0; i < 50; i++)
        v[i] = (i * 37 + 11) % 50 - 25;
    qsort(v, 50, sizeof(int), cmpint);
    for (ok = 1, i = 1; i < 50; i++)
        if (v[i - 1] > v[i])
            ok = 0;
    check(ok && v[0] == -25 && v[49] == 24, "qsort");
    {
        int key = 7, *p = bsearch(&key, v, 50, sizeof(int), cmpint);
        check(p && *p == 7, "bsearch");
    }
    check(strtol("  -1234xyz", &end, 10) == -1234 && *end == 'x', "strtol base 10");
    check(strtol("ff", 0, 16) == 255 && strtol("0x1F", 0, 0) == 31 && strtol("017", 0, 0) == 15,
          "strtol bases");
    check(strtol("2147483647", 0, 10) == 2147483647L, "strtol long max");
    check(strtoul("4000000000", 0, 10) == 4000000000UL, "strtoul");
    check(atoi("-77") == -77 && atol("100000") == 100000L, "atoi atol");
    check(abs(-5) == 5 && labs(-70000L) == 70000L, "abs labs");
    {
        div_t d = div(17, 5);
        ldiv_t l = ldiv(-100001L, 7L);
        check(d.quot == 3 && d.rem == 2 && l.quot == -14285 && l.rem == -6, "div ldiv");
    }
    {
        int a1, a2, a3, b1;
        srand(1);
        a1 = rand(); a2 = rand(); a3 = rand();
        srand(1);
        b1 = rand();
        check(a1 == b1 && (a1 != a2 || a2 != a3), "rand repeats with srand");
        check(a1 >= 0 && a1 <= RAND_MAX && RAND_MAX == 32767, "rand range");
    }
}

static void t_string(void)
{
    char a[64], b[64];
    char *tok;
    strcpy(a, "hello");
    strcat(a, ", world");
    checks_eq(a, "hello, world", "strcpy strcat");
    check(strlen(a) == 12, "strlen");
    check(strcmp("abc", "abd") < 0 && strcmp("b", "a") > 0 && strcmp("x", "x") == 0, "strcmp");
    check(strncmp("abcX", "abcY", 3) == 0, "strncmp");
    check(strchr(a, 'w') == a + 7 && strrchr(a, 'l') == a + 10 && !strchr(a, 'z'), "strchr strrchr");
    check(strstr(a, "world") == a + 7 && !strstr(a, "xyz"), "strstr");
    check(strspn("aabbc", "ab") == 4 && strcspn("hello", "l") == 2, "strspn strcspn");
    memset(b, 'x', sizeof(b));
    memcpy(b, "12345", 5);
    check(memcmp(b, "12345xx", 7) == 0, "memcpy memset memcmp");
    memmove(b + 1, b, 5);
    check(memcmp(b, "112345x", 7) == 0, "memmove up");
    memmove(b, b + 2, 4);
    check(memcmp(b, "2345", 4) == 0, "memmove down");
    strcpy(a, "one two  three");
    tok = strtok(a, " ");
    check(tok && !strcmp(tok, "one"), "strtok 1");
    tok = strtok(0, " ");
    check(tok && !strcmp(tok, "two"), "strtok 2");
    tok = strtok(0, " ");
    check(tok && !strcmp(tok, "three") && !strtok(0, " "), "strtok 3");
    check(isdigit('7') && !isdigit('a') && isalpha('Q') && isspace(' ') && toupper('a') == 'A'
          && tolower('Z') == 'z' && isxdigit('f') && ispunct('!'), "ctype");
}

static void t_malloc(void)
{
    char *p[200];
    unsigned n = 0, i;
    unsigned long total = 0;
    char *q = malloc(1000);
    check(q != 0, "malloc 1000");
    memset(q, 0x5A, 1000);
    q = realloc(q, 3000);
    check(q && q[999] == 0x5A, "realloc keeps the data");
    free(q);
    q = calloc(100, 10);
    check(q && q[0] == 0 && q[999] == 0, "calloc zeroes");
    free(q);
    /* fill the heap with 1 KB blocks until malloc says no */
    while (n < 200 && (p[n] = malloc(1024)) != 0) {
        p[n][0] = (char)n;
        p[n][1023] = (char)n;
        total += 1024;
        ++n;
    }
    check(n > 0 && n < 200, "malloc runs out and returns NULL");
    for (i = 0; i < n; i++)
        if (p[i][0] != (char)i || p[i][1023] != (char)i)
            break;
    check(i == n, "malloc blocks do not overlap");
    printf("heap: %u blocks of 1 KB (%lu bytes) before NULL\n", n, total);
    while (n)
        free(p[--n]);
    q = malloc(4000);
    check(q != 0, "malloc again after free");
    free(q);
}

static void t_files(void)
{
    FILE *f, *g[5];
    int i, c, n;
    long pos;
    char line[64];

    f = fopen("/CTEST.TXT", "w");
    check(f != 0, "fopen w");
    if (!f)
        return;
    fprintf(f, "line %d\n", 1);
    fputs("line two\n", f);
    fwrite("line 3\n", 1, 7, f);
    for (i = 0; i < 300; i++)                   /* 3000 bytes: more than one buffer */
        fprintf(f, "%09d\n", i);
    pos = ftell(f);
    check(pos == 7 + 9 + 7 + 3000, "ftell while writing");
    check(fclose(f) == 0, "fclose");

    f = fopen("/CTEST.TXT", "r");
    check(f != 0, "fopen r");
    if (!f)
        return;
    check(fgets(line, sizeof(line), f) && !strcmp(line, "line 1\n"), "fgets 1");
    check(fgets(line, sizeof(line), f) && !strcmp(line, "line two\n"), "fgets 2");
    check(ftell(f) == 16, "ftell while reading");
    check(fscanf(f, "line %d", &n) == 1 && n == 3, "fscanf");
    check(fseek(f, 23 + 10 * 250, SEEK_SET) == 0, "fseek set");
    check(fgets(line, sizeof(line), f) && !strcmp(line, "000000250\n"), "read after fseek");
    check(fseek(f, -10, SEEK_END) == 0 && fgets(line, sizeof(line), f)
          && !strcmp(line, "000000299\n"), "fseek end");
    check(fseek(f, -20, SEEK_CUR) == 0 && fgets(line, sizeof(line), f)
          && !strcmp(line, "000000298\n"), "fseek cur");
    check(fgets(line, sizeof(line), f) && !strcmp(line, "000000299\n"), "the last line");
    c = fgetc(f);
    check(c == EOF && feof(f), "end of file");
    rewind(f);
    check(fgetc(f) == 'l' && ungetc('L', f) == 'L' && fgetc(f) == 'L', "rewind ungetc");
    fclose(f);

    f = fopen("/CTEST.TXT", "a");
    check(f && fputs("appended\n", f) >= 0 && fclose(f) == 0, "append");
    f = fopen("/CTEST.TXT", "r");
    check(f && fseek(f, -9, SEEK_END) == 0 && fgets(line, sizeof(line), f)
          && !strcmp(line, "appended\n"), "append is at the end");
    if (f)
        fclose(f);

    f = fopen("/CTEST.TXT", "r+");
    check(f != 0, "fopen r+");
    if (f) {
        fseek(f, 5, SEEK_SET);
        fputc('1', f);
        fputc('!', f);
        fseek(f, 0, SEEK_SET);
        check(fgets(line, sizeof(line), f) && !strcmp(line, "line 1!line two\n"), "r+ overwrite");
        fclose(f);
    }

    /* Horizon has 4 file handles in the whole system: the 5th fopen fails */
    for (i = 0; i < 5; i++) {
        sprintf(line, "/CTEST%d.TXT", i);
        g[i] = fopen(line, "w");
    }
    check(g[0] && g[1] && g[2] && g[3], "4 files open at once");
    check(g[4] == 0 && errno == ENFILE, "the 5th fopen fails with ENFILE");
    for (i = 0; i < 5; i++)
        if (g[i])
            fclose(g[i]);
    for (i = 0; i < 5; i++) {
        sprintf(line, "/CTEST%d.TXT", i);
        remove(line);
    }

    check(rename("/CTEST.TXT", "/CTEST2.TXT") == 0, "rename");
    f = fopen("/CTEST.TXT", "r");
    check(f == 0 && errno == ENOENT, "fopen of a missing file: NULL, ENOENT");
    check(remove("/CTEST2.TXT") == 0, "remove");
    check(remove("/CTEST2.TXT") != 0 && errno == ENOENT, "remove again fails");
    f = fopen("/NOFOLDER/X.TXT", "w");
    check(f == 0 && errno == ENOENT, "fopen in a missing folder");
    check(fopen("/X", "q") == 0 && errno == EINVAL, "bad mode");
}

#ifdef __CC816__
#include <fcntl.h>
#include <unistd.h>
/* POSIX descriptors (fcntl.h, unistd.h: DOS and Unix programs' open/read/write/lseek;
 * the Xargon port's board and config files) */
static void t_posix(void)
{
    static char buf[300];
    int fd, i, fds[5];
    fd = open("/CPOSIX.BIN", O_RDONLY);
    check(fd == -1 && errno == ENOENT, "open of a missing file: -1, ENOENT");
    fd = open("/CPOSIX.BIN", O_WRONLY | O_CREAT | O_TRUNC | O_BINARY, 0666);
    check(fd >= 3, "open O_CREAT: a descriptor 3 or above");
    for (i = 0; i < 300; i++)
        buf[i] = (char)i;
    check(write(fd, buf, 300) == 300, "write 300");
    check(lseek(fd, 0, SEEK_CUR) == 300, "lseek SEEK_CUR: the position after writing");
    check(lseek(fd, 10, SEEK_SET) == 10 && write(fd, "AB", 2) == 2, "lseek and overwrite");
    check(lseek(fd, 0, SEEK_END) == 300, "lseek SEEK_END: the size");
    check(read(fd, buf, 4) == -1 && errno == EBADF, "read on a write-only descriptor");
    check(close(fd) == 0, "close");
    check(close(fd) == -1 && errno == EBADF, "close again: EBADF");
    fd = open("/CPOSIX.BIN", O_CREAT | O_EXCL | O_WRONLY);
    check(fd == -1 && errno == EEXIST, "O_EXCL on a file that exists");
    fd = open("/CPOSIX.BIN", O_RDONLY);
    check(fd >= 3, "open O_RDONLY");
    memset(buf, 0, sizeof buf);
    check(read(fd, buf, 100) == 100 && buf[9] == 9 && buf[10] == 'A' && buf[11] == 'B'
          && buf[12] == 12, "read back");
    check(lseek(fd, -10, SEEK_END) == 290 && read(fd, buf, 100) == 10
          && buf[0] == (char)290 && buf[9] == (char)299, "lseek from the end, a short read");
    check(read(fd, buf, 100) == 0, "read at the end: 0");
    {                                   /* small reads (the read-ahead), seeks among them */
        int ok = 1;
        unsigned char b1;
        lseek(fd, 0, SEEK_SET);
        for (i = 0; i < 300; i++)
            if (read(fd, &b1, 1) != 1 || b1 != (unsigned char)(i == 10 ? 'A' : i == 11 ? 'B' : i))
                ok = 0;
        check(ok, "300 reads of 1 byte");
        check(lseek(fd, 20, SEEK_SET) == 20 && read(fd, &b1, 1) == 1 && b1 == 20 &&
              lseek(fd, 5, SEEK_CUR) == 26 && read(fd, &b1, 1) == 1 && b1 == 26 &&
              lseek(fd, 0, SEEK_CUR) == 27 && read(fd, buf, 280) == 273 && buf[0] == 27,
              "seeks between small reads, a read to the end");
        check(lseek(fd, 100, SEEK_SET) == 100 && read(fd, &b1, 1) == 1 && b1 == 100 &&
              lseek(fd, 400, SEEK_SET) == 400 && read(fd, &b1, 1) == 0 &&
              lseek(fd, 2, SEEK_SET) == 2 && read(fd, buf, 200) == 200 &&
              buf[0] == 2 && buf[199] == (char)201, "a seek past the end, back, a read");
    }
    check(lseek(fd, -1, SEEK_SET) == -1 && errno == EINVAL, "lseek before the start");
    check(write(fd, buf, 1) == -1 && errno == EBADF, "write on a read-only descriptor");
    check(isatty(fd) == 0 && isatty(1) == 1, "isatty");
    close(fd);
    fd = open("/CPOSIX.BIN", O_WRONLY | O_APPEND);
    check(fd >= 3 && write(fd, "end", 3) == 3 && close(fd) == 0, "O_APPEND");
    fd = open("/CPOSIX.BIN", O_RDWR);
    check(fd >= 3 && lseek(fd, 0, SEEK_END) == 303 && lseek(fd, 300, SEEK_SET) == 300
          && read(fd, buf, 3) == 3 && !memcmp(buf, "end", 3), "appended at the end");
    close(fd);
    fd = creat("/CPOSIX.BIN", 0);
    check(fd >= 3 && lseek(fd, 0, SEEK_END) == 0, "creat empties the file");
    close(fd);
    for (i = 0; i < 5; i++)
        fds[i] = open("/CPOSIX.BIN", O_RDONLY);
    check(fds[0] >= 3 && fds[3] >= 3 && fds[4] == -1, "4 descriptors at once, the 5th fails");
    for (i = 0; i < 5; i++)
        if (fds[i] >= 0)
            close(fds[i]);
    check(read(9, buf, 1) == -1 && errno == EBADF, "read on a descriptor not open");
    check(write(1, "posix: write(1)\n", 16) == 16, "write to stdout");
    check(unlink("/CPOSIX.BIN") == 0, "unlink");
    check(unlink("/CPOSIX.BIN") == -1 && errno == ENOENT, "unlink again: ENOENT");
}

/* fopen with the heap full: the file still opens (a 128-byte buffer, or the FILE's own
 * 2 bytes) and works; setvbuf _IONBF gives the 1 KB back; the heap's counts (the Digger
 * port: a recording could not be saved, fopen failed with ENOMEM and no hint) */
static void t_fullheap(void)
{
    static void *p[400];
    FILE *f;
    unsigned n = 0, k, peak0 = hz_heap_peak(), free0 = hz_heap_free();
    char line[64];
    check(free0 >= hz_heap_largest() && hz_heap_largest() > 1024, "hz_heap_free, largest");
    while (n < 200 && (p[n] = malloc(512)) != 0)            /* the heap filled ... */
        n++;
    k = n;
    while (n < 400 && (p[n] = malloc(6)) != 0)              /* ... to the last bytes */
        n++;
    check(k > 10 && n < 400 && hz_heap_largest() < 6, "the heap filled");
    check(hz_heap_peak() >= peak0 && hz_heap_peak() >= 512u * k, "hz_heap_peak");
    f = fopen("/CFULL.TXT", "w");
    check(f != 0 && f->size == 2, "fopen with the heap full");
    if (f) {
        for (k = 0; k < 100; k++)
            fprintf(f, "%03u\n", k);
        check(fclose(f) == 0, "fclose with the heap full");
    }
    free(p[0]);                 /* 512 bytes free: the 128-byte buffer this time */
    p[0] = 0;
    f = fopen("/CFULL.TXT", "r");
    check(f != 0 && f->size == 128, "fopen r with the heap nearly full");
    if (f) {
        for (k = 0; k < 99; k++)
            fgets(line, sizeof line, f);
        check(fgets(line, sizeof line, f) && !strcmp(line, "099\n"), "read with the heap full");
        check(fseek(f, 4, SEEK_SET) == 0 && fgets(line, sizeof line, f) &&
              !strcmp(line, "001\n"), "fseek with the heap full");
        fclose(f);
    }
    while (n)
        free(p[--n]);
    check(hz_heap_free() == free0, "the heap whole again");
    f = fopen("/CFULL.TXT", "r");
    check(f != 0 && setvbuf(f, NULL, _IONBF, 0) == 0 && hz_heap_free() == free0,
          "setvbuf _IONBF gives the buffer back");
    if (f) {
        check(fgets(line, sizeof line, f) && !strcmp(line, "000\n"), "read unbuffered");
        fclose(f);
    }
    remove("/CFULL.TXT");
    check(strstr(strerror(ENOMEM), "heap") != 0, "strerror(ENOMEM) names the heap");
}
#endif

static void t_dir(void)
{
    DIR *d = opendir("/");
    struct dirent *e;
    int sys = 0, n = 0;
    check(d != 0, "opendir /");
    if (!d)
        return;
    while ((e = readdir(d)) != 0) {
        ++n;
        if (!strcmp(e->d_name, "SYSTEM") && (e->d_attr & HZ_ATTR_DIR))
            sys = 1;
    }
    closedir(d);
    check(n > 3 && sys, "readdir finds /SYSTEM");
    check(opendir("/NOSUCH") == 0, "opendir of a missing folder");
}

static void t_time(void)
{
    time_t t = time(0);
    clock_t c1 = clock(), c2;
    unsigned long ms = hz_uptime();
    struct tm *tm = gmtime(&t);
    check(t >= 946684800L, "time() after 2000");
    check(tm && tm->tm_year >= 100, "gmtime");
    hz_sleep(200);
    c2 = clock();
    check(c2 - c1 >= 9 && c2 - c1 <= 12, "clock() counts 50 a second");
    /* (hz_uptime counts in steps of 10 ms: one step less may show) */
    check(hz_uptime() - ms >= 190, "hz_sleep and hz_uptime");
}

static void t_far(void)
{
    unsigned char __far *b = hz_far_alloc();
    static char src[100];
    char back[100];
    unsigned i;
    check(b != 0, "hz_far_alloc");
    if (!b)
        return;
    for (i = 0; i < 100; i++)
        src[i] = (char)(i * 3);
    hz_far_copy(b + 1000, src, 100);
    hz_far_copy(back, b + 1000, 100);
    check(memcmp(back, src, 100) == 0, "hz_far_copy there and back");
    hz_far_set(b, 0x77, 5000);
    check(b[0] == 0x77 && b[4999] == 0x77 && b[5000] != 0x77 + 1, "hz_far_set");
    b[65535u] = 9;
    check(b[65535u] == 9, "far pointer at the bank's end");
    hz_far_free(b);
    check(hz_errno == 0, "hz_far_free");
}

static void t_errno(void)
{
    check(hz_open("/NO/SUCH/FILE", HZ_O_READ) == -1 && hz_errno == HZ_ENOPATH, "hz_errno set");
    check(hz_getpid() > 0 && hz_errno == 0, "hz_errno cleared");
    check(strlen(strerror(ENOENT)) > 0, "strerror");
    check(hz_errno_to_errno(HZ_ENOFILE) == ENOENT, "hz_errno_to_errno");
}

static void bye(void)
{
    printf("atexit ran\n");
}

int main(int argc, char **argv)
{
    char line[80];
    int n;
    atexit(bye);
    check(argc == 4 && !strcmp(argv[1], "one") && !strcmp(argv[2], "two words")
          && !strcmp(argv[3], "3") && argv[4] == 0, "argc, argv");
    t_printf();
    t_string();
    t_stdlib();
    t_malloc();
#ifdef __CC816__
    t_fullheap();
#endif
    t_files();
#ifdef __CC816__
    t_posix();
#endif
    t_dir();
    t_time();
    t_far();
    t_errno();
    printf("type a number: ");
    check(scanf("%d", &n) == 1 && n == 42, "scanf from the keyboard");
    check(fgets(line, sizeof(line), stdin) && !strcmp(line, " apples\n"), "rest of the line");
    printf("type a line: ");
    check(fgets(line, sizeof(line), stdin) && !strcmp(line, "a line\n"), "fgets(stdin)");
    printf("stack free now: %u\n", hz_stack_free());
    printf("libc: %u checks, %u failures\n", checks, fails);
    printf(fails ? "LIBC FAIL\n" : "LIBC PASS\n");
    return fails ? 1 : 0;
}

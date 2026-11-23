/* bigio.c - the C SDK's test: read and write of 40,000 bytes on a descriptor. ssize_t is
 * a 16-bit int, so one call moves at most 32,767 bytes: a short count (as POSIX allows),
 * never one that looks negative and is taken for an error; a loop gets the rest. The
 * buffer is near in the near data models and far with hcc --data far. */
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>

#define N 40000u

static unsigned char big[N];
static unsigned checks, fails;

static void check(int ok, const char *what)
{
    ++checks;
    printf("%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok)
        ++fails;
}

int main(void)
{
    unsigned u, done;
    int fd, k, ok;

    for (u = 0; u < N; u++)
        big[u] = (unsigned char)(u ^ u >> 8);
    fd = open("/CBIG.BIN", O_WRONLY | O_CREAT | O_TRUNC);
    check(fd >= 3, "open for writing");
    k = write(fd, big, N);
    check(k == 32767, "write of 40,000 bytes: 32,767 (not negative)");
    done = k > 0 ? (unsigned)k : 0;
    while (done < N && (k = write(fd, big + done, N - done)) > 0)
        done += (unsigned)k;
    check(done == N, "a write loop: all 40,000");
    check(lseek(fd, 0, SEEK_END) == (long)N && close(fd) == 0, "the file's size: 40,000");

    memset(big, 0, sizeof big);
    fd = open("/CBIG.BIN", O_RDONLY);
    check(fd >= 3, "open for reading");
    k = read(fd, big, N);
    check(k == 32767, "read of 40,000 bytes: 32,767 (not negative)");
    check(k >= 0, "so a test of < 0 sees no error");
    done = k > 0 ? (unsigned)k : 0;
    while (done < N && (k = read(fd, big + done, N - done)) > 0)
        done += (unsigned)k;
    check(done == N, "a read loop: all 40,000");
    check(read(fd, big, N) == 0, "then 0 at the end");
    ok = 1;
    for (u = 0; u < N; u++)
        if (big[u] != (unsigned char)(u ^ u >> 8))
            ok = 0;
    check(ok, "every byte read back");
    check(lseek(fd, 1000, SEEK_SET) == 1000 && read(fd, big, 65535u) == 32767 &&
          big[0] == (unsigned char)(1000u ^ 1000u >> 8), "a read of 65,535 from 1,000: 32,767");
    close(fd);
    check(unlink("/CBIG.BIN") == 0, "unlink");
    printf("bigio: %u checks, %u failures\n", checks, fails);
    if (!fails)
        printf("BIGIO PASS\n");
    return 0;
}

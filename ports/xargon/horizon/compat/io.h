/* io.h - Turbo C's file handles: POSIX descriptors (the SDK's fcntl.h, unistd.h) */
#ifndef XIO_H
#define XIO_H
#include <fcntl.h>
#include <unistd.h>
#define _open(p, f) open((p), (f))
#define _creat(p, m) creat((p), (m))
#define _read read
#define _write write
#define _close close
long filelength(int fd);
#endif

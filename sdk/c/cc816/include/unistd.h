/* unistd.h - POSIX's file descriptor calls (cc816): read, write, lseek, close, unlink,
 * isatty. Descriptors 0, 1 and 2 are the console (stdin, stdout, stderr, through
 * stdio); open (fcntl.h) gives 3 and up, one for each of Horizon's file handles.
 * lib/cc816/posixio.c. */
#ifndef _UNISTD_H
#define _UNISTD_H
#include <stddef.h>

#ifndef SEEK_SET
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#endif
#define STDIN_FILENO  0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2

typedef long off_t;
typedef int ssize_t;

/* bytes read (0 at the end of the file), or -1 and errno. At most 65,535 a call (size_t) */
ssize_t read(int fd, void *buf, size_t n);
/* bytes written, or -1 and errno */
ssize_t write(int fd, const void *buf, size_t n);
/* the new position from the start, or -1 and errno (ESPIPE on the console). Any 32-bit
 * position; SEEK_END counts from the file's size */
off_t lseek(int fd, off_t off, int whence);
int close(int fd);
int unlink(const char *path);
int isatty(int fd);

#endif

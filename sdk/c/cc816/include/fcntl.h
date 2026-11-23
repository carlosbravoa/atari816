/* fcntl.h - POSIX's open() and its flags (cc816), for programs written for Unix or DOS
 * that use file descriptors instead of FILE: open, creat (here), read, write, lseek,
 * close (unistd.h). Implemented over Horizon's file calls (lib/posixio.c), without a
 * buffer: each read or write is one call to the card, so read and write in blocks.
 * Horizon has 4 file handles for the whole system (as for fopen). */
#ifndef _FCNTL_H
#define _FCNTL_H

#define O_RDONLY  0x0000
#define O_WRONLY  0x0001
#define O_RDWR    0x0002
#define O_ACCMODE 0x0003
#define O_CREAT   0x0100        /* create the file when it does not exist */
#define O_TRUNC   0x0200        /* make it empty */
#define O_EXCL    0x0400        /* with O_CREAT: fail (EEXIST) when it exists */
#define O_APPEND  0x0800        /* every write at the end */
/* DOS and Windows compilers' flags (no line-end conversion is ever done here) */
#define O_BINARY  0
#define O_TEXT    0
#define O_NOCTTY  0
#define O_NONBLOCK 0

/* -> a descriptor (3 and up), or -1 and errno. The mode (permissions) is ignored */
int open(const char *path, int flags, ...);
/* open(path, O_WRONLY | O_CREAT | O_TRUNC) */
int creat(const char *path, int mode);

#endif

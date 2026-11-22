/* stdio_int.h - what the cc816 C library's stdio files share (not for programs). */
#define F_READ   0x0001         /* opened for reading */
#define F_WRITE  0x0002         /* opened for writing */
#define F_RDING  0x0004         /* the buffer holds bytes read */
#define F_WRING  0x0008         /* the buffer holds bytes to write */
#define F_EOF    0x0010
#define F_ERR    0x0020
#define F_LINE   0x0040         /* line-buffered */
#define F_NOBUF  0x0080         /* unbuffered */
#define F_MYBUF  0x0100         /* the buffer is the library's (malloc) */
#define F_APPEND 0x0200         /* "a": every write at the end */
#define F_CON    0x0400         /* the console */
#define F_STATIC 0x0800         /* stdin, stdout, stderr (not malloc'd) */

#define FILEBUF  1024           /* a file's buffer */
#define CONBUF   128            /* the console's */

extern FILE *__hz_files;
int __hz_flushw(FILE *f);
int __hz_putslow(int c, FILE *f);
int __hz_getslow(FILE *f);

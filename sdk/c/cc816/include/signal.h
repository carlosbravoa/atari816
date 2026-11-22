/* signal.h - cc816 (Horizon C SDK): Horizon has no signals; signal() and raise() fail. */
#ifndef _SIGNAL_H
#define _SIGNAL_H
typedef int sig_atomic_t;
typedef void (*__hz_sighandler)(int);
#define SIG_DFL ((__hz_sighandler)0)
#define SIG_IGN ((__hz_sighandler)1)
#define SIG_ERR ((__hz_sighandler)-1)
#define SIGABRT 6
#define SIGFPE 8
#define SIGILL 4
#define SIGINT 2
#define SIGSEGV 11
#define SIGTERM 15
__hz_sighandler signal(int sig, __hz_sighandler f);
int raise(int sig);
#endif

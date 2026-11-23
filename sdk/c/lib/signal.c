/* signal.c - Horizon has no signals: signal() and raise() fail (cc816) */
#include <signal.h>

__hz_sighandler signal(int sig, __hz_sighandler f)
{
    (void)sig;
    (void)f;
    return SIG_ERR;
}

int raise(int sig)
{
    (void)sig;
    return -1;
}

/* hzerr.c - Horizon error codes: to errno (errno.h), and in words. */
#include <errno.h>
#include <horizon.h>

int hz_errno_to_errno(unsigned code)
{
    switch (code) {
    case 0:              return 0;
    case HZ_EINVAL:      return EINVAL;
    case HZ_ENOMEM:      return ENOMEM;
    case HZ_ENOENT:      return ENOENT;
    case HZ_EFAULT:      return EFAULT;
    case HZ_ECHILD:      return ECHILD;
    case HZ_EAGAIN:      return EAGAIN;
    case HZ_ENOSYS:      return ENOSYS;
    case HZ_ERUNNING:    return EBUSY;
    case HZ_ENODEV:      return ENODEV;
    case HZ_ECANCELED:   return EINTR;
    case HZ_ENOFILE:     return ENOENT;
    case HZ_ENOPATH:     return ENOENT;
    case HZ_EBADNAME:    return EINVAL;
    case HZ_EDENIED:     return EACCES;
    case HZ_EEXIST:      return EEXIST;
    case HZ_ENFILE:      return ENFILE;      /* the 4 handles of the whole system */
    case HZ_EBADH:       return EBADF;
    case HZ_EIO + 0x81:  return EFAULT;
    case HZ_E_NOLINK:    return ENODEV;
    case HZ_E_LOST:      return EIO;
    case HZ_E_NOSVC:     return ENOSYS;
    case HZ_E_BADADDR:   return EINVAL;
    case HZ_E_NONAME:    return EHOSTUNREACH;
    case HZ_E_REFUSED:   return ECONNREFUSED;
    case HZ_E_TIMEOUT:   return ETIMEDOUT;
    case HZ_E_HTTP:      return EIO;
    case HZ_E_CLOSED:    return EPIPE;
    case HZ_E_TLS:       return EIO;
    case HZ_E_PCBUSY:    return EAGAIN;
    case HZ_E_NET:       return EIO;
    }
    return EIO;
}

const char *hz_strerror(unsigned code)
{
    switch (code) {
    case 0:              return "no error";
    case HZ_EINVAL:      return "invalid argument";
    case HZ_ENOMEM:      return "no free memory bank";
    case HZ_EFAULT:      return "bad address";
    case HZ_ECHILD:      return "no such task";
    case HZ_EAGAIN:      return "busy, try again";
    case HZ_ENOSYS:      return "no such syscall";
    case HZ_ERUNNING:    return "already running";
    case HZ_ENODEV:      return "not on this machine";
    case HZ_ECANCELED:   return "cancelled";
    case HZ_ENOFILE:     return "no such file";
    case HZ_ENOPATH:     return "no such folder";
    case HZ_EBADNAME:    return "invalid name";
    case HZ_EDENIED:     return "access denied";
    case HZ_EEXIST:      return "already exists";
    case HZ_ENFILE:      return "too many open files (4 in the whole system)";
    case HZ_EBADH:       return "bad file handle";
    case HZ_E_NOLINK:    return "no PC link";
    case HZ_E_LOST:      return "the PC link was lost";
    case HZ_E_NOSVC:     return "no such service";
    case HZ_E_BADADDR:   return "bad address";
    case HZ_E_NONAME:    return "name not found";
    case HZ_E_REFUSED:   return "refused or unreachable";
    case HZ_E_TIMEOUT:   return "timeout";
    case HZ_E_HTTP:      return "HTTP error";
    case HZ_E_CLOSED:    return "connection closed";
    case HZ_E_TLS:       return "TLS failed";
    case HZ_E_PCBUSY:    return "too many connections on the PC";
    case HZ_E_NET:       return "network error";
    }
    if (code >= HZ_EIO)
        return "I/O error";
    return "error";
}

/* errno from the last hz_ call (used by the C library's file functions) */
int __hz_seterrno(void)
{
    errno = hz_errno_to_errno(hz_errno);
    return -1;
}

/* strerror and perror replace the C library's: its strerror returns a pointer with a
 * wrong bank (the compiler bug hzc.fix_asm repairs, in the binary-only library) */
#include <stdio.h>

char *strerror(int e)
{
    static char other[16];
    switch (e) {
    case 0:            return "No error";
    case EPERM:        return "Operation not permitted";
    case ENOENT:       return "No such file or directory";
    case ESRCH:        return "No such process";
    case EINTR:        return "Interrupted";
    case EIO:          return "I/O error";
    case E2BIG:        return "Argument list too long";
    case EBADF:        return "Bad file handle";
    case ECHILD:       return "No child process";
    case ENOMEM:       return "Not enough memory";
    case EACCES:       return "Access denied";
    case EFAULT:       return "Bad address";
    case EBUSY:        return "Busy";
    case EEXIST:       return "File exists";
    case ENODEV:       return "No such device";
    case ENOTDIR:      return "Not a directory";
    case EISDIR:       return "Is a directory";
    case EINVAL:       return "Invalid argument";
    case ENFILE:       return "Too many open files in the system";
    case EMFILE:       return "Too many open files";
    case ENOSPC:       return "No space left";
    case ESPIPE:       return "Not seekable";
    case EROFS:        return "Read-only";
    case EPIPE:        return "Broken pipe";
    case EDOM:         return "Argument out of domain";
    case ERANGE:       return "Result out of range";
    case EAGAIN:       return "Try again";
    case ETIMEDOUT:    return "Timed out";
    case ECONNREFUSED: return "Connection refused";
    case EHOSTUNREACH: return "Host unreachable";
    case ENOSYS:       return "Not implemented";
    }
    sprintf(other, "Error %d", e);
    return other;
}

void perror(const char *s)
{
    if (s && *s) {
        fputs(s, stderr);
        fputs(": ", stderr);
    }
    fputs(strerror(errno), stderr);
    fputs("\n", stderr);
}

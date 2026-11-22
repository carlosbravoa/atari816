/* switches.c - switch on a long, sparse and negative cases, fall through, a default in
 * the middle, nested switches, Duff's device, a switch on a char. */
static int on_long(long v)
{
    switch (v) {
    case 0: return 0;
    case 100000L: return 1;
    case -100000L: return 2;
    case 0x7FFFFFFFL: return 3;
    case 65536L: return 4;
    case 1: return 5;
    default: return 9;
    }
}

static int sparse(int v)
{
    switch (v) {
    case -32768: return 1;
    case -1: return 2;
    case 7: return 3;
    case 1000: return 4;
    case 32767: return 5;
    case 20000: return 6;
    }
    return 0;
}

static int fall(int v)
{
    int s = 0;
    switch (v) {
    case 1: s += 1;
    case 2: s += 10;
    default: s += 100;
    case 3: s += 1000; break;
    case 4: s = -1;
    }
    return s;
}

static void duff(char *to, const char *from, int count)
{
    int n = (count + 7) / 8;
    switch (count % 8) {
    case 0: do { *to++ = *from++;
    case 7:      *to++ = *from++;
    case 6:      *to++ = *from++;
    case 5:      *to++ = *from++;
    case 4:      *to++ = *from++;
    case 3:      *to++ = *from++;
    case 2:      *to++ = *from++;
    case 1:      *to++ = *from++;
            } while (--n > 0);
    }
}

static int nested(int a, int b)
{
    switch (a) {
    case 1:
        switch (b) {
        case 1: return 11;
        case 2: break;
        }
        return 10;
    case 2: return 20;
    }
    return 0;
}

static int on_char(unsigned char c)
{
    switch (c) {
    case 'a': return 1;
    case 200: return 2;
    case 255: return 3;
    }
    return 0;
}

int main(void)
{
    char buf[20];
    int i;
    if (on_long(100000L) != 1 || on_long(-100000L) != 2 || on_long(0x7FFFFFFFL) != 3 ||
        on_long(65536L) != 4 || on_long(1) != 5 || on_long(2) != 9 || on_long(0) != 0 ||
        on_long(100001L) != 9 || on_long(65537L) != 9)
        return 1;
    if (sparse(-32768) != 1 || sparse(-1) != 2 || sparse(7) != 3 || sparse(1000) != 4 ||
        sparse(32767) != 5 || sparse(20000) != 6 || sparse(8) != 0 || sparse(0) != 0)
        return 2;
    if (fall(1) != 1111 || fall(2) != 1110 || fall(3) != 1000 || fall(4) != -1 ||
        fall(9) != 1100)
        return 3;
    for (i = 1; i < 20; i++) {
        int k;
        for (k = 0; k < 20; k++)
            buf[k] = 0;
        duff(buf, "abcdefghijklmnopqrs", i);
        if (buf[i - 1] != 'a' + i - 1 || buf[i] != 0)
            return 4;
    }
    if (nested(1, 1) != 11 || nested(1, 2) != 10 || nested(2, 0) != 20 || nested(3, 3) != 0)
        return 5;
    if (on_char('a') != 1 || on_char(200) != 2 || on_char(255) != 3 || on_char(0) != 0)
        return 6;
    return 0;
}

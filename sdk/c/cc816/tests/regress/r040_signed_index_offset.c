/* r040_signed_index_offset.c - a[d + 1] with a signed d: the constant was taken out of
 * the index into the address (a + 1, index d), so d = -1 put $FFFF in the index register,
 * and the 65816 adds an index to an absolute address in 24 bits: the load read a + 1 +
 * $FFFF, the next bank, instead of a[0] (a garbage value, or a kill for a bank not
 * allocated). Prince of Persia's dir_front[Char.direction + 1] with a direction of -1
 * (facing left): the column in front of the kid came out wrong, and how wrong depended on
 * what lay in the next bank. A positive constant now stays in a signed index; an unsigned
 * index (never negative) and a[i - k] keep the cheaper form. Found by the Prince of Persia
 * port. */
typedef signed char sbyte;

struct ch { unsigned char frame, x, y; sbyte direction; sbyte col; };
struct ch Char = {1, 2, 3, -1, 6};
const sbyte dir_front[] = {-1, 1};
const sbyte dir_behind[] = {1, -1};
int words[3] = {100, 200, 300};
short infrontx;

static int front(void)
{
    infrontx = dir_front[Char.direction + 1] + Char.col;
    return infrontx;
}

static int via_local(sbyte d)
{
    return dir_behind[d + 1];
}

static int via_pointer(const int *p, int i)
{
    return p[i + 2];
}

static void store(int i, int v)
{
    words[i + 1] = v;
}

int main(void)
{
    volatile int m1 = -1, m2 = -2;
    if (front() != 5)
        return 1;
    Char.direction = 1;
    if (front() != 7)
        return 2;
    if (via_local(-1) != 1 || via_local(0) != -1)
        return 3;
    if (via_pointer(words, m1) != 200 || via_pointer(words, m2) != 100)
        return 4;
    store(m1, 111);
    if (words[0] != 111 || words[1] != 200)
        return 5;
    if (words[m1 + 3] != 300 || dir_front[m1 + 1] != -1)
        return 6;
    return 0;
}

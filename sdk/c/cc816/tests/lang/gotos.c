/* gotos.c - goto into and out of blocks and loops, forwards and backwards; labels in
 * code that is not reached otherwise (if (0) { label: ... }), cases inside an if (0). */
static int find(const int *a, int n, int key)
{
    int i, j;
    for (i = 0; i < n; i++)
        for (j = 0; j < 2; j++)
            if (a[i] == key + j)
                goto found;
    return -1;
found:
    return i * 10 + j;
}

static int into(int k)
{
    int s = 0;
    if (k)
        goto inside;
    s = 100;
    {
        int t = 5;
        s += t;
    inside:
        s += 1;
    }
    return s;
}

static int dead_label(int k)
{
    int s = 0;
    if (0) {
    again:
        s += 10;
    }
    if (k-- > 0)
        goto again;
    return s;
}

static int case_in_if0(int k)
{
    int s = 0;
    switch (k) {
        if (0) {
        case 1:
            s = 1;
        }
        s += 2;
        break;
    case 2:
        s = 20;
    }
    return s;
}

int main(void)
{
    static const int a[] = { 3, 8, 12 };
    int n = 0;
back:
    n++;
    if (n < 5)
        goto back;
    if (n != 5)
        return 1;
    if (find(a, 3, 8) != 10 || find(a, 3, 11) != 21 || find(a, 3, 50) != -1)
        return 2;
    if (into(1) != 1 || into(0) != 106)
        return 3;
    if (dead_label(3) != 30 || dead_label(0) != 0)
        return 4;
    if (case_in_if0(1) != 3 || case_in_if0(2) != 20 || case_in_if0(0) != 0)
        return 5;
    return 0;
}

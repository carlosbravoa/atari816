/* stmtexpr.c - statement expressions ({ ...; value; }) (a GNU extension cc816 has). */
#define MAX(a, b) ({ int _a = (a), _b = (b); _a > _b ? _a : _b; })

int main(void)
{
    int i = 3, n = 0;
    int m = MAX(i++, 2);
    long l = ({ long t = 70000L; t + 1; });
    if (m != 3 || i != 4 || l != 70001L)
        return 1;
    ({ n = 5; });
    if (n != 5)
        return 2;
    n = ({ int k, s = 0; for (k = 0; k < 4; k++) s += k; s; });
    if (n != 6)
        return 3;
    return 0;
}

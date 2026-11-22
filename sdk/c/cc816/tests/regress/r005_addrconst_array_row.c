/* r005_addrconst_array_row.c - a row of a 2-D array (a[2], an int * by array-to-pointer
 * conversion) is an address constant, but cc816 refuses it as a static initialiser:
 * "initialiser is not a constant" (&a[2][0] and &a[1][2] are accepted).
 * Found by genfuzz --features globals (an array of structures with pointers). */
static int a[3][4] = { { 1, 2, 3, 4 }, { 5, 6, 7, 8 }, { 9, 10, 11, 12 } };
static int *p = a[2];
struct T { const char *s; int *q; };
static struct T t[1] = { { "x", a[1] } };

int main(void)
{
    return (*p == 9 && t[0].q[3] == 8) ? 0 : 1;
}

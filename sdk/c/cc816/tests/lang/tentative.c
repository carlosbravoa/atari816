/* tentative.c - tentative definitions: int x; int x; int x = 5; an array declared
 * without a size and then with one; a structure defined after a variable of its type. */
int x;
int x;
int x = 5;
int y;
int arr[];
int arr[10];
struct later g1;            /* its structure is defined below: the size is known then */
struct later { long a, b, c; };
struct later g2;
static int st;
static int st;
char after[3];

int main(void)
{
    int i;
    if (x != 5 || y != 0 || st != 0)
        return 1;
    for (i = 0; i < 10; i++)
        arr[i] = i;
    after[0] = 1;           /* would land in arr if arr had 1 element */
    if (arr[9] != 9 || sizeof arr != 20)
        return 2;
    g1.c = 123456L;
    g2.a = 7;
    if (sizeof g1 != 12 || g1.c != 123456L || g2.a != 7 || g1.a != 0)
        return 3;
    if ((char *)&g2 - (char *)&g1 != 12 && (char *)&g1 - (char *)&g2 != 12 &&
        (char *)&g1 == (char *)&g2)
        return 4;
    return 0;
}

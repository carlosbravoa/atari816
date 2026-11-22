/* r014_tentative_size.c - a tentative definition's size: int a[]; then int a[10]; kept
 * one element, and a variable of a structure defined only later in the file got 0 bytes:
 * the zeroed variables after them were written over. The size is now the last
 * declaration's (and the structure's, at the end of the file). */
int a[];
int guard1[4];
int a[10];
struct later g;
int guard2[4];
struct later { long x, y; };

int main(void)
{
    int i;
    for (i = 0; i < 10; i++)
        a[i] = -1;
    g.x = -1;
    g.y = -1;
    for (i = 0; i < 4; i++)
        if (guard1[i] != 0 || guard2[i] != 0)
            return 1;
    if (sizeof a != 20 || sizeof g != 8)
        return 2;
    return 0;
}

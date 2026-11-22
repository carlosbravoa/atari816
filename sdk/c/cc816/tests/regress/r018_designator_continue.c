/* r018_designator_continue.c - after a designator into a member (.b.x = 3) or an element
 * ([1] = 3 of an array of structures), the values that follow go on inside it (b.y, then
 * the next member); cc816 went on with the next member of the outer structure. Found by
 * tests/lang/designators.c. */
struct pt { int x, y; };
struct box { struct pt a, b; int tag; };

static struct box g = { {1, 2}, .b.x = 3, 4, 5 };
static struct pt arr[3] = { [1] = 7, 8, 9 };

int main(void)
{
    struct box l = { .b.x = 3, 4, 5 };
    if (g.b.x != 3 || g.b.y != 4 || g.tag != 5)
        return 1;
    if (l.b.y != 4 || l.tag != 5 || l.a.x != 0)
        return 2;
    if (arr[1].x != 7 || arr[1].y != 8 || arr[2].x != 9)
        return 3;
    return 0;
}

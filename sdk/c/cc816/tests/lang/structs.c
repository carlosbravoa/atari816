/* structs.c - structures by value: passed, returned, assigned, nested, with arrays,
 * returned through a function pointer, chained member access of a returned one. */
struct v3 { int x, y, z; };
struct big { char name[10]; long id; struct v3 pos; };

static struct v3 add(struct v3 a, struct v3 b)
{
    a.x += b.x;
    a.y += b.y;
    a.z += b.z;
    return a;
}

static struct big make(long id)
{
    struct big b = { "player", 0, { 1, 2, 3 } };
    b.id = id;
    return b;
}

static int sumv(struct v3 v) { return v.x + v.y + v.z; }

int main(void)
{
    struct v3 a = { 1, 2, 3 }, b = { 10, 20, 30 }, c;
    struct v3 (*fp)(struct v3, struct v3) = add;
    struct big g, h;
    c = add(a, b);
    if (c.x != 11 || c.y != 22 || c.z != 33 || a.x != 1)
        return 1;
    c = fp(c, a);
    if (c.z != 36)
        return 2;
    g = make(70000L);
    h = g;
    h.name[0] = 'P';
    if (g.id != 70000L || g.name[0] != 'p' || h.name[0] != 'P' || h.pos.z != 3)
        return 3;
    if (make(5).pos.y != 2 || add(a, a).y != 4 || sumv(add(a, b)) != 66)
        return 4;
    {
        struct v3 arr[3];
        arr[1] = a;
        arr[2] = arr[1];
        arr[0] = add(arr[1], arr[2]);
        if (arr[0].x != 2 || arr[2].z != 3)
            return 5;
    }
    return 0;
}

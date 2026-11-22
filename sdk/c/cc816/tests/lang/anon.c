/* anon.c - anonymous structures and unions (C11): their members are the outer one's. */
struct shape {
    int kind;
    union {
        struct { int w, h; };
        struct { int r; };
        long area;
    };
    struct { unsigned char red, green; } colour;
};

int main(void)
{
    struct shape s = { 1, { { 3, 4 } }, { 9, 8 } };
    struct shape t = { .kind = 2, .r = 5 };
    if (s.w != 3 || s.h != 4 || s.r != 3 || s.colour.green != 8)
        return 1;
    if (t.r != 5 || t.w != 5 || t.kind != 2)
        return 2;
    s.area = 0x00050006L;
    if (s.w != 6 || s.h != 5)
        return 3;
    if (sizeof(struct shape) != 2 + 4 + 2)
        return 4;
    return 0;
}

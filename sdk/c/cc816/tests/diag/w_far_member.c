/* the address of a member reached through a far pointer is far: given to a near pointer
 * parameter or variable the bank is lost (it was silent before: Prince of Persia's
 * x_to_xh_and_xl(obj_x, &entry->xh, &entry->xl) wrote into the main bank) */
typedef struct { int a, b; } pair;
typedef struct { signed char xh, xl; pair clip; } entry;
__far entry tab[4];
void take(const pair *r);
void two(signed char *xh, signed char *xl);
int main(void)
{
    entry __far *p = &tab[1];
    signed char __far *f;
    take(&p->clip);         // EXPECT: warning: passing
    two(&p->xh, &tab[2].xl);    // EXPECT: warning: passing
    f = &p->xl;
    return *f;
}

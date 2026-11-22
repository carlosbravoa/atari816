/* r013_dead_branch_labels.c - the branch of an if with a constant condition was left
 * out even when a label or a case was in it: a goto into if (0) { ... } was refused
 * ("label used but not defined") and a case inside an if (0) in a switch was lost (the
 * switch took the default). Found by the c-testsuite (00213.c). */
static int f(int k)
{
    int s = 0;
    switch (k) {
        if (0) {
        case 1:
            s = 10;
        }
        s += 1;
        break;
    default:
        s = 100;
    }
    return s;
}

int main(void)
{
    int n = 2, s = 0;
    if (0) {
    again:
        s += 5;
    }
    if (n-- > 0)
        goto again;
    if (s != 10)
        return 1;
    if (f(1) != 11 || f(0) != 100)
        return 2;
    s = 1 ? 0 : ({ inside: 2; });       /* the label keeps the branch */
    if (n == -1 && s == 0)
        goto out;
    goto inside;
out:
    return s;
}

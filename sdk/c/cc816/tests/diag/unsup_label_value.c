/* labels as values (computed goto) */
int main(void)
{
    void *p = &&done;       // EXPECT: error: cc816 does not support labels as values
    goto *p;
done:
    return 0;
}

/* a label twice, a goto to a label that is not there */
int main(void)
{
    int i = 0;
again:
    i++;
again:                  // EXPECT: error: duplicate label 'again'
    if (i < 3)
        goto again;
    goto nowhere;       // EXPECT: error: label 'nowhere' used but not defined
    return i;
}

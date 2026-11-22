/* GNU case ranges */
int kind(int c)
{
    switch (c) {
    case 'a' ... 'z':
        return 1;
    case 'm':               // EXPECT: error: duplicate case value 109
        return 2;
    case 1000 ... 2000:
        return 3;
    case 1500 ... 1600:     // EXPECT: error: the case range 1500 ... 1600 overlaps another
        return 4;
    }
    return 0;
}
long wide(long v)
{
    switch (v) {
    case 0 ... 100000L:     // EXPECT: error: cc816 does not support a case range of more than 256 values in a switch on a long
        return 1;
    }
    return 0;
}
int main(void) { return kind('q') + (int)wide(5); }

/* GNU case ranges */
int kind(int c)
{
    switch (c) {
    case 'a' ... 'z':       // EXPECT: error: cc816 does not support ranges (a ... b) in case labels and initialisers
        return 1;
    }
    return 0;
}
int main(void) { return kind('q'); }

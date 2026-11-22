/* bad array sizes */
int neg[-1];            // EXPECT: error: the size of an array is negative (-1)
void nothing[4];        // EXPECT: error: an array of void
char big[70000u];       // EXPECT: error: an object is at most 65,535 bytes in cc816
int main(void) { return 0; }

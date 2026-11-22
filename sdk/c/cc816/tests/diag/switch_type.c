/* switch on a float or a pointer */
int main(void)
{
    float f = 1.0f;
    switch (f) {        // EXPECT: error: switch on a value that is not an integer (float)
    case 1: return 1;
    }
    return 0;
}

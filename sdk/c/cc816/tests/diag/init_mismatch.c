/* initialisers of the wrong kind */
struct p { int x, y; };
int main(void)
{
    struct p a = {1, 2};
    int arr[2] = 5;     // EXPECT: error: an array is initialised with a list in braces ({...}) or a string, not with int
    float f = &a;       // EXPECT: error: incompatible types when initialising float with struct p *
    return arr[0] + (int)f;
}

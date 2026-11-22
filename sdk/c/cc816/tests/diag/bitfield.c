/* bit-fields: too wide for int (16 bits here), negative, of a float */
struct flags {
    int big : 20;           // EXPECT: error: width of bit-field 'big' (20 bits) exceeds its type (int, 16 bits) (int is 16 bits in cc816: declare it long
    unsigned neg : -1;      // EXPECT: error: negative width in bit-field 'neg'
    float f : 3;            // EXPECT: error: bit-field 'f' has a type that is not an integer (float)
    long ok : 20;
};
int main(void) { return 0; }

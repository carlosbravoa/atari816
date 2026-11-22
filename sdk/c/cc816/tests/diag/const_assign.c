/* writing to what is const */
int main(void)
{
    const int lives = 3;
    const char *msg = "hi";
    lives = 4;          // EXPECT: error: assignment of the read-only variable 'lives' (it is const)
    lives++;            // EXPECT: error: increment of the read-only variable 'lives'
    *msg = 'H';         // EXPECT: error: assignment of a read-only location (its type is const char)
    return 0;
}

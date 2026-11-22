/* calling a function that is not declared */
int main(void)
{
    return draw_sprite(3);  // EXPECT: warning: implicit declaration of the function 'draw_sprite' (include its header, or declare it
}
int draw_sprite(int n) { return n; }

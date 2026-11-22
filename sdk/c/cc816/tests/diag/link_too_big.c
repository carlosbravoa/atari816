/* a program too big for its code bank: hcc says by how much, and in which segments */
// HCC: -o X.PRG
// EXPECT-HCC: does not fit in its code bank
// EXPECT-HCC: bss
static unsigned char level[30000], tiles[30000];
int main(void) { level[1] = 1; tiles[2] = 2; return level[1] + tiles[2]; }

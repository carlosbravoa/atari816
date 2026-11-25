/* hcc --set outside --check-calls: refused (a build gives each file's options in its own
 * hcc -c) */
// HCC: --set -DX -o X.PRG
// EXPECT-HCC: --set is for --check-calls
int main(void) { return 0; }

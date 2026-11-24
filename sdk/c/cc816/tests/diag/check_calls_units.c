/* hcc --check-calls a.c b.c: the files of a program read together (nothing built): a call
 * without a prototype in one file, or a prototype, that disagrees with the definition in
 * another (Civilization's picture_target(0): 2 bytes pushed where a far pointer's 4 are
 * read; a prototype in one header that says int for a pointer). Exit 1 when one is found.
 * A static function of the other file is not this file's (hidden). (make check also runs
 * it with $HZ_DATA=far, where the far pointer is spelt "char *": the EXPECTs stop before) */
// HCC: --check-calls check_calls/units_b.c
// EXPECT-HCC: check_calls_units.c:17:12: warning: the call of 'picture_target' has no prototype: argument 1 is pushed as an int (2 bytes), but the definition (units_b.c:2) reads a char
// EXPECT-HCC: check_calls_units.c:17:49: warning: the call of 'other' has no prototype: argument 1 is pushed as an int (2 bytes), but the definition (units_b.c:5) reads a long (4 bytes)
// EXPECT-HCC: check_calls_units.c:13:6: warning: the prototype of 'blit' says parameter 1 is int (2 bytes), but its definition (units_b.c:3) reads char
// EXPECT-HCC: hcc --check-calls: 2 file(s), 3 call(s) or prototype(s) that disagree with a definition
int picture_target();
void blit(int x, int y);
long sum(int a, int b);
int fine();
int main(void) { blit(1, 2);
    return picture_target(0) + (int)sum(1, 2) + other(3) + fine(4) + hidden(5); }

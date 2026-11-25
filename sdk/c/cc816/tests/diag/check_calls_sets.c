/* hcc --check-calls --set: files of one program read with different -D options (and -U,
 * -I, -include): the options before the first --set are every file's, those after a --set
 * the files' after it, up to the next --set. Each file here refuses the other's -D, so the
 * two can only be read together this way; the calls between them are still compared. */
// HCC: --check-calls -DBOTH --set -DSIDE_B check_calls/sets_b.c --set -DSIDE_A
// EXPECT-HCC: check_calls_sets.c:16:17: warning: the call of 'scaled' has no prototype: its result is read as a long (4 bytes), but the definition (sets_b.c:6) returns an int (2 bytes)
// EXPECT-HCC: check_calls_sets.c:17:6: warning: the call of 'shift_by' has no prototype: argument 1 is pushed as an int (2 bytes), but the definition (sets_b.c:7) reads a long (4 bytes)
// EXPECT-HCC: hcc --check-calls: 2 file(s), 2 call(s) or prototype(s) that disagree with a definition
#if !defined(BOTH) || !defined(SIDE_A) || defined(SIDE_B)
#error "check_calls_sets.c: not its own set of -D options"
#endif
long scaled();
void shift_by();
int main(void)
{
    return (int)scaled(3) +
    (shift_by(1), 0);
}

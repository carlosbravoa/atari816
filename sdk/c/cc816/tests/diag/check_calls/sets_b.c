/* the other file of check_calls_sets.c (hcc --check-calls --set): read with -DBOTH and
   -DSIDE_B, not -DSIDE_A */
#if !defined(BOTH) || !defined(SIDE_B) || defined(SIDE_A)
#error "sets_b.c: not its own set of -D options"
#endif
int scaled(int n) { return n * 2; }
void shift_by(long n) { (void)n; }

/* the other file of check_calls_ret.c (hcc --check-calls): the definitions */
static char buf[4];
char __far *far_text(void) { return buf; }
long big_count(void) { return 70000L; }
void no_value(void) { buf[0] = 1; }
float half_value(void) { return 1.5f; }
int small_int(void) { return 1; }
char __far *far_slot(int n) { return buf + n; }
char __far *undeclared_far(void) { return buf + 1; }
int fine_int(void) { return 2; }
char *fine_ptr(void) { return buf; }
int may_end(int n) { if (n) return 1; }
int may_end_unused(int n) { if (n) return 1; }

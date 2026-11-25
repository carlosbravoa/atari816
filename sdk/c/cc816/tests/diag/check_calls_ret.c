/* hcc --check-calls: the results too. A call without a prototype whose value is used, or a
 * prototype, that takes the result as another type than the definition in the other file
 * returns: a far pointer or a long (4 bytes) read as an int (2), an int read as a long, a
 * float read as a long (the bits), the value of a void function, or of one that can reach
 * its end without a return (may_end; may_end_unused's value is never used). A call that
 * drops the value reads nothing: no warning; an int and a near pointer (2 bytes each)
 * agree. (make check also runs it with $HZ_DATA=far, where the far pointer is spelt
 * "char *": the EXPECTs stop before) */
// HCC: --check-calls check_calls/ret_b.c
// EXPECT-HCC: check_calls_ret.c:27:9: warning: the call of 'far_text' has no prototype: its result is read as an int (2 bytes), but the definition (ret_b.c:3) returns a char
// EXPECT-HCC: check_calls_ret.c:28:10: warning: the call of 'big_count' has no prototype: its result is read as an int (2 bytes), but the definition (ret_b.c:4) returns a long (4 bytes): the upper half is lost
// EXPECT-HCC: check_calls_ret.c:29:10: warning: the call of 'no_value' has no prototype: its result is read as an int (2 bytes), but the definition (ret_b.c:5) returns nothing (void)
// EXPECT-HCC: check_calls_ret.c:30:15: warning: the call of 'half_value' has no prototype: its result is read as a long (4 bytes), but the definition (ret_b.c:6) returns a float (4 bytes): the bits are not converted
// EXPECT-HCC: check_calls_ret.c:31:15: warning: the call of 'small_int' has no prototype: its result is read as a long (4 bytes), but the definition (ret_b.c:7) returns an int (2 bytes): the upper half read is garbage
// EXPECT-HCC: check_calls_ret.c:32:10: warning: the call of 'undeclared_far' has no prototype: its result is read as an int (2 bytes), but the definition (ret_b.c:9) returns a char
// EXPECT-HCC: check_calls_ret.c:21:5: warning: the prototype of 'far_slot' says it returns int (2 bytes), but its definition (ret_b.c:8) returns a char
// EXPECT-HCC: ret_b.c:12:39: warning: the function 'may_end' can reach its end without a return, and a caller uses its value (check_calls_ret.c:38)
// EXPECT-HCC: hcc --check-calls: 2 file(s), 8 call(s) or prototype(s) that disagree with a definition
extern int far_text(), big_count(), no_value(), fine_int();
extern long half_value(), small_int();
int far_slot(int);
extern char *fine_ptr();
int may_end(int), may_end_unused(int);
int main(void)
{
    int a;
    a = far_text();
    a += big_count();
    a += no_value();
    a += (int)half_value();
    a += (int)small_int();
    a += undeclared_far();
    a += far_slot(1) + fine_int() + (fine_ptr() != 0);
    no_value();
    big_count();
    (void)far_text();
    may_end_unused(0);
    a += may_end(1);
    return a;
}

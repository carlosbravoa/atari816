/* -D and -U from the command line (FLAGS), and -include */
// FLAGS: -DLEVEL=2 -UNDEBUG -DNDEBUG -include diag_inc.h
#if LEVEL != 2 || !defined(NDEBUG) || INCLUDED != 1
#error "the command line's macros"
#endif
int main(void) { return 0; }

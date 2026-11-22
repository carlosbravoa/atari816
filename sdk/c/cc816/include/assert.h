/* assert.h - cc816 (Horizon C SDK): a failed assert prints the expression, the file and
 * the line on stderr and ends the program (abort: exit code 3). */
#undef assert
#ifdef NDEBUG
#define assert(e) ((void)0)
#else
void __hz_assert(const char *expr, const char *file, unsigned line);
#define assert(e) ((e) ? (void)0 : __hz_assert(#e, __FILE__, __LINE__))
#endif

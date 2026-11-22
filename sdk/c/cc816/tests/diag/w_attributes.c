/* GNU attributes: the common ones are read without a word; one cc816 cannot honour is
   said */
struct __attribute__((packed)) hdr { char a; int b; };
static int unused_fn(void) __attribute__((unused));
static int unused_fn(void) { return 0; }
__attribute__((noreturn)) void die(int code);
void stop(int code) __attribute__((__noreturn__));
int buf[4] __attribute__((aligned(16)));    // EXPECT: warning: the attribute 'aligned' is ignored: cc816 does not align objects
__attribute__((always_inline)) static __inline__ int sq(int x) { return x * x; }
int f(int x) { if (x) return sq(x); die(1); }
int g(int x) { if (x) return 1; stop(2); }
int h(int x) { if (x) return 1; }   // EXPECT: warning: control reaches the end of the non-void function 'h'
int main(void) { return f(1) + g(1) + h(1) + unused_fn() + (int)sizeof(struct hdr) - 4; }

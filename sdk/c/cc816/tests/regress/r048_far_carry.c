/* r048_far_carry.c - the default far pointer arithmetic at a bank's edges: a pointer's
 * value is its 24-bit address (far_edges.h; r047_far_wrap.c is the same with -ffar-wrap).
 * LEVELS: 0 1 2 */
// FLAGS: -Wno-overflow
#include "far_edges.h"

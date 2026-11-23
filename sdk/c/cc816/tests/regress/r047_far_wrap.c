/* r047_far_wrap.c - -ffar-wrap: far pointer arithmetic on the offset alone, at a bank's
 * edges (far_edges.h; r048_far_carry.c is the same without the option). LEVELS: 0 1 2 */
// FLAGS: -ffar-wrap -Wno-overflow
#include "far_edges.h"

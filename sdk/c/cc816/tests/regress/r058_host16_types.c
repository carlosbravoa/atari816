/* r058_host16_types.c - the test of sdk/c/tools/host16.py (the PC build with the Atari816's
 * integer sizes) run with cc816 too: what it checks (int 16 bits, long 32, an unsigned
 * before a macro type, structures packed, double the 32-bit float, plain char unsigned,
 * 16-bit wrapping) must hold here, or the PC twin would be checked against wrong answers.
 * Prints "host16: 0 failures" and returns 0. */
#include "../../../tests/host16/h16test.c"

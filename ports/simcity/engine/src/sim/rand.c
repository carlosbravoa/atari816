/*-
 * Copyright (c) 1990 The Regents of the University of California.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *	This product includes software developed by the University of
 *	California, Berkeley and its contributors.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include "sim.h"

#if !defined(MICROPOLIS_PORT)
#include <sys/types.h>
#include <stdlib.h>
#endif

#define SIM_RAND_MAX 0xffff

#if defined(MICROPOLIS_PORT)
/* (global: the Atari816's sim_rand is in assembly, ports/simcity/src/fast.s, with a
   table of the multiplier's byte products, port_rand_tab) */
unsigned QUAD port_rand_next = 1;
unsigned QUAD port_rand_tab[256];
#define next port_rand_next

void
port_rand_init(void)
{
	unsigned i;
	for (i = 0; i < 256; i++)
		port_rand_tab[i] = (unsigned QUAD)i * 1103515245UL;
}
#else
static unsigned QUAD next = 1;
#endif

#if defined(MICROPOLIS_PORT)
/* 16-bit int: SIM_RAND_MAX + 1 is 0 (0xffff is an unsigned int, + 1 wraps), the
 * modulus a division by zero; and the result, 0 to 65,535, does not fit an int. The
 * same numbers, in unsigned QUAD arithmetic and an unsigned result (Rand16, s_sim.c) */
#if !defined(__CC816__)
unsigned
sim_rand(void)
{
	next = next * 1103515245UL + 12345;
	return (unsigned)((next % ((SIM_RAND_MAX + 1UL) <<8)) >>8);
}
#endif

void
sim_srand(unsigned QUAD seed)
{
	next = seed;
}

/* the generator's state, for the port's checksum of the simulation */
unsigned QUAD
sim_rand_state(void)
{
	return next;
}
#else
int
sim_rand()
{
	next = next * 1103515245 + 12345;
	return ((next % ((SIM_RAND_MAX + 1) <<8)) >>8);
}

void
sim_srand(seed)
u_int seed;
{
	next = seed;
}
#endif

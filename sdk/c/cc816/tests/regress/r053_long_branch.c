/* r053_long_branch.c - a function of more than 32 KB of code: a loop whose body is
 * about 45 KB (3,000 calls). Its branches back to the top and over the body (the
 * continue) were relaxed to BRL, which reaches 32 KB: ca65 refused them ("Range error").
 * Now a BRL out of reach is a JMP (the same size; a function never crosses its bank).
 * (Not at -O0: its 72 KB of code do not fit the small model's bank; the relaxation is the
 * same at every level.) */
static unsigned g(unsigned x) { return (x * 7) ^ 0x1234; }

#define S(k) s += g(i + (k));
#define S10(k) S(k) S(k + 1) S(k + 2) S(k + 3) S(k + 4) S(k + 5) S(k + 6) S(k + 7) \
    S(k + 8) S(k + 9)
#define S100(k) S10(k) S10(k + 10) S10(k + 20) S10(k + 30) S10(k + 40) S10(k + 50) \
    S10(k + 60) S10(k + 70) S10(k + 80) S10(k + 90)
#define S1000(k) S100(k) S100(k + 100) S100(k + 200) S100(k + 300) S100(k + 400) \
    S100(k + 500) S100(k + 600) S100(k + 700) S100(k + 800) S100(k + 900)

static unsigned huge(unsigned n, unsigned skip)
{
    unsigned i, s = 0;
    for (i = 0; i < n; i++) {
        if (i == skip) {
            s += 1000;
            continue;
        }
        S1000(0) S1000(1000) S1000(2000)
    }
    return s;
}

int main(void)
{
    return huge(4, 2) == 58748u ? 0 : 1;
}

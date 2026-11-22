/* r001_relax.c - bug 1: a switch whose compare-and-branch chain is far longer than a
 * branch reaches. cc816's branch relaxation gave up after 20 branches: ca65 then refused
 * the assembly (range error). Fixed: every out-of-range branch is relaxed, pass after
 * pass. */
static unsigned f(unsigned x)
{
    unsigned r = 0, s = 0;
    switch (x) {
    case 0: r = x * 1 + 0; if (r & 1) r ^= 0; s += r; break;
    case 3: r = x * 2 + 1; if (r & 1) r ^= 7; s += r; break;
    case 6: r = x * 3 + 2; if (r & 1) r ^= 14; s += r; break;
    case 9: r = x * 4 + 3; if (r & 1) r ^= 21; s += r; break;
    case 12: r = x * 5 + 4; if (r & 1) r ^= 28; s += r; break;
    case 15: r = x * 6 + 5; if (r & 1) r ^= 35; s += r; break;
    case 18: r = x * 7 + 6; if (r & 1) r ^= 42; s += r; break;
    case 21: r = x * 8 + 7; if (r & 1) r ^= 49; s += r; break;
    case 24: r = x * 9 + 8; if (r & 1) r ^= 56; s += r; break;
    case 27: r = x * 10 + 9; if (r & 1) r ^= 63; s += r; break;
    case 30: r = x * 11 + 10; if (r & 1) r ^= 70; s += r; break;
    case 33: r = x * 12 + 11; if (r & 1) r ^= 77; s += r; break;
    case 36: r = x * 13 + 12; if (r & 1) r ^= 84; s += r; break;
    case 39: r = x * 14 + 13; if (r & 1) r ^= 91; s += r; break;
    case 42: r = x * 15 + 14; if (r & 1) r ^= 98; s += r; break;
    case 45: r = x * 16 + 15; if (r & 1) r ^= 105; s += r; break;
    case 48: r = x * 17 + 16; if (r & 1) r ^= 112; s += r; break;
    case 51: r = x * 18 + 17; if (r & 1) r ^= 119; s += r; break;
    case 54: r = x * 19 + 18; if (r & 1) r ^= 126; s += r; break;
    case 57: r = x * 20 + 19; if (r & 1) r ^= 133; s += r; break;
    case 60: r = x * 21 + 20; if (r & 1) r ^= 140; s += r; break;
    case 63: r = x * 22 + 21; if (r & 1) r ^= 147; s += r; break;
    case 66: r = x * 23 + 22; if (r & 1) r ^= 154; s += r; break;
    case 69: r = x * 24 + 23; if (r & 1) r ^= 161; s += r; break;
    case 72: r = x * 25 + 24; if (r & 1) r ^= 168; s += r; break;
    case 75: r = x * 26 + 25; if (r & 1) r ^= 175; s += r; break;
    case 78: r = x * 27 + 26; if (r & 1) r ^= 182; s += r; break;
    case 81: r = x * 28 + 27; if (r & 1) r ^= 189; s += r; break;
    case 84: r = x * 29 + 28; if (r & 1) r ^= 196; s += r; break;
    case 87: r = x * 30 + 29; if (r & 1) r ^= 203; s += r; break;
    case 90: r = x * 31 + 30; if (r & 1) r ^= 210; s += r; break;
    case 93: r = x * 32 + 31; if (r & 1) r ^= 217; s += r; break;
    case 96: r = x * 33 + 32; if (r & 1) r ^= 224; s += r; break;
    case 99: r = x * 34 + 33; if (r & 1) r ^= 231; s += r; break;
    case 102: r = x * 35 + 34; if (r & 1) r ^= 238; s += r; break;
    case 105: r = x * 36 + 35; if (r & 1) r ^= 245; s += r; break;
    case 108: r = x * 37 + 36; if (r & 1) r ^= 252; s += r; break;
    case 111: r = x * 38 + 37; if (r & 1) r ^= 259; s += r; break;
    case 114: r = x * 39 + 38; if (r & 1) r ^= 266; s += r; break;
    case 117: r = x * 40 + 39; if (r & 1) r ^= 273; s += r; break;
    default: s = 9999; break;
    }
    return s;
}

int main(void)
{
    unsigned k, t = 0;
    for (k = 0; k < 130; k++)
        t += f(k);
    return t == 47226u ? 0 : 1;
}

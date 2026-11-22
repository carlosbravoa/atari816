/* r027_strings_h.c - POSIX's <strings.h> was missing ("cannot find the include file
 * strings.h"): programs written for Unix include it for strcasecmp and strncasecmp (the C
 * library had them, declared in string.h only). Found by the Digger port (ini.c). */
#include <strings.h>

int main(void)
{
    if (strcasecmp("Digger", "DIGGER") != 0)
        return 1;
    if (strncasecmp("SoundOn", "soundoff", 6) != 0)
        return 2;
    if (strcasecmp("a", "B") >= 0)
        return 3;
    return 0;
}

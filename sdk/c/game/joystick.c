/* joystick.c - cc65's joystick API on Horizon's joystick call (both DB9 ports). */
#include <horizon.h>
#include <joystick.h>

const unsigned char joy_static_stddrv[1] = { 0 };

unsigned char joy_install(const void *driver)
{
    return JOY_ERR_OK;
}

unsigned char joy_load_driver(const char *driver)
{
    return JOY_ERR_OK;
}

unsigned char joy_uninstall(void)
{
    return JOY_ERR_OK;
}

unsigned char joy_unload(void)
{
    return JOY_ERR_OK;
}

unsigned char joy_count(void)
{
    return 2;
}

unsigned char joy_read(unsigned char joy)
{
    unsigned d = hz_joystick(), t = hz_x;
    if (hz_errno)
        return 0;                       /* (an older Horizon: no joystick call) */
    if (joy == JOY_1)
        return (unsigned char)((d & 15) | ((t & 1) ? JOY_BTN_1_MASK : 0));
    return (unsigned char)(((d >> 4) & 15) | ((t & 2) ? JOY_BTN_1_MASK : 0));
}

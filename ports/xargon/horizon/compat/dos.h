/* dos.h - the parts of Turbo C's dos.h Xargon uses, on Horizon (hz_dos.c). The I/O ports
 * are the ones upstream's files touch, emulated: the VGA's DAC (palette) and status
 * (vertical retrace) and CRTC start address (the page shown), the game port (joystick). */
#ifndef XDOS_H
#define XDOS_H
void delay(unsigned ms);
void enable(void);
void disable(void);
unsigned char inportb(unsigned port);
void outportb(unsigned port, unsigned char value);
void outport(unsigned port, unsigned value);
unsigned inport(unsigned port);
void sound(unsigned hz);
void nosound(void);
struct REGPACK {
    unsigned r_ax, r_bx, r_cx, r_dx, r_bp, r_si, r_di, r_ds, r_es, r_flags;
};
void intr(int n, struct REGPACK *r);
#endif

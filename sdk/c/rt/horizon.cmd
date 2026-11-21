/* horizon.cmd - vlink linker script, LARGE model (hcc's default).
 *
 * Everything the program has goes into its code bank, from $0100: the text (startup
 * first), constant data, initialised data, then bss. The heap is the rest of the code
 * bank, from the end of bss to $FFF0. The stack is the task's window (bank 0), from just
 * below the argument string down to $0100 (about 32 KB); the direct page is window $0000.
 *
 * Direct-page sections of libraries (the float library's 14 bytes) go to $F0-$FF.
 *
 * hcc links the program three times (BASE = $000000, $5A0000, $A50000) as raw binaries
 * and tools/mko65.py turns the differences into the o65 relocations Horizon's loader
 * applies. The region is far larger than a bank on purpose: mko65 checks the sizes and
 * says in plain words what does not fit (vlink's own message would not).
 */
BASE =? 0;
HZ_PAINT =? 0;

MEMORY
{
  zp:   org = 0xF0, len = 0x10
  main: org = BASE + 0x100, len = 0x100000
}
SECTIONS
{
  zpage (NOLOAD) : { *(zpage) *(zp1) *(zp2) } >zp
  .text : { *(*_text.blob) *(*_text.startup) *(?????????_text.*) *(text*) *(.text*) *(?????????_rodata.*) *(rodata*) *(.rodata*) *(.dtors) *(.ctors) } >main
  .data : { *(?????????_data.*) *(data*) *(.data*) } >main
  .bss (NOLOAD) : { *(?????????_bss.*) *(bss*) *(.bss*) } >main
  __DBR_init = ADDR(.text);
  ___heap = ADDR(.bss) + SIZEOF(.bss);
  ___heapend = BASE + 0xFFF0;
  ___hz_stklo = 0x100;
  ___hz_paint = HZ_PAINT;
}

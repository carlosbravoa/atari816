/* horizon.cmd - vlink linker script for a vbcc 65816 program under Horizon.
 *
 * Linked as a raw binary at BASE + $0100 (BASE = bank << 16): text (startup first),
 * rodata, data, then bss. hz/mko65.py links it at two banks, takes the bytes that
 * differ as bank-byte (SEG) relocations and writes the o65 file the loader wants.
 * The loader always puts text at offset $0100 of the code bank, so offsets never move:
 * only bank bytes need relocating. vbcc's direct-page registers are absolute (startup.s).
 */
BASE =? 0;

MEMORY
{
  main: org = BASE + 0x100, len = 0xff00
}
SECTIONS
{
  .text : { *(*_text.blob) *(*_text.startup) *(*text*) *(*rodata*) *(.dtors) *(.ctors) } >main
  .data : { *(*data*) } >main
  .bss (NOLOAD) : { *(*bss*) } >main
  __DBR_init = ADDR(.text);
  ___hz_imgend = ADDR(.bss);
  ___heap = ADDR(.bss) + SIZEOF(.bss);
  ___heapend = BASE + 0xFF00;
}

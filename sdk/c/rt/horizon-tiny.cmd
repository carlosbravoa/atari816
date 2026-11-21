/* horizon-tiny.cmd - vlink linker script, TINY model (hcc --model tiny, vbcc -mtiny).
 *
 * vbcc's tiny model needs every data object and the stack in one bank (the data bank,
 * DBR), and the 65816's stack is always in bank 0: so all data lives in the task's
 * 32 KB window. The code goes into the code bank (linked at BASE + $0100 and relocated
 * by tools/mko65.py like the large model); constant and initialised data are linked for
 * the window at $0100 and loaded after the code, and the startup (rt/crt0.s) copies them
 * there. bss follows them, then the heap up to WEND; the stack has WEND up to the
 * argument string ($7F7F at the lowest). The window is at the same addresses in every
 * task, so data addresses need no relocation.
 *
 * Direct-page sections of libraries (the float library's 14 bytes) go to $F0-$FF.
 *
 * WEND (hcc --stack N sets it to $7F80 - N, rounded down to 16): $7000 by default, so
 * data + bss + heap get 28,416 bytes and the stack at least 3,968.
 */
BASE =? 0;
WEND =? 0x7000;
HZ_PAINT =? 0;

MEMORY
{
  zp:   org = 0xF0, len = 0x10
  main: org = BASE + 0x100, len = 0x100000
  win:  org = 0x100, len = 0x100000
}
SECTIONS
{
  zpage (NOLOAD) : { *(zpage) *(zp1) *(zp2) } >zp
  .text : { *(*_text.blob) *(*_text.startup) *(?????????_text.*) *(text*) *(.text*) *(.dtors) *(.ctors) } >main
  .wdata : { *(?????????_rodata.*) *(rodata*) *(.rodata*) *(?????????_data.*) *(data*) *(.data*) } >win AT>main
  .wbss (NOLOAD) : { *(?????????_bss.*) *(bss*) *(.bss*) } >win
  __DBR_init = 0;
  ___WDS = ADDR(.wdata);
  ___WDL = SIZEOF(.wdata);
  ___WDC = ADDR(.text) + SIZEOF(.text);
  ___WBS = ADDR(.wbss);
  ___WBE = ADDR(.wbss) + SIZEOF(.wbss);
  ___heap = ADDR(.wbss) + SIZEOF(.wbss);
  ___heapend = WEND;
  ___hz_stklo = WEND;
  ___hz_paint = HZ_PAINT;
}

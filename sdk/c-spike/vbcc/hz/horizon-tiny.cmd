/* horizon-tiny.cmd - vlink linker script for vbcc's tiny data model (-mtiny) under Horizon.
 *
 * vbcc's tiny model needs the stack and all data in the same bank (DBR), and the 65816
 * stack is always in bank 0. So: code in the code bank (linked at BASE + $0100 like
 * horizon.cmd, relocated by hz/mko65.py), all data (rodata, data, bss) in the task's
 * window in bank 0 at fixed addresses $0100..WEND-1 (above the direct page, below the
 * stack). The window is at the same addresses in every task, so data addresses need no
 * relocation. startup-tiny.s copies the data image from the code bank to the window,
 * clears bss and sets DBR = 0. The stack (S starts just below the argument string, at
 * most $7FFE) has WEND..S. A larger WEND gives more data and less stack.
 */
BASE =? 0;
WEND =? 0x7000;

MEMORY
{
  main: org = BASE + 0x100, len = 0xff00
  win:  org = 0x100, len = WEND - 0x100
}
SECTIONS
{
  .text : { *(*_text.startup) *(*text*) *(.dtors) *(.ctors) } >main
  .wdata : { *(*rodata*) *(*data*) } >win AT>main
  .wbss (NOLOAD) : { *(*bss*) } >win
  __DBR_init = 0;
  ___WDS = ADDR(.wdata);
  ___WDL = SIZEOF(.wdata);
  ___WDC = ADDR(.text) + SIZEOF(.text);
  ___WBS = ADDR(.wbss);
  ___WBE = ADDR(.wbss) + SIZEOF(.wbss);
  ___heap = ADDR(.wbss) + SIZEOF(.wbss);
  ___heapend = WEND;
}

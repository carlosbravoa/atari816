/* "#define NAME= value": gcc's warning, and the macro is defined (r032 runs it) */
#define scan_f1= 0x3B           // EXPECT: warning: missing whitespace after the macro name
int x scan_f1;
int main(void) { return x != 0x3B; }

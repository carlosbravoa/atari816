/* pragmas: Watcom's inline code and unknown ones are not ignored silently (ports/xcom,
 * PORTING-NOTES.md item 5: a function defined only by its #pragma aux became an
 * undefined symbol at the link); pack(1) and the harmless ones say nothing */
#pragma aux cpu_below_286 = "pushf" "pop ax" value [ax]
#pragma aux rl_imul parm [ax] [dx] value [ax]
#pragma pack(1)
struct s { char a; int b; };
#pragma pack()
#pragma pack(push, 1)
#pragma pack(pop)
#pragma pack(2)
#pragma once
#pragma GCC diagnostic ignored "-Wfoo"
#pragma warning 102 9
#pragma frobnicate
int main(void)
{
    return sizeof(struct s) - 3;
}
// EXPECT: 4: warning: #pragma aux cpu_below_286 = ...: Watcom inline code is ignored: 'cpu_below_286' needs a C body
// EXPECT: 5: warning: #pragma aux rl_imul: Watcom's calling convention for it is ignored
// EXPECT: 11: warning: #pragma pack(2): cc816 packs every structure (no padding)
// EXPECT: 15: warning: #pragma frobnicate: unknown, ignored

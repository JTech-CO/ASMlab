; Development-only comparison backend. Never used by the normal release.
%include "include/abi.inc"
extern memcpy, memmove, memset, memcmp, strlen, strnlen, strcmp
section .text
%macro BRIDGE 2
global %1
%1:
    jmp %2 wrt ..plt
%endmacro
BRIDGE rt_memcpy, memcpy
BRIDGE rt_memmove, memmove
BRIDGE rt_memset, memset
BRIDGE rt_memcmp, memcmp
BRIDGE rt_strlen, strlen
BRIDGE rt_strnlen, strnlen
BRIDGE rt_strcmp, strcmp
section .note.GNU-stack noalloc noexec nowrite progbits

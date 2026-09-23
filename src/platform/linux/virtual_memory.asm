; Linux x86-64 VM boundary. No MAP_NORESERVE, executable pages or libc.
%include "include/abi.inc"
section .text
global rt_sys_mmap, rt_sys_munmap, rt_memory_abort
rt_sys_mmap:
    mov r10, rcx
    mov eax, 9
    syscall
    ret
rt_sys_munmap:
    mov eax, 11
    syscall
    ret
rt_memory_abort:
    mov edi, 2
    mov eax, 231
    syscall
    ud2
section .note.GNU-stack noalloc noexec nowrite progbits

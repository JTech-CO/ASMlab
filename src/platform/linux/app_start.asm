; Full L3-Core process entry. No CRT, C ABI main wrapper, libc or dynamic loader.
%include "include/abi.inc"
extern main, rt_host_init, rt_host_finish, rt_sys_exit
section .rodata
initial_mxcsr: dd 0x1f80
section .text
global _start
_start:
    xor ebp, ebp
    cld
    mov r12, [rsp]
    lea r13, [rsp+8]
    and rsp, -16
    ldmxcsr [initial_mxcsr]
    call rt_host_init
    mov rdi, r12
    mov rsi, r13
    call main
    mov edi, eax
    call rt_host_finish
    mov edi, eax
    jmp rt_sys_exit
section .note.GNU-stack noalloc noexec nowrite progbits

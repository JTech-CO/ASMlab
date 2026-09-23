; Used ONLY by the standalone foundation smoke executable.
; The full L3 application has its own entry in app_start.asm.
%include "include/abi.inc"
extern rt_program_main, rt_sys_exit
section .text
global _start
_start:
    xor ebp, ebp
    cld
    mov rdi, [rsp]             ; argc
    lea rsi, [rsp+8]           ; argv
    lea rdx, [rsi+rdi*8+8]     ; envp
    and rsp, -16
    call rt_program_main
    mov edi, eax
    jmp rt_sys_exit
section .note.GNU-stack noalloc noexec nowrite progbits

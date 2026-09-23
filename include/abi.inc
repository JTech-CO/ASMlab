; Common SysV AMD64 project ABI. No storage or runtime imports.
%ifndef ASMLAB_ABI_INC
%define ASMLAB_ABI_INC 1
bits 64
default rel
%macro FRAME 1
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, %1 + 8
%endmacro
%macro DONE 0
    lea rsp, [rbp-40]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
%endmacro

%endif

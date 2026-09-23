; Test-only native probe. fn(args[0..5]); records RAX,RDX,RFLAGS,MXCSR.
; Return mask: bits0..5=callee-saved GPR, bit6=DF, bit7=MXCSR mutation.
; Integer/memory/I/O primitives promise not to touch SIMD state.
%include "include/abi.inc"
section .text
global rt_test_invoke
rt_test_invoke:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 88
    mov [rsp], rdi
    mov [rsp+8], rsi
    mov [rsp+16], rdx
    stmxcsr [rsp+24]
    mov dword [rsp+28], 0x5fa0
    ldmxcsr [rsp+28]
    cld
    mov rbx, 0x0123456789abcdef
    mov rbp, 0x13579bdf2468ace0
    mov r12, 0x1122334455667788
    mov r13, 0x99aabbccddeeff00
    mov r14, 0xfedcba9876543210
    mov r15, 0x8877665544332211
    mov rax, [rsp+8]
    mov rdi, [rax]
    mov rsi, [rax+8]
    mov rdx, [rax+16]
    mov rcx, [rax+24]
    mov r8, [rax+32]
    mov r9, [rax+40]
    call [rsp]
    mov [rsp+32], rax
    mov [rsp+40], rdx
    pushfq
    pop rax
    mov [rsp+48], rax
    stmxcsr [rsp+56]
    xor eax, eax
%macro SENTINEL 3
    mov r10, %2
    cmp %1, r10
    je %%ok
    or eax, %3
%%ok:
%endmacro
    SENTINEL rbx, 0x0123456789abcdef, 1
    SENTINEL rbp, 0x13579bdf2468ace0, 2
    SENTINEL r12, 0x1122334455667788, 4
    SENTINEL r13, 0x99aabbccddeeff00, 8
    SENTINEL r14, 0xfedcba9876543210, 16
    SENTINEL r15, 0x8877665544332211, 32
    test qword [rsp+48], 0x400
    jz .df_ok
    or eax, 64
.df_ok:
    cmp dword [rsp+56], 0x5fa0
    je .mx_ok
    or eax, 128
.mx_ok:
    mov r10, [rsp+16]
    mov r11, [rsp+32]
    mov [r10], r11
    mov r11, [rsp+40]
    mov [r10+8], r11
    mov r11, [rsp+48]
    mov [r10+16], r11
    mov r11d, [rsp+56]
    mov [r10+24], r11
    ldmxcsr [rsp+24]
    cld
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
; Set/retrieve MXCSR for decimal boundary fixtures; never part of app runtime.
global rt_test_mxcsr_set, rt_test_mxcsr_get
rt_test_mxcsr_set:
    sub rsp, 8
    mov [rsp], edi
    ldmxcsr [rsp]
    add rsp, 8
    ret
rt_test_mxcsr_get:
    sub rsp, 8
    stmxcsr [rsp]
    mov eax, [rsp]
    add rsp, 8
    ret
section .note.GNU-stack noalloc noexec nowrite progbits

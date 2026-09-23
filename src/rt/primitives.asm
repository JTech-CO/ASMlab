; Original scalar reference primitives. SysV AMD64; DF=0 on entry/exit.
; No libc, CPU feature dispatch, or speculative reads beyond supplied bounds.
%include "include/abi.inc"
section .text
global rt_memcpy, rt_memmove, rt_memset, rt_memcmp
global rt_strlen, rt_strnlen, rt_strcmp
; (dst, src, n) -> original dst. Non-overlap required for memcpy.
rt_memcpy:
    mov rax, rdi
    mov rcx, rdx
    cld
    rep movsb
    ret
rt_memmove:
    mov rax, rdi
    test rdx, rdx
    jz .done
    cmp rdi, rsi
    jbe .forward
    mov rcx, rdi
    sub rcx, rsi
    cmp rcx, rdx
    jae .forward
    ; Overlap: copy backwards WITHOUT setting DF, including during signals.
.back:
    dec rdx
    mov cl, [rsi+rdx]
    mov [rdi+rdx], cl
    test rdx, rdx
    jnz .back
.done:
    ret
.forward:
    mov rcx, rdx
    cld
    rep movsb
    ret
; (dst, byte, n) -> original dst; only the low eight bits are used.
rt_memset:
    mov r8, rdi
    mov eax, esi
    mov rcx, rdx
    cld
    rep stosb
    mov rax, r8
    ret
; (a,b,n) -> int32 with sign of first different UNSIGNED byte, or zero.
rt_memcmp:
    xor ecx, ecx
.loop:
    cmp rcx, rdx
    jae .same
    movzx eax, byte [rdi+rcx]
    movzx r8d, byte [rsi+rcx]
    sub eax, r8d
    jnz .done
    inc rcx
    jmp .loop
.same:
    xor eax, eax
.done:
    ret
; strlen is for valid NUL-terminated internal strings, not untrusted spans.
rt_strlen:
    xor eax, eax
.loop:
    cmp byte [rdi+rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret
; (str,max) -> min(strlen,max); max==0 performs NO read.
rt_strnlen:
    xor eax, eax
.loop:
    cmp rax, rsi
    jae .done
    cmp byte [rdi+rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret
rt_strcmp:
    xor ecx, ecx
.loop:
    movzx eax, byte [rdi+rcx]
    movzx edx, byte [rsi+rcx]
    cmp eax, edx
    jne .diff
    test eax, eax
    jz .done
    inc rcx
    jmp .loop
.diff:
    sub eax, edx
.done:
    ret
section .note.GNU-stack noalloc noexec nowrite progbits

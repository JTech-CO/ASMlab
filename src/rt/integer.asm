; Bounded integer conversion only. No floating-point decimal converter here.
%include "include/abi.inc"
%include "include/rt/foundation.inc"
section .text
global rt_format_u64, rt_format_i64, rt_format_hex64
; (dst, capacity including NUL, value) -> length, or -ENOSPC.
; On error the destination is unchanged. No allocation; no outside calls.
rt_format_u64:
    xor r11d, r11d
    jmp format_decimal
rt_format_i64:
    mov r11, rdx
    shr r11, 63
    test r11, r11
    jz format_decimal
    neg rdx                 ; INT64_MIN magnitude is valid unsigned 2^63.
format_decimal:
    sub rsp, 40
    mov r8, rdi
    mov r9, rsi
    lea rsi, [rsp+32]
    mov rax, rdx
    mov r10d, 10
.digit:
    xor edx, edx
    div r10
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .digit
    test r11, r11
    jz .length
    dec rsi
    mov byte [rsi], '-'
.length:
    lea rax, [rsp+32]
    sub rax, rsi
    cmp r9, rax
    jbe .small
    mov rcx, rax
    mov rdi, r8
    cld
    rep movsb
    mov byte [rdi], 0
    add rsp, 40
    ret
.small:
    mov rax, -RT_ENOSPC
    add rsp, 40
    ret
; Exact sixteen lowercase hex digits, no prefix, plus NUL (capacity >= 17).
rt_format_hex64:
    cmp rsi, 17
    jb .small
    xor ecx, ecx
.loop:
    rol rdx, 4
    mov eax, edx
    and eax, 15
    add eax, '0'
    cmp eax, '9'
    jbe .store
    add eax, 39
.store:
    mov [rdi+rcx], al
    inc ecx
    cmp ecx, 16
    jb .loop
    mov byte [rdi+16], 0
    mov eax, 16
    ret
.small:
    mov rax, -RT_ENOSPC
    ret
; (bytes, length) -> RAX=status (0 or -EINVAL/-ERANGE), RDX=value or zero.
; u64: one or more ASCII digits; i64: optional '+'/'-' then digits.
; Full span consumed or rejected; no whitespace, NUL, locale, or partial parsing.
global rt_parse_u64, rt_parse_i64
rt_parse_u64:
    xor r8d, r8d
    mov r9, -1
    jmp parse_integer
rt_parse_i64:
    xor r8d, r8d
    mov r9, 0x7fffffffffffffff
    test rsi, rsi
    jz parse_integer.invalid
    cmp byte [rdi], '-'
    je .minus
    cmp byte [rdi], '+'
    jne parse_integer
    inc rdi
    dec rsi
    jmp parse_integer
.minus:
    mov r8d, 1
    inc r9
    inc rdi
    dec rsi
parse_integer:
    test rsi, rsi
    jz .invalid
    xor ecx, ecx
    xor edx, edx
    mov r10d, 10
.loop:
    movzx r11d, byte [rdi+rcx]
    sub r11d, '0'
    cmp r11d, 9
    ja .invalid
    mov rax, rdx
    mul r10
    test rdx, rdx
    jnz .overflow
    add rax, r11
    jc .overflow
    cmp rax, r9
    ja .overflow
    mov rdx, rax
    inc rcx
    cmp rcx, rsi
    jb .loop
    test r8, r8
    jz .ok
    neg rdx
.ok:
    xor eax, eax
    ret
.invalid:
    xor edx, edx
    mov rax, -RT_EINVAL
    ret
.overflow:
    xor edx, edx
    mov rax, -RT_ERANGE
    ret
section .note.GNU-stack noalloc noexec nowrite progbits

; Original bounded unsigned-integer helpers for exact binary64 decimal conversion.
; Layout: qword used limbs, followed by 64 little-endian qword limbs.
; Internal preconditions: valid workspace, no overflow beyond 4096 bits;
; sub requires a>=b, div_small divisor nonzero. No SIMD/floating-point use.
%include "include/abi.inc"
%include "include/rt/biguint.inc"
section .text
global bu_set, bu_copy, bu_mul_small, bu_add_small, bu_shl, bu_shr1
global bu_bits, bu_cmp, bu_sub, bu_div_small
; (dst, u64)
bu_set:
    mov qword [rdi], 0
    test rsi, rsi
    jz .done
    mov qword [rdi], 1
    mov [rdi+8], rsi
.done:
    ret
; (dst, src), uninitialized tail is intentionally not read/copied.
bu_copy:
    mov rcx, [rsi]
    inc rcx
    cld
    rep movsq
    ret
; (a, small u64). Factor zero permitted.
bu_mul_small:
    mov rcx, [rdi]
    test rcx, rcx
    jz .done
    test rsi, rsi
    jz .zero
    xor r8d, r8d
    xor r9d, r9d
.loop:
    mov rax, [rdi+r9*8+8]
    mul rsi
    add rax, r8
    adc rdx, 0
    mov [rdi+r9*8+8], rax
    mov r8, rdx
    inc r9
    cmp r9, rcx
    jb .loop
    test r8, r8
    jz .done
    mov [rdi+rcx*8+8], r8
    inc qword [rdi]
.done:
    ret
.zero:
    mov qword [rdi], 0
    ret
; (a, u64), small carry propagation.
bu_add_small:
    test rsi, rsi
    jz .done
    mov rcx, [rdi]
    test rcx, rcx
    jz bu_set
    add [rdi+8], rsi
    jnc .done
    mov r8d, 1
.carry:
    cmp r8, rcx
    jae .append
    add qword [rdi+r8*8+8], 1
    jnc .done
    inc r8
    jmp .carry
.append:
    mov qword [rdi+rcx*8+8], 1
    inc qword [rdi]
.done:
    ret
; (a, bit count). Move whole limbs first, then shift residue.
bu_shl:
    mov r8, [rdi]
    test r8, r8
    jz .done
    test rsi, rsi
    jz .done
    mov r9, rsi
    shr r9, 6
    and esi, 63
    test r9, r9
    jz .residue
    mov rcx, r8
.move:
    dec rcx
    mov rax, [rdi+rcx*8+8]
    lea r10, [rcx+r9]
    mov [rdi+r10*8+8], rax
    test rcx, rcx
    jnz .move
    xor ecx, ecx
.clear:
    mov qword [rdi+rcx*8+8], 0
    inc rcx
    cmp rcx, r9
    jb .clear
    add r8, r9
    mov [rdi], r8
.residue:
    test esi, esi
    jz .done
    mov ecx, esi
    xor r9d, r9d
    xor r10d, r10d
.shift:
    mov rax, [rdi+r10*8+8]
    xor edx, edx
    shld rdx, rax, cl
    shl rax, cl
    or rax, r9
    mov [rdi+r10*8+8], rax
    mov r9, rdx
    inc r10
    cmp r10, r8
    jb .shift
    test r9, r9
    jz .done
    mov [rdi+r8*8+8], r9
    inc qword [rdi]
.done:
    ret
bu_shr1:
    mov rcx, [rdi]
    test rcx, rcx
    jz .done
    clc
.loop:
    rcr qword [rdi+rcx*8], 1
    dec rcx                    ; DEC preserves carry from RCR
    jnz .loop
    mov rcx, [rdi]
    cmp qword [rdi+rcx*8], 0
    jne .done
    dec qword [rdi]
.done:
    ret
bu_bits:
    mov rax, [rdi]
    test rax, rax
    jz .done
    mov rcx, [rdi+rax*8]
    dec rax
    shl rax, 6
    bsr rcx, rcx
    lea rax, [rax+rcx+1]
.done:
    ret
; signed comparison result -1/0/+1 in EAX.
bu_cmp:
    mov rcx, [rdi]
    cmp rcx, [rsi]
    jb .less
    ja .more
    test rcx, rcx
    jz .equal
.loop:
    mov rax, [rdi+rcx*8]
    cmp rax, [rsi+rcx*8]
    jb .less
    ja .more
    dec rcx
    jnz .loop
.equal:
    xor eax, eax
    ret
.less:
    mov eax, -1
    ret
.more:
    mov eax, 1
    ret
; a -= b, no tail reads beyond b.length.
bu_sub:
    mov r8, [rdi]
    mov r9, [rsi]
    xor ecx, ecx
    xor r10d, r10d             ; incoming borrow
.loop:
    cmp rcx, r8
    jae .trim
    xor eax, eax
    cmp rcx, r9
    jae .word
    mov rax, [rsi+rcx*8+8]
.word:
    bt r10, 0
    sbb [rdi+rcx*8+8], rax
    setc r10b
    inc rcx
    jmp .loop
.trim:
    test r8, r8
    jz .done
    cmp qword [rdi+r8*8], 0
    jne .done
    dec r8
    jmp .trim
.done:
    mov [rdi], r8
    ret
; a /= divisor, remainder in RAX.
bu_div_small:
    mov rcx, [rdi]
    xor edx, edx
    test rcx, rcx
    jz .done
.loop:
    mov rax, [rdi+rcx*8]
    div rsi
    mov [rdi+rcx*8], rax
    dec rcx
    jnz .loop
    mov rcx, [rdi]
    cmp qword [rdi+rcx*8], 0
    jne .done
    dec qword [rdi]
.done:
    mov rax, rdx
    ret
section .note.GNU-stack noalloc noexec nowrite progbits

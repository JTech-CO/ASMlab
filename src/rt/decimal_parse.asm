; Exact decimal -> IEEE binary64 using bounded integer rational arithmetic.
; Original project implementation: no floating-point arithmetic, libc or tables.
; Nearest, ties-to-even independent of MXCSR; underflow may return signed zero.
%include "include/abi.inc"
%include "include/rt/biguint.inc"
extern bu_set, bu_copy, bu_mul_small, bu_add_small, bu_shl, bu_shr1
extern bu_bits, bu_cmp, bu_sub
section .text
global rt_parse_f64, rt_decimal_from_cstr
; (bytes,length<=127) -> RAX=0/-22/-34; RDX=bits (infinity on overflow,
; zero on syntax error). Grammar [+-]?(digits[.digits?]?|.digits)([eE][+-]?digits)?
; Consumes entire span; no NUL, whitespace, hex, NaN/Inf. Valid spans required.
rt_parse_f64:
    FRAME 1696
    mov r15, rdi
    lea rbx, [rdi+rsi]
    test rsi, rsi
    jz .invalid
    cmp rsi, 127
    ja .invalid
    lea r12, [rsp]                ; N
    lea r13, [rsp+BU_SLOT]        ; D
    lea r14, [rsp+BU_SLOT*2]      ; work
    mov qword [rsp+1584], 0       ; sign bit
    mov qword [rsp+1592], 0       ; fractional digit count
    mov qword [rsp+1600], 0       ; seen dot
    mov qword [rsp+1608], 0       ; significant decimal digit count
    mov qword [rsp+1616], 0       ; all digit count
    mov qword [rsp+1624], 0       ; exponent sign
    mov qword [rsp+1632], 0       ; exponent magnitude -> effective decimal exponent
    mov rdi, r12
    xor esi, esi
    call bu_set
    cmp byte [r15], '-'
    jne .plus
    bts qword [rsp+1584], 63
    inc r15
    jmp .mantissa
.plus:
    cmp byte [r15], '+'
    jne .mantissa
    inc r15
.mantissa:
    cmp r15, rbx
    jae .mantissa_end
    movzx eax, byte [r15]
    cmp al, '.'
    je .dot
    cmp al, 'e'
    je .exp_start
    cmp al, 'E'
    je .exp_start
    sub eax, '0'
    cmp eax, 9
    ja .invalid
    mov [rsp+1672], rax
    inc qword [rsp+1616]
    mov rcx, [rsp+1600]
    add [rsp+1592], rcx
    test eax, eax
    jnz .significant
    cmp qword [r12], 0
    je .accumulate
.significant:
    inc qword [rsp+1608]
.accumulate:
    mov rdi, r12
    mov esi, 10
    call bu_mul_small
    mov rdi, r12
    mov rsi, [rsp+1672]
    call bu_add_small
    inc r15
    jmp .mantissa
.dot:
    cmp qword [rsp+1600], 0
    jne .invalid
    mov qword [rsp+1600], 1
    inc r15
    jmp .mantissa
.exp_start:
    cmp qword [rsp+1616], 0
    je .invalid
    inc r15
    cmp r15, rbx
    jae .invalid
    cmp byte [r15], '-'
    jne .exp_plus
    mov qword [rsp+1624], 1
    inc r15
    jmp .exp_first
.exp_plus:
    cmp byte [r15], '+'
    jne .exp_first
    inc r15
.exp_first:
    cmp r15, rbx
    jae .invalid
.exp_loop:
    movzx eax, byte [r15]
    sub eax, '0'
    cmp eax, 9
    ja .invalid
    mov rcx, [rsp+1632]
    cmp rcx, 10000
    jae .exp_next
    imul rcx, 10
    add rcx, rax
    mov rdx, 10000
    cmp rcx, rdx
    cmova rcx, rdx
    mov [rsp+1632], rcx
.exp_next:
    inc r15
    cmp r15, rbx
    jb .exp_loop
.mantissa_end:
    cmp qword [rsp+1616], 0
    je .invalid
    mov rax, [rsp+1632]
    cmp qword [rsp+1624], 0
    je .exp_signed
    neg rax
.exp_signed:
    sub rax, [rsp+1592]
    mov [rsp+1632], rax
    cmp qword [r12], 0
    je .zero
    add rax, [rsp+1608]
    dec rax                      ; floor(log10(abs(value)))
    cmp rax, 308
    jg .overflow
    cmp rax, -324
    jl .zero
    mov rdi, r13
    mov esi, 1
    call bu_set
    mov r15, [rsp+1632]
    test r15, r15
    js .denominator
.numerator_loop:
    test r15, r15
    jz .exponent2
    mov rdi, r12
    mov esi, 10
    call bu_mul_small
    dec r15
    jmp .numerator_loop
.denominator:
    neg r15
.denominator_loop:
    test r15, r15
    jz .exponent2
    mov rdi, r13
    mov esi, 10
    call bu_mul_small
    dec r15
    jmp .denominator_loop
.exponent2:
    mov rdi, r12
    call bu_bits
    mov rbx, rax
    mov rdi, r13
    call bu_bits
    sub rbx, rax                 ; trial floor(log2(N/D))
    test rbx, rbx
    js .negative_exp
    mov rdi, r14
    mov rsi, r13
    call bu_copy
    mov rdi, r14
    mov rsi, rbx
    call bu_shl
    mov rdi, r12
    mov rsi, r14
    call bu_cmp
    jmp .adjust_exp
.negative_exp:
    mov rdi, r14
    mov rsi, r12
    call bu_copy
    mov rdi, r14
    mov rsi, rbx
    neg rsi
    call bu_shl
    mov rdi, r14
    mov rsi, r13
    call bu_cmp
.adjust_exp:
    test eax, eax
    jns .exponent_ready
    dec rbx
.exponent_ready:
    mov [rsp+1640], rbx
    mov esi, 1074               ; subnormal unit = 2^-1074
    cmp rbx, -1022
    jl .scale
    mov esi, 52
    sub rsi, rbx
.scale:
    test rsi, rsi
    js .scale_denominator
    mov rdi, r12
    call bu_shl
    jmp .divide
.scale_denominator:
    neg rsi
    mov rdi, r13
    call bu_shl
.divide:
    ; Long division with at most 53 quotient bits. N becomes the remainder.
    mov rdi, r12
    call bu_bits
    mov rbx, rax
    mov rdi, r13
    call bu_bits
    sub rbx, rax
    xor r15d, r15d              ; quotient
    test rbx, rbx
    js .round
    mov rdi, r14
    mov rsi, r13
    call bu_copy
    mov rdi, r14
    mov rsi, rbx
    call bu_shl
.div_loop:
    shl r15, 1
    mov rdi, r12
    mov rsi, r14
    call bu_cmp
    test eax, eax
    js .div_shift
    mov rdi, r12
    mov rsi, r14
    call bu_sub
    inc r15
.div_shift:
    mov rdi, r14
    call bu_shr1
    dec rbx
    jns .div_loop
.round:
    mov rdi, r12
    mov esi, 1
    call bu_shl
    mov rdi, r12
    mov rsi, r13
    call bu_cmp
    test eax, eax
    js .pack
    jnz .round_up
    test r15b, 1
    jz .pack
.round_up:
    inc r15
.pack:
    mov rbx, [rsp+1640]
    cmp rbx, -1022
    jl .subnormal
    mov rax, 0x0020000000000000
    cmp r15, rax
    jb .normal
    shr r15, 1
    inc rbx
.normal:
    cmp rbx, 1023
    jg .overflow
    add rbx, 1023
    shl rbx, 52
    btr r15, 52
    or r15, rbx
.subnormal:
    mov rdx, r15
    or rdx, [rsp+1584]
    xor eax, eax
    DONE
.zero:
    mov rdx, [rsp+1584]
    xor eax, eax
    DONE
.overflow:
    mov rdx, 0x7ff0000000000000
    or rdx, [rsp+1584]
    mov rax, -34
    DONE
.invalid:
    xor edx, edx
    mov rax, -22
    DONE
; Compatibility with the existing lexer boundary. Not libc strtod semantics.
; Exact token only, max127 bytes. Error -> nonfinite sentinel rejected by lexer.
rt_decimal_from_cstr:
    FRAME 16
    mov r12, rdi
    mov r13, rsi
    xor esi, esi
.scan:
    cmp rsi, 128
    jae .bad
    cmp byte [r12+rsi], 0
    je .parse
    inc rsi
    jmp .scan
.parse:
    mov [rsp], rsi
    call rt_parse_f64
    test rax, rax
    jnz .bad
    movq xmm0, rdx
    mov rax, [rsp]
    add rax, r12
    test r13, r13
    jz .done
    mov [r13], rax
.done:
    DONE
.bad:
    mov rax, 0x7ff0000000000000
    movq xmm0, rax
    test r13, r13
    jz .done
    mov [r13], r12
    DONE
section .note.GNU-stack noalloc noexec nowrite progbits

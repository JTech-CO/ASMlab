; Exact binary64 -> general decimal, precision 1..17 significant digits.
; Integer-only reference path: m*2^e becomes an exact decimal integer times 10^k.
; Rounding is performed once on decimal digits (nearest, ties to even).
; Matches C-locale %g selection without locale/libc, shortest-output claims or FPU.
%include "include/abi.inc"
%include "include/rt/biguint.inc"
extern bu_set, bu_shl, bu_mul_small, bu_div_small
section .rodata
text_nan: db 'nan',0
text_inf: db 'inf',0
section .text
global rt_format_f64
; (dst, capacity including NUL, raw binary64 bits, precision 1..17)
; -> length excluding NUL, or -22 invalid precision / -28 insufficient space.
; Failure leaves dst unchanged. NaN/Inf may be displayed for trace metadata;
; parser/results still reject them. Signed zero is preserved. No MXCSR changes.
rt_format_f64:
    FRAME 1504
    mov [rsp+1440], rdi         ; output pointer
    mov [rsp+1448], rsi         ; capacity
    mov [rsp+1456], rcx         ; precision
    mov rax, rdx
    shr rax, 63
    mov [rsp+1464], rax         ; sign
    cmp ecx, 1
    jl .invalid
    cmp rcx, 17
    ja .invalid
    lea r12, [rsp]             ; big integer
    lea r13, [rsp+528]         ; reverse exact decimal digits (800 bytes)
    lea r14, [rsp+1344]        ; final temporary output (80 bytes)
    xor ebx, ebx               ; output count
    mov rax, rdx
    shr rax, 52
    and eax, 0x7ff
    mov rsi, 0x000fffffffffffff
    and rsi, rdx
    cmp eax, 0x7ff
    je .special
    test eax, eax
    jz .denormal
    bts rsi, 52
    sub eax, 1075
    jmp .mantissa
.denormal:
    mov eax, -1074
.mantissa:
    mov r15d, eax              ; binary exponent
    test rsi, rsi
    jz .zero
    mov rdi, r12
    call bu_set
    mov qword [rsp+1472], 0    ; decimal scale
    test r15d, r15d
    js .negative_exp
    mov rdi, r12
    mov esi, r15d
    call bu_shl
    jmp .digits
.negative_exp:
    movsxd rax, r15d
    mov [rsp+1472], rax
    neg r15d
.fives:
    mov rdi, r12
    mov esi, 5
    call bu_mul_small
    dec r15d
    jnz .fives
.digits:
    xor r15d, r15d            ; reverse digit count
.convert:
    mov rdi, r12
    mov esi, 10
    call bu_div_small
    add al, '0'
    mov [r13+r15], al
    inc r15
    cmp qword [r12], 0
    jne .convert
    mov rax, r15
    add rax, [rsp+1472]
    dec rax
    mov [rsp+1472], rax       ; base10 exponent after normalization
    ; Copy leading precision digits in normal order to a separate 32-byte area.
    lea r12, [rsp+1408]
    mov rcx, [rsp+1456]
    cmp rcx, r15
    cmova rcx, r15
    mov [rsp+1480], rcx       ; retained digit count
    xor edx, edx
.leading:
    mov rax, r15
    sub rax, rdx
    dec rax
    mov al, [r13+rax]
    mov [r12+rdx], al
    inc rdx
    cmp rdx, rcx
    jb .leading
    cmp rcx, r15
    jae .trim
    mov rax, r15
    sub rax, rcx
    dec rax                  ; first discarded reverse index
    cmp byte [r13+rax], '5'
    jb .trim
    ja .round_up
    ; Halfway only when all less significant exact digits are zero.
.sticky:
    test rax, rax
    jz .tie
    dec rax
    cmp byte [r13+rax], '0'
    jne .round_up
    jmp .sticky
.tie:
    test byte [r12+rcx-1], 1
    jz .trim
.round_up:
    mov rax, [rsp+1480]
.carry:
    dec rax
    cmp byte [r12+rax], '9'
    jne .increment
    mov byte [r12+rax], '0'
    test rax, rax
    jnz .carry
    mov byte [r12], '1'
    inc qword [rsp+1472]
    jmp .trim
.increment:
    inc byte [r12+rax]
.trim:
    mov r15, [rsp+1480]
.trim_loop:
    cmp r15, 1
    jbe .sign
    cmp byte [r12+r15-1], '0'
    jne .sign
    dec r15
    jmp .trim_loop
.sign:
    cmp qword [rsp+1464], 0
    je .choose
    mov byte [r14+rbx], '-'
    inc rbx
.choose:
    mov rax, [rsp+1472]
    cmp rax, -4
    jl .scientific
    cmp rax, [rsp+1456]
    jge .scientific
    inc rax                   ; decimal point position D
    test rax, rax
    jle .leading_zero
    xor ecx, ecx
.fixed:
    cmp rcx, rax
    jae .fraction_start
    mov dl, '0'
    cmp rcx, r15
    jae .fixed_store
    mov dl, [r12+rcx]
.fixed_store:
    mov [r14+rbx], dl
    inc rbx
    inc rcx
    jmp .fixed
.fraction_start:
    cmp rcx, r15
    jae .commit
    mov byte [r14+rbx], '.'
    inc rbx
.fraction:
    mov dl, [r12+rcx]
    mov [r14+rbx], dl
    inc rbx
    inc rcx
    cmp rcx, r15
    jb .fraction
    jmp .commit
.leading_zero:
    mov byte [r14+rbx], '0'
    mov byte [r14+rbx+1], '.'
    add rbx, 2
.zero_pad:
    test rax, rax
    jz .fraction_zero_start
    mov byte [r14+rbx], '0'
    inc rbx
    inc rax
    jmp .zero_pad
.fraction_zero_start:
    xor ecx, ecx
    jmp .fraction
.scientific:
    mov al, [r12]
    mov [r14+rbx], al
    inc rbx
    cmp r15, 1
    jbe .sci_exp
    mov byte [r14+rbx], '.'
    inc rbx
    mov ecx, 1
.sci_fraction:
    mov al, [r12+rcx]
    mov [r14+rbx], al
    inc rbx
    inc rcx
    cmp rcx, r15
    jb .sci_fraction
.sci_exp:
    mov byte [r14+rbx], 'e'
    inc rbx
    mov rax, [rsp+1472]
    mov dl, '+'
    test rax, rax
    jns .sci_sign
    mov dl, '-'
    neg rax
.sci_sign:
    mov [r14+rbx], dl
    inc rbx
    cmp rax, 100
    jb .two_digits
    xor edx, edx
    mov ecx, 100
    div rcx
    add al, '0'
    mov [r14+rbx], al
    inc rbx
    mov rax, rdx
.two_digits:
    xor edx, edx
    mov ecx, 10
    div rcx
    add al, '0'
    add dl, '0'
    mov [r14+rbx], al
    mov [r14+rbx+1], dl
    add rbx, 2
    jmp .commit
.zero:
    cmp qword [rsp+1464], 0
    je .zero_digit
    mov byte [r14], '-'
    inc rbx
.zero_digit:
    mov byte [r14+rbx], '0'
    inc rbx
    jmp .commit
.special:
    lea r15, [text_inf]
    test rsi, rsi
    jz .special_sign
    lea r15, [text_nan]
.special_sign:
    cmp qword [rsp+1464], 0
    je .special_copy
    mov byte [r14], '-'
    inc rbx
.special_copy:
    mov eax, [r15]
    mov [r14+rbx], eax
    add rbx, 3
.commit:
    cmp [rsp+1448], rbx
    jbe .small
    mov rdi, [rsp+1440]
    mov rsi, r14
    mov rcx, rbx
    cld
    rep movsb
    mov byte [rdi], 0
    mov rax, rbx
    DONE
.small:
    mov rax, -28
    DONE
.invalid:
    mov rax, -22
    DONE
section .note.GNU-stack noalloc noexec nowrite progbits

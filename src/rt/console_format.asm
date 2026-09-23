; Small, trusted-format renderer for the existing terminal views; NOT ISO printf.
; Supported: %% %s %c %d %ld %x %lx %g, space/zero width (0..4096),
; dynamic nonnegative width *, precision 1..17 for g. No %n/locale/user formats.
; All numeric formatting uses the project's integer/decimal routines.
%include "include/abi.inc"
extern rt_console_write_bytes, rt_console_fault, rt_strlen
extern rt_format_i64, rt_format_hex64, rt_format_f64
section .text
global rt_console_format
rt_console_format:
    FRAME 416
    mov r15, rsp
    mov [r15], rsi
    mov [r15+8], rdx
    mov [r15+16], rcx
    mov [r15+24], r8
    mov [r15+32], r9
    mov qword [r15+40], 0       ; GP cursor
    mov qword [r15+48], 0       ; FP cursor
    lea rcx, [rbp+16]
    mov [r15+56], rcx          ; first stack argument
    mov qword [r15+104], 0     ; bytes submitted
    movzx eax, al
    mov [r15+120], rax         ; number of valid vector varargs
    movdqu [r15+128], xmm0
    movdqu [r15+144], xmm1
    movdqu [r15+160], xmm2
    movdqu [r15+176], xmm3
    movdqu [r15+192], xmm4
    movdqu [r15+208], xmm5
    movdqu [r15+224], xmm6
    movdqu [r15+240], xmm7
    mov r12, rdi
.loop:
    mov r14, r12
.literal:
    mov al, [r12]
    test al, al
    jz .literal_end
    cmp al, '%'
    je .literal_end
    inc r12
    jmp .literal
.literal_end:
    mov rsi, r12
    sub rsi, r14
    jz .conversion
    add [r15+104], rsi
    mov rdi, r14
    call rt_console_write_bytes
    test rax, rax
    jnz .done
.conversion:
    cmp byte [r12], 0
    je .success
    inc r12
    mov qword [r15+72], 0      ; width
    mov qword [r15+80], 6      ; precision
    mov qword [r15+88], 0      ; zero padding
    mov qword [r15+96], 0      ; long argument
    cmp byte [r12], '%'
    je .percent
    cmp byte [r12], '0'
    jne .width
    mov qword [r15+88], 1
    inc r12
.width:
    cmp byte [r12], '*'
    jne .width_digits
    call .next_gp
    movsxd rax, eax
    test rax, rax
    js .invalid
    cmp rax, 4096
    ja .invalid
    mov [r15+72], rax
    inc r12
    jmp .precision
.width_digits:
    movzx eax, byte [r12]
    sub eax, '0'
    cmp eax, 9
    ja .precision
    imul rcx, [r15+72], 10
    add rcx, rax
    cmp rcx, 4096
    ja .invalid
    mov [r15+72], rcx
    inc r12
    jmp .width_digits
.precision:
    cmp byte [r12], '.'
    jne .long
    inc r12
    mov qword [r15+80], 0
    movzx eax, byte [r12]
    sub eax, '0'
    cmp eax, 9
    ja .invalid
.precision_digit:
    movzx eax, byte [r12]
    sub eax, '0'
    cmp eax, 9
    ja .precision_end
    imul rcx, [r15+80], 10
    add rcx, rax
    cmp rcx, 17
    ja .invalid
    mov [r15+80], rcx
    inc r12
    jmp .precision_digit
.precision_end:
    cmp qword [r15+80], 1
    jb .invalid
.long:
    cmp byte [r12], 'l'
    jne .type
    mov qword [r15+96], 1
    inc r12
.type:
    mov al, [r12]
    inc r12
    cmp al, 's'
    je .string
    cmp al, 'c'
    je .character
    cmp al, 'd'
    je .integer
    cmp al, 'x'
    je .hex
    cmp al, 'g'
    je .float
    jmp .invalid
.percent:
    inc r12
    mov byte [r15+256], '%'
    lea r14, [r15+256]
    mov r13d, 1
    jmp .emit
.string:
    call .next_gp
    mov r14, rax
    mov rdi, rax
    call rt_strlen
    mov r13, rax
    mov qword [r15+88], 0
    jmp .emit
.character:
    call .next_gp
    mov [r15+256], al
    lea r14, [r15+256]
    mov r13d, 1
    jmp .emit
.integer:
    call .next_gp
    cmp qword [r15+96], 0
    jne .integer64
    movsxd rax, eax
.integer64:
    mov rdx, rax
    lea rdi, [r15+256]
    mov esi, 128
    call rt_format_i64
    jmp .number_ready
.hex:
    call .next_gp
    cmp qword [r15+96], 0
    jne .hex64
    mov eax, eax
.hex64:
    mov rdx, rax
    lea rdi, [r15+256]
    mov esi, 128
    call rt_format_hex64
    lea r14, [r15+256]
    mov r13d, 16
.trim_hex:
    cmp r13, 1
    jbe .emit
    cmp byte [r14], '0'
    jne .emit
    inc r14
    dec r13
    jmp .trim_hex
.float:
    mov rcx, [r15+48]
    cmp rcx, 8
    jae .invalid
    cmp rcx, [r15+120]
    jae .invalid
    inc qword [r15+48]
    shl rcx, 4
    mov rdx, [r15+rcx+128]
    mov rcx, [r15+80]
    lea rdi, [r15+256]
    mov esi, 128
    call rt_format_f64
.number_ready:
    test rax, rax
    js .format_failure
    mov r13, rax
    lea r14, [r15+256]
.emit:
    mov rbx, [r15+72]
    sub rbx, r13
    jle .content
    ; A negative sign precedes zero padding, never follows it.
    cmp qword [r15+88], 0
    je .pad
    cmp byte [r14], '-'
    jne .pad
    mov rdi, r14
    mov esi, 1
    call rt_console_write_bytes
    test rax, rax
    jnz .done
    inc qword [r15+104]
    inc r14
    dec r13
.pad:
    mov byte [r15+400], ' '
    cmp qword [r15+88], 0
    je .pad_loop
    mov byte [r15+400], '0'
.pad_loop:
    lea rdi, [r15+400]
    mov esi, 1
    call rt_console_write_bytes
    test rax, rax
    jnz .done
    inc qword [r15+104]
    dec rbx
    jnz .pad_loop
.content:
    mov rdi, r14
    mov rsi, r13
    call rt_console_write_bytes
    test rax, rax
    jnz .done
    add [r15+104], r13
    jmp .loop
.success:
    mov rax, [r15+104]
.done:
    DONE
.invalid:
    mov rax, -22
.format_failure:
    mov rdi, rax
    call rt_console_fault
    DONE
; Internal, no stack argument locations depend on RSP here.
.next_gp:
    mov rcx, [r15+40]
    inc qword [r15+40]
    cmp rcx, 5
    jae .stack_gp
    mov rax, [r15+rcx*8]
    ret
.stack_gp:
    sub rcx, 5
    mov rax, [r15+56]
    mov rax, [rax+rcx*8]
    ret
section .note.GNU-stack noalloc noexec nowrite progbits

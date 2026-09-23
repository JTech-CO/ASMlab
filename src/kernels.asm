; Trace ABI: edi=opcode, xmm0=lhs/destination, xmm1=rhs/source.
; Preserves xmm1..xmm15 and all GP registers except rax, rdx, r10, r11.
; No libc call occurs between a watched instruction and its register capture.
section .rodata
op_addsd: db 'addsd xmm0, xmm1',0
op_subsd: db 'subsd xmm0, xmm1',0
op_mulsd: db 'mulsd xmm0, xmm1',0
op_divsd: db 'divsd xmm0, xmm1',0
op_sqrtsd: db 'sqrtsd xmm0, xmm1',0
op_addpd: db 'addpd xmm0, xmm1',0
op_subpd: db 'subpd xmm0, xmm1',0
op_mulpd: db 'mulpd xmm0, xmm1',0
op_divpd: db 'divpd xmm0, xmm1',0
op_sqrtpd: db 'sqrtpd xmm0, xmm1',0
op_movapd: db 'movapd xmm0, xmm1',0
op_xorpd: db 'xorpd xmm0, xmm1',0
op_names: dq 0, op_addsd, op_subsd, op_mulsd, op_divsd, op_sqrtsd
          dq op_addpd, op_subpd, op_mulpd, op_divpd, op_sqrtpd, op_movapd, op_xorpd
section .text
exec_sse:
    lea r11, [trace_scratch]
    cmp qword [trace_enabled], 0
    je .capture
    inc qword [trace_total]
    mov rax, [trace_count]
    cmp rax, TRACE_CAP
    jae .capture
    imul rax, TS
    lea r11, [trace_records+rax]
    inc qword [trace_count]
.capture:
    mov [r11], rdi
    mov rax, [trace_node]
    mov [r11+8], rax
    mov rax, [trace_element]
    mov [r11+16], rax
    movupd [r11+32], xmm0
    movupd [r11+48], xmm1
    mov qword [r11+88], 0
    stmxcsr [r11+88]
    cmp edi, O_ADDSD
    je .addsd
    cmp edi, O_SUBSD
    je .subsd
    cmp edi, O_MULSD
    je .mulsd
    cmp edi, O_DIVSD
    je .divsd
    cmp edi, O_SQRTSD
    je .sqrtsd
    cmp edi, O_ADDPD
    je .addpd
    cmp edi, O_SUBPD
    je .subpd
    cmp edi, O_MULPD
    je .mulpd
    cmp edi, O_DIVPD
    je .divpd
    cmp edi, O_SQRTPD
    je .sqrtpd
    cmp edi, O_XORPD
    je .xorpd
    lea r10, [watched_movapd]
watched_movapd:
    movapd xmm0, xmm1
    jmp exec_sse.after
exec_sse.addsd:
    lea r10, [watched_addsd]
watched_addsd:
    addsd xmm0, xmm1
    jmp exec_sse.after
exec_sse.subsd:
    lea r10, [watched_subsd]
watched_subsd:
    subsd xmm0, xmm1
    jmp exec_sse.after
exec_sse.mulsd:
    lea r10, [watched_mulsd]
watched_mulsd:
    mulsd xmm0, xmm1
    jmp exec_sse.after
exec_sse.divsd:
    lea r10, [watched_divsd]
watched_divsd:
    divsd xmm0, xmm1
    jmp exec_sse.after
exec_sse.sqrtsd:
    lea r10, [watched_sqrtsd]
watched_sqrtsd:
    sqrtsd xmm0, xmm1
    jmp exec_sse.after
exec_sse.addpd:
    lea r10, [watched_addpd]
watched_addpd:
    addpd xmm0, xmm1
    jmp exec_sse.after
exec_sse.subpd:
    lea r10, [watched_subpd]
watched_subpd:
    subpd xmm0, xmm1
    jmp exec_sse.after
exec_sse.mulpd:
    lea r10, [watched_mulpd]
watched_mulpd:
    mulpd xmm0, xmm1
    jmp exec_sse.after
exec_sse.divpd:
    lea r10, [watched_divpd]
watched_divpd:
    divpd xmm0, xmm1
    jmp exec_sse.after
exec_sse.sqrtpd:
    lea r10, [watched_sqrtpd]
watched_sqrtpd:
    sqrtpd xmm0, xmm1
    jmp exec_sse.after
exec_sse.xorpd:
    lea r10, [watched_xorpd]
watched_xorpd:
    xorpd xmm0, xmm1
exec_sse.after:
    movupd [r11+64], xmm0
    mov [r11+24], r10
    mov qword [r11+80], 0
    stmxcsr [r11+80]
    ret

; Scalar broadcast or same-shaped elementwise binary operation.
elementwise:
    FRAME 48
    mov r12, rdi
    mov r13, rsi
    mov r15, rdx
    mov rax, [r12]
    imul rax, [r12+8]
    mov [rsp], rax
    mov rax, [r13]
    imul rax, [r13+8]
    mov [rsp+8], rax
    cmp r15, '/'
    jne .shape
    cmp rax, 1
    jne .rightdiv
.shape:
    cmp qword [rsp], 1
    je .shape_b
    cmp qword [rsp+8], 1
    je .shape_a
    mov rax, [r12]
    cmp rax, [r13]
    jne .badshape
    mov rax, [r12+8]
    cmp rax, [r13+8]
    jne .badshape
.shape_a:
    mov rdi, [r12]
    mov rsi, [r12+8]
    jmp .alloc
.shape_b:
    mov rdi, [r13]
    mov rsi, [r13+8]
.alloc:
    call new_value
    test rax, rax
    jz .fail
    mov r14, rax
    mov rcx, [rax]
    imul rcx, [rax+8]
    mov [rsp+16], rcx
    cmp r15, '+'
    je .opadd
    cmp r15, '-'
    je .opsub
    cmp r15, '*'
    je .opmul
    cmp r15, T_EMUL
    je .opmul
    mov r15d, O_DIVSD
    ; Check actual divisors before issuing scalar or packed division.
    xor ecx, ecx
.divcheck:
    cmp rcx, [rsp+8]
    jae .begin
    mov rax, [r13+16+rcx*8]
    shl rax, 1
    jz .divzero
    inc rcx
    jmp .divcheck
.opadd:
    mov r15d, O_ADDSD
    jmp .begin
.opsub:
    mov r15d, O_SUBSD
    jmp .begin
.opmul:
    mov r15d, O_MULSD
.begin:
    xor ebx, ebx
.loop:
    mov [trace_element], rbx
    mov rax, [rsp+16]
    sub rax, rbx
    cmp rax, 2
    jb .tail
    cmp qword [rsp], 1
    je .broadcast_a
    movupd xmm0, [r12+16+rbx*8]
    jmp .load_b
.broadcast_a:
    movsd xmm0, [r12+16]
    unpcklpd xmm0, xmm0
.load_b:
    cmp qword [rsp+8], 1
    je .broadcast_b
    movupd xmm1, [r13+16+rbx*8]
    jmp .packed
.broadcast_b:
    movsd xmm1, [r13+16]
    unpcklpd xmm1, xmm1
.packed:
    lea rdi, [r15+5]
    call exec_sse
    movupd [r14+16+rbx*8], xmm0
    add rbx, 2
    jmp .loop
.tail:
    test rax, rax
    jz .return
    xor eax, eax
    cmp qword [rsp], 1
    cmovne rax, rbx
    movsd xmm0, [r12+16+rax*8]
    xor eax, eax
    cmp qword [rsp+8], 1
    cmovne rax, rbx
    movsd xmm1, [r13+16+rax*8]
    mov rdi, r15
    call exec_sse
    movsd [r14+16+rbx*8], xmm0
.return:
    mov rax, r14
    DONE
.badshape:
    lea rdi, [err_shape]
    jmp .error
.rightdiv:
    lea rdi, [err_rightdiv]
    jmp .error
.divzero:
    lea rdi, [err_div]
.error:
    call set_error
.fail:
    xor eax, eax
    DONE

; Row-major C=A*B. Two K terms per mulpd/addpd; SSE2 horizontal reduction.
matmul:
    FRAME 64
    mov r12, rdi
    mov r13, rsi
    mov rax, [r12+8]
    cmp rax, [r13]
    jne .badshape
    mov [rsp], rax
    mov rdi, [r12]
    mov rsi, [r13+8]
    call new_value
    test rax, rax
    jz .fail
    mov r14, rax
    mov qword [rsp+8], 0
.row:
    mov rax, [rsp+8]
    cmp rax, [r12]
    jae .return
    mov qword [rsp+16], 0
.col:
    mov rax, [rsp+16]
    cmp rax, [r13+8]
    jae .nextrow
    mov rcx, [rsp+8]
    imul rcx, [r13+8]
    add rcx, rax
    mov [trace_element], rcx
    mov [rsp+24], rcx
    xor ebx, ebx
    pxor xmm4, xmm4
.pair:
    lea rax, [rbx+1]
    cmp rax, [rsp]
    jae .reduce
    mov rax, [rsp+8]
    imul rax, [rsp]
    add rax, rbx
    movupd xmm0, [r12+16+rax*8]
    mov rax, rbx
    imul rax, [r13+8]
    add rax, [rsp+16]
    movsd xmm1, [r13+16+rax*8]
    add rax, [r13+8]
    movhpd xmm1, [r13+16+rax*8]
    OP O_MULPD
    movapd xmm1, xmm0
    movapd xmm0, xmm4
    OP O_ADDPD
    movapd xmm4, xmm0
    add rbx, 2
    jmp .pair
.reduce:
    movapd xmm0, xmm4
    movapd xmm1, xmm4
    unpckhpd xmm1, xmm1
    OP O_ADDSD
    movapd xmm4, xmm0
    cmp rbx, [rsp]
    jae .store
    mov rax, [rsp+8]
    imul rax, [rsp]
    add rax, rbx
    movsd xmm0, [r12+16+rax*8]
    mov rax, rbx
    imul rax, [r13+8]
    add rax, [rsp+16]
    movsd xmm1, [r13+16+rax*8]
    OP O_MULSD
    movapd xmm1, xmm0
    movapd xmm0, xmm4
    OP O_ADDSD
    movapd xmm4, xmm0
.store:
    mov rax, [rsp+24]
    movsd [r14+16+rax*8], xmm4
    inc qword [rsp+16]
    jmp .col
.nextrow:
    inc qword [rsp+8]
    jmp .row
.return:
    mov rax, r14
    DONE
.badshape:
    lea rdi, [err_shape]
    call set_error
.fail:
    xor eax, eax
    DONE

transpose_value:
    FRAME 0
    mov r12, rdi
    mov rdi, [r12+8]
    mov rsi, [r12]
    call new_value
    test rax, rax
    jz .return
    mov r13, rax
    xor r14d, r14d
.row:
    cmp r14, [r12]
    jae .complete
    xor r15d, r15d
.col:
    cmp r15, [r12+8]
    jae .nextrow
    mov rax, r14
    imul rax, [r12+8]
    add rax, r15
    movsd xmm1, [r12+16+rax*8]
    pxor xmm0, xmm0
    mov rbx, r15
    imul rbx, [r12]
    add rbx, r14
    mov [trace_element], rbx
    OP O_MOVAPD
    movsd [r13+16+rbx*8], xmm0
    inc r15
    jmp .col
.nextrow:
    inc r14
    jmp .row
.complete:
    mov rax, r13
.return:
    DONE

; Bitwise sign negation preserves signed zero and subnormal payloads.
negate_value:
    FRAME 0
    mov r12, rdi
    mov rdi, [r12]
    mov rsi, [r12+8]
    call new_value
    test rax, rax
    jz .return
    mov r13, rax
    mov r14, [r12]
    imul r14, [r12+8]
    xor ebx, ebx
.loop:
    mov [trace_element], rbx
    mov rax, r14
    sub rax, rbx
    cmp rax, 2
    jb .tail
    movupd xmm0, [r12+16+rbx*8]
    movupd xmm1, [sign_mask]
    OP O_XORPD
    movupd [r13+16+rbx*8], xmm0
    add rbx, 2
    jmp .loop
.tail:
    test rax, rax
    jz .complete
    movsd xmm0, [r12+16+rbx*8]
    movsd xmm1, [sign_mask]
    OP O_XORPD
    movsd [r13+16+rbx*8], xmm0
.complete:
    mov rax, r13
.return:
    DONE

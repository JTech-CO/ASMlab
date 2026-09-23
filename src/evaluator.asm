; AST evaluator: shape checks, bounded temporaries, no JIT or code generation.
section .text
eval_node:
    FRAME 32
    mov r12, rdi
    inc qword [eval_depth]
    cmp qword [eval_depth], DEPTH_CAP
    ja .depth
    test r12, r12
    jz .fail
    cmp qword [err_msg], 0
    jne .fail
    mov rax, [r12+N_POS]
    mov [tok_pos], rax
    mov rax, [r12+N_ID]
    mov [trace_node], rax
    mov qword [trace_element], 0
    mov rax, [r12+N_TYPE]
    cmp rax, NUM
    je .number
    cmp rax, VAR
    je .variable
    cmp rax, MATRIX
    je .matrix
    cmp rax, BINARY
    je .binary
    cmp rax, UNARY
    je .unary
    cmp rax, FUNC
    je .function
    cmp rax, INDEX
    je .function
    cmp rax, ASSIGN
    je .assignment
    jmp .fail
.number:
    mov edi, 1
    mov esi, 1
    call new_value
    test rax, rax
    jz .fail
    mov rdx, [r12+N_NUM]
    mov r10, [rax+V_DATA]
    mov [r10], rdx
    jmp .finish
.variable:
    lea rdi, [r12+N_NAME]
    lea rsi, [name_pi]
    call rt_strcmp
    test eax, eax
    jz .pi
    lea rdi, [r12+N_NAME]
    lea rsi, [name_e]
    call rt_strcmp
    test eax, eax
    jz .e
    lea rdi, [r12+N_NAME]
    call find_symbol
    test rax, rax
    jz .unknown
    mov rdi, [rax+S_VALUE]
    call clone_temp
    jmp .finish

.pi:
    lea r13, [pi]
    jmp .constant
.e:
    lea r13, [const_e]
.constant:
    mov edi, 1
    mov esi, 1
    call new_value
    test rax, rax
    jz .fail
    mov rdx, [r13]
    mov r10, [rax+V_DATA]
    mov [r10], rdx
    jmp .finish
.matrix:
    mov rdi, [r12+N_ROWS]
    mov rsi, [r12+N_COLS]
    call new_value
    test rax, rax
    jz .fail
    mov r13, rax
    mov r14, [r12+N_LEFT]
    xor ebx, ebx
.matrix_loop:
    test r14, r14
    jz .matrix_done
    mov rdi, r14
    call eval_node
    cmp qword [err_msg], 0
    jne .fail
    cmp qword [rax], 1
    jne .scalar_error
    cmp qword [rax+8], 1
    jne .scalar_error
    mov r10, [rax+V_DATA]
    mov rdx, [r10]
    mov r10, [r13+V_DATA]
    mov [r10+rbx*8], rdx
    inc rbx
    mov r14, [r14+N_NEXT]
    jmp .matrix_loop
.matrix_done:
    mov rax, r13
    jmp .finish
.binary:
    mov rdi, [r12+N_LEFT]
    call eval_node
    cmp qword [err_msg], 0
    jne .fail
    mov r13, rax
    mov rdi, [r12+N_RIGHT]
    call eval_node
    cmp qword [err_msg], 0
    jne .fail
    mov r14, rax
    call .context
    mov rdx, [r12+N_OP]
    cmp rdx, '^'
    je .power
    cmp rdx, '*'
    jne .elementwise
    mov rax, [r13]
    imul rax, [r13+8]
    cmp rax, 1
    je .elementwise
    mov rax, [r14]
    imul rax, [r14+8]
    cmp rax, 1
    je .elementwise
    mov rdi, r13
    mov rsi, r14
    call matmul
    jmp .finish
.elementwise:
    mov rdi, r13
    mov rsi, r14
    call elementwise
    jmp .finish
.power:
    mov rax, [r13]
    imul rax, [r13+8]
    cmp rax, 1
    jne .pow_error
    mov rax, [r14]
    imul rax, [r14+8]
    cmp rax, 1
    jne .pow_error
    mov edi, 1
    mov esi, 1
    call new_value
    test rax, rax
    jz .fail
    mov r15, rax
    mov r10, [r13+V_DATA]
    movsd xmm0, [r10]
    mov r10, [r14+V_DATA]
    movsd xmm1, [r10]
    call math_power
    mov r10, [r15+V_DATA]
    movsd [r10], xmm0
    mov rax, r15
    jmp .finish
.unary:
    mov rdi, [r12+N_LEFT]
    call eval_node
    cmp qword [err_msg], 0
    jne .fail
    cmp qword [r12+N_OP], '+'
    je .finish
    mov r13, rax
    call .context
    mov rdi, r13
    call negate_value
    jmp .finish
.function:
    mov rdi, r12
    call eval_call
    jmp .finish
.assignment:
    ; Preflight first. No partially successful assignment is visible.
    lea rdi, [r12+N_NAME]
    call assignment_allowed
    test eax, eax
    jz .fail
    mov rdi, [r12+N_LEFT]
    call eval_node
.finish:
    cmp qword [err_msg], 0
    jne .fail
    test rax, rax
    jz .fail
    mov r13, rax
    call .context
    mov rdi, r13
    call validate_value
    test eax, eax
    jz .fail
    mov [r12+N_VALUE], r13
    mov rax, r13
    dec qword [eval_depth]
    DONE
.context:
    mov rax, [r12+N_ID]
    mov [trace_node], rax
    mov rax, [r12+N_POS]
    mov [tok_pos], rax
    mov qword [trace_element], 0
    ret
.depth:
    lea rdi, [err_depth]
    jmp .error
.unknown:
    lea rdi, [err_unknown]
    jmp .error
.scalar_error:
    lea rdi, [err_scalar]
    jmp .error
.pow_error:
    lea rdi, [err_pow]
.error:
    call set_error
.fail:
    xor eax, eax
    dec qword [eval_depth]
    DONE

assignment_allowed:
    FRAME 0
    mov r12, rdi
    lea rsi, [name_pi]
    call rt_strcmp
    test eax, eax
    jz .readonly
    mov rdi, r12
    lea rsi, [name_e]
    call rt_strcmp
    test eax, eax
    jz .readonly
    mov rdi, r12
    lea rsi, [name_ans]
    call rt_strcmp
    test eax, eax
    jz .readonly
    mov rdi, r12
    call lookup_function
    test eax, eax
    jnz .readonly
    mov rdi, r12
    call find_symbol
    test rax, rax
    jnz .yes

.yes:
    mov eax, 1
    DONE
.readonly:
    lea rdi, [err_readonly]
    jmp .error
.error:
    call set_error
    xor eax, eax
    DONE

apply_function:
    FRAME 16
    mov r12, rdi
    mov r13, rsi
    cmp r13, F_TRANSPOSE
    je .transpose
    cmp r13, F_SUM
    je .sum
    mov rdi, [r12]
    mov rsi, [r12+8]
    call new_value
    test rax, rax
    jz .fail
    mov r14, rax
    mov r15, [r12]
    imul r15, [r12+8]
    xor ebx, ebx
    cmp r13, F_SQRT
    je .sqrt_check
.scalar_loop:
    cmp rbx, r15
    jae .complete
    mov [trace_element], rbx
    mov r10, [r12+V_DATA]
    movsd xmm0, [r10+rbx*8]
    cmp r13, F_SIN
    je .sin
    cmp r13, F_COS
    je .cos
    call math_log
    jmp .scalar_store
.sin:
    call math_sin
    jmp .scalar_store
.cos:
    call math_cos
.scalar_store:
    cmp qword [err_msg], 0
    jne .fail
    mov r10, [r14+V_DATA]
    movsd [r10+rbx*8], xmm0
    inc rbx
    jmp .scalar_loop
.sqrt_check:
    xor ecx, ecx
    pxor xmm1, xmm1
.check_loop:
    cmp rcx, r15
    jae .sqrt_loop
    mov r10, [r12+V_DATA]
    movsd xmm0, [r10+rcx*8]
    ucomisd xmm0, xmm1
    jb .sqrt_error
    inc rcx
    jmp .check_loop
.sqrt_loop:
    mov [trace_element], rbx
    mov rax, r15
    sub rax, rbx
    cmp rax, 2
    jb .sqrt_tail
    pxor xmm0, xmm0
    mov r10, [r12+V_DATA]
    movupd xmm1, [r10+rbx*8]
    OP O_SQRTPD
    mov r10, [r14+V_DATA]
    movupd [r10+rbx*8], xmm0
    add rbx, 2
    jmp .sqrt_loop
.sqrt_tail:
    test rax, rax
    jz .complete
    pxor xmm0, xmm0
    mov r10, [r12+V_DATA]
    movsd xmm1, [r10+rbx*8]
    OP O_SQRTSD
    mov r10, [r14+V_DATA]
    movsd [r10+rbx*8], xmm0
.complete:
    mov rax, r14
    DONE
.transpose:
    call transpose_value
    DONE
.sum:
    mov edi, 1
    mov esi, 1
    call new_value
    test rax, rax
    jz .fail
    mov r14, rax
    mov r15, [r12]
    imul r15, [r12+8]
    xor ebx, ebx
    pxor xmm0, xmm0
.sumloop:
    cmp rbx, r15
    jae .sumdone
    mov [trace_element], rbx
    mov r10, [r12+V_DATA]
    movsd xmm1, [r10+rbx*8]
    OP O_ADDSD
    inc rbx
    jmp .sumloop
.sumdone:
    mov r10, [r14+V_DATA]
    movsd [r10], xmm0
    jmp .complete
.sqrt_error:
    lea rdi, [err_real]
    call set_error
.fail:
    xor eax, eax
    DONE

; v0.4 constructors, named two-dimensional read indexing, and multi-argument calls.
; No empty arrays, slices, implicit expansion, or indexed assignment.
section .text
eval_call:
    FRAME 32
    mov r12, rdi
    mov r13, [r12+N_OP]
    mov rax, [r12+N_ARGC]
    cmp qword [r12+N_TYPE], INDEX
    je .index_arity
    cmp r13, F_LINSPACE
    je .three
    cmp r13, F_ZEROS
    jae .one_or_two
    cmp rax, 1
    jne .arity
    jmp .evaluate
.one_or_two:
    cmp rax, 1
    jb .arity
    cmp rax, 2
    ja .arity
    jmp .evaluate
.three:
    cmp rax, 3
    jne .arity
    jmp .evaluate
.index_arity:
    cmp rax, 2
    jne .arity
.evaluate:
    mov r14, [r12+N_LEFT]
    xor r15d, r15d
.args:
    test r14, r14
    jz .dispatch
    mov rdi, r14
    call eval_node
    test rax, rax
    jz .fail
    cmp qword [err_msg], 0
    jne .fail
    mov [rsp+r15*8], rax
    inc r15
    mov r14, [r14+N_NEXT]
    jmp .args
.dispatch:
    mov rax, [r12+N_ID]
    TRACE_SET trace_node, rax
    mov rax, [r12+N_POS]
    mov [tok_pos], rax
    TRACE_SET trace_element, 0
    TRACE_SET trace_stage, ST_NONE
    TRACE_SET trace_kind, KIND_OUTPUT
    TRACE_SET trace_k, -1
    TRACE_SET trace_lanes, 1
    cmp qword [r12+N_TYPE], INDEX
    je .index
    cmp r13, F_ZEROS
    jb .unary
    cmp r13, F_SIZE
    je .size
    cmp r13, F_LINSPACE
    je .linspace
    mov rdi, rsp
    mov rsi, r15
    mov rdx, r13
    call create_array
    DONE
.unary:
    mov rdi, [rsp]
    mov rsi, r13
    call apply_function
    DONE
.size:
    mov rdi, rsp
    mov rsi, r15
    call size_value
    DONE
.linspace:
    mov rdi, rsp
    call linspace_value
    DONE
.index:
    lea rdi, [r12+N_NAME]
    call find_symbol
    test rax, rax
    jz .unknown
    mov rdi, [rax+S_VALUE]
    mov rsi, [rsp]
    mov rdx, [rsp+8]
    call index_value
    DONE
.unknown:
    lea rdi, [err_unknown]
    jmp .error
.arity:
    lea rdi, [err_arity]
.error:
    call set_error
.fail:
    xor eax, eax
    DONE

; Scalar positive integral dimension/index up to ELEM_CAP; no truncation accepted.
positive_integer:
    cmp qword [rdi], 1
    jne .invalid
    cmp qword [rdi+8], 1
    jne .invalid
    mov rax, [rdi+V_DATA]
    movsd xmm0, [rax]
    cvttsd2si rax, xmm0
    cmp rax, 1
    jl .invalid
    cmp rax, ELEM_CAP
    ja .invalid
    cvtsi2sd xmm1, rax
    ucomisd xmm0, xmm1
    jne .invalid
    jp .invalid
    ret
.invalid:
    xor eax, eax
    ret

create_array:
    FRAME 0
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rdi, [r12]
    call positive_integer
    test rax, rax
    jz .size_error
    mov r15, rax
    cmp r13, 1
    je .allocate
    mov rdi, [r12+8]
    call positive_integer
    test rax, rax
    jz .size_error
.allocate:
    mov rsi, rax
    mov rdi, r15
    call new_value
    test rax, rax
    jz .return
    mov r12, rax
    cmp r14, F_ZEROS
    je .complete
    mov r10, [r12+V_DATA]
    mov rdx, [one]
    cmp r14, F_EYE
    je .identity
    mov rcx, [r12+V_BYTES]
    shr rcx, 3
    xor eax, eax
.fill:
    cmp rax, rcx
    jae .complete
    mov [r10+rax*8], rdx
    inc rax
    jmp .fill
.identity:
    mov rcx, [r12]
    cmp rcx, [r12+8]
    cmova rcx, [r12+8]
    mov rsi, [r12+8]
    inc rsi
    shl rsi, 3
    xor eax, eax
.diagonal:
    cmp rax, rcx
    jae .complete
    mov [r10], rdx
    add r10, rsi
    inc rax
    jmp .diagonal
.complete:
    mov rax, r12
.return:
    DONE
.size_error:
    lea rdi, [err_size]
    call set_error
    xor eax, eax
    DONE

size_value:
    FRAME 0
    mov r12, rdi
    mov r13, rsi
    mov r14, [r12]
    cmp r13, 1
    je .both
    mov rdi, [r12+8]
    call positive_integer
    cmp rax, 1
    jb .index_error
    cmp rax, 2
    ja .index_error
    dec rax
    mov r15, [r14+rax*8]
    mov edi, 1
    mov esi, 1
    call new_value
    test rax, rax
    jz .return
    mov r10, [rax+V_DATA]
    cvtsi2sd xmm0, r15
    movsd [r10], xmm0
    DONE
.both:
    mov edi, 1
    mov esi, 2
    call new_value
    test rax, rax
    jz .return
    mov r10, [rax+V_DATA]
    cvtsi2sd xmm0, qword [r14]
    movsd [r10], xmm0
    cvtsi2sd xmm0, qword [r14+8]
    movsd [r10+8], xmm0
.return:
    DONE
.index_error:
    lea rdi, [err_index]
    call set_error
    xor eax, eax
    DONE

index_value:
    FRAME 0
    mov r12, rdi
    mov r13, rdx
    mov rdi, rsi
    call positive_integer
    test rax, rax
    jz .bad
    cmp rax, [r12]
    ja .bad
    lea r14, [rax-1]
    mov rdi, r13
    call positive_integer
    test rax, rax
    jz .bad
    cmp rax, [r12+8]
    ja .bad
    dec rax
    imul r14, [r12+8]
    add r14, rax
    mov edi, 1
    mov esi, 1
    call new_value
    test rax, rax
    jz .return
    mov r13, rax
    TRACE_SET trace_element, r14
    TRACE_SET trace_stage, ST_INDEX
    TRACE_SET trace_kind, KIND_INPUT
    TRACE_SET trace_lanes, 1
    TRACE_SHAPE r12
    mov r10, [r12+V_DATA]
    movsd xmm1, [r10+r14*8]
    pxor xmm0, xmm0
    OP O_MOVAPD
    mov r10, [r13+V_DATA]
    movsd [r10], xmm0
    mov rax, r13
.return:
    DONE
.bad:
    lea rdi, [err_index]
    call set_error
    xor eax, eax
    DONE

; linspace(a,b,n): row vector, n>=1. n=1 -> b. Exact endpoint bit copies.
; Interior = (1-t)*a + t*b, t=i/(n-1). No b-a overflow for opposite signs.
; Arithmetic/copy instructions below use the same real capture mechanism.
linspace_value:
    FRAME 32
    mov r12, rdi
    mov rax, [r12]
    cmp qword [rax], 1
    jne .scalar
    cmp qword [rax+8], 1
    jne .scalar
    mov rax, [rax+V_DATA]
    mov rax, [rax]
    mov [rsp], rax
    mov rax, [r12+8]
    cmp qword [rax], 1
    jne .scalar
    cmp qword [rax+8], 1
    jne .scalar
    mov rax, [rax+V_DATA]
    mov rax, [rax]
    mov [rsp+8], rax
    mov rdi, [r12+16]
    call positive_integer
    test rax, rax
    jz .size
    mov r14, rax
    mov rsi, rax
    mov edi, 1
    call new_value
    test rax, rax
    jz .return
    mov r12, rax
    TRACE_SHAPE r12
    TRACE_SET trace_kind, KIND_OUTPUT
    TRACE_SET trace_stage, ST_LINSPACE
    TRACE_SET trace_lanes, 1
    mov r15, [rax+V_DATA]
    lea rax, [r14-1]
    cvtsi2sd xmm6, rax
    xor r13d, r13d
.loop:
    TRACE_SET trace_element, r13
    lea rax, [r14-1]
    cmp r13, rax
    je .last
    test r13, r13
    jz .first
    cvtsi2sd xmm0, r13
    movapd xmm1, xmm6
    OP O_DIVSD
    movapd xmm4, xmm0
    movsd xmm0, [one]
    movapd xmm1, xmm4
    OP O_SUBSD
    movsd xmm1, [rsp]
    OP O_MULSD
    movapd xmm5, xmm0
    movapd xmm0, xmm4
    movsd xmm1, [rsp+8]
    OP O_MULSD
    movapd xmm1, xmm5
    OP O_ADDSD
    jmp .store
.first:
    movsd xmm1, [rsp]
    jmp .copy
.last:
    movsd xmm1, [rsp+8]
.copy:
    pxor xmm0, xmm0
    OP O_MOVAPD
.store:
    movsd [r15+r13*8], xmm0
    inc r13
    cmp r13, r14
    jb .loop
    mov rax, r12
.return:
    DONE
.scalar:
    lea rdi, [err_scalar_arg]
    jmp .error
.size:
    lea rdi, [err_size]
.error:
    call set_error
    xor eax, eax
    DONE

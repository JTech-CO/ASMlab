section .text
; First error wins, including a source byte offset. rdi = static message.
set_error:
    cmp qword [err_msg], 0
    jne .done
    mov [err_msg], rdi
    mov rax, [tok_pos]
    mov [err_pos], rax
.done:
    ret

new_node:
    mov rax, [node_count]
    cmp rax, NODE_CAP
    jae .full
    mov rcx, rax
    imul rax, NS
    lea rax, [nodes+rax]
    inc qword [node_count]
    mov [rax+N_ID], rcx
    mov rcx, [tok_pos]
    mov [rax+N_POS], rcx
    ret
.full:
    lea rdi, [err_nodes]
    sub rsp, 8
    call set_error
    add rsp, 8
    xor eax, eax
    ret

; new_value(rows:rdi, cols:rsi) -> rax. Bounded arena, reclaimed each line.
new_value:
    cmp rdi, 1
    jl .size
    cmp rdi, DIM_CAP
    jg .size
    cmp rsi, 1
    jl .size
    cmp rsi, DIM_CAP
    jg .size
    mov rax, [value_count]
    cmp rax, VALUE_CAP
    jae .full
    imul rax, VS
    lea rax, [values+rax]
    inc qword [value_count]
    mov [rax], rdi
    mov [rax+8], rsi
    ret
.size:
    lea rdi, [err_size]
    jmp .error
.full:
    lea rdi, [err_values]
.error:
    sub rsp, 8
    call set_error
    add rsp, 8
    xor eax, eax
    ret

; Find workspace entry, or NULL. Name is NUL-terminated, max 31 bytes.
find_symbol:
    FRAME 0
    mov r12, rdi
    xor ebx, ebx
.loop:
    cmp rbx, [symbol_count]
    jae .missing
    imul rax, rbx, SS
    lea r13, [symbols+rax]
    mov rdi, r12
    mov rsi, r13
    call rt_strcmp
    test eax, eax
    jz .found
    inc rbx
    jmp .loop
.found:
    mov rax, r13
    DONE
.missing:
    xor eax, eax
    DONE

; Atomic deep copy: only called after successful evaluation/finite checks.
store_symbol:
    FRAME 0
    mov r12, rdi
    mov r13, rsi
    call find_symbol
    test rax, rax
    jnz .copy
    mov rax, [symbol_count]
    cmp rax, VAR_CAP
    jae .full
    imul rax, SS
    lea r14, [symbols+rax]
    mov rdi, r14
    mov rsi, r12
    mov edx, 32
    call rt_memcpy
    inc qword [symbol_count]
    mov rax, r14
.copy:
    lea rdi, [rax+32]
    mov rsi, r13
    mov edx, VS
    call rt_memcpy
    DONE
.full:
    lea rdi, [err_symbols]
    call set_error
    xor eax, eax
    DONE

workspace_clear:
    FRAME 0
    lea rdi, [symbols]
    xor esi, esi
    mov edx, VAR_CAP * SS
    call rt_memset
    ; ans always has a reserved workspace slot.
    mov byte [symbols], 'a'
    mov byte [symbols+1], 'n'
    mov byte [symbols+2], 's'
    mov qword [symbols+32], 1
    mov qword [symbols+40], 1
    mov qword [symbol_count], 1
    DONE

expression_reset:
    FRAME 0
    lea rdi, [nodes]
    xor esi, esi
    mov edx, NODE_CAP * NS
    call rt_memset
    mov qword [node_count], 0
    mov qword [value_count], 0
    mov qword [parse_depth], 0
    mov qword [eval_depth], 0
    mov qword [err_msg], 0
    mov qword [err_pos], 0
    mov qword [root_node], 0
    mov qword [result_value], 0
    mov qword [trace_count], 0
    mov qword [trace_total], 0
    mov qword [trace_node], 0
    mov qword [trace_element], 0
    mov qword [tok_pos], 0
    lea rax, [input_buf]
    mov [lex_ptr], rax
    ; Deterministic round-to-nearest; gradual underflow; exceptions masked.
    mov dword [mxcsr_default], 0x1f80
    ldmxcsr [mxcsr_default]
    DONE

; validate all elements finite. Underflow and subnormals are permitted.
validate_value:
    mov rcx, [rdi]
    imul rcx, [rdi+8]
    xor edx, edx
.loop:
    cmp rdx, rcx
    jae .good
    mov rax, [rdi+16+rdx*8]
    shr rax, 52
    and eax, 0x7ff
    cmp eax, 0x7ff
    je .bad
    inc rdx
    jmp .loop
.good:
    mov eax, 1
    ret
.bad:
    lea rdi, [err_nonfinite]
    sub rsp, 8
    call set_error
    add rsp, 8
    xor eax, eax
    ret

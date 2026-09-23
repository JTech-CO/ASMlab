; Dynamic values and transactional workspace. No aliases or copy-on-write.
section .text
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

; Per-expression bump arena. Each chunk is an independently charged mapping.
; Chunk payload: next pointer, capacity, then 16-byte aligned allocations.
temp_alloc:
    FRAME 0
    mov r12, rdi
    add r12, 15
    jc .fail
    and r12, -16
    mov rax, [temp_cursor]
    test rax, rax
    jz .chunk
    mov rdx, rax
    add rdx, r12
    jc .fail
    cmp rdx, [temp_end]
    ja .chunk
    mov [temp_cursor], rdx
    DONE
.chunk:
    lea r13, [r12+16]
    cmp r13, 65536
    jae .allocate
    mov r13d, 65536
.allocate:
    mov rdi, r13
    call rt_heap_alloc
    test rax, rax
    jz .fail
    mov rdx, [temp_head]
    mov [rax], rdx
    mov [rax+8], r13
    mov [temp_head], rax
    lea rdx, [rax+r13]
    mov [temp_end], rdx
    add rax, 16
    lea rdx, [rax+r12]
    mov [temp_cursor], rdx
    DONE
.fail:
    lea rdi, [err_memory]
    call set_error
    xor eax, eax
    DONE

temp_release:
    FRAME 0
    mov r12, [temp_head]
    mov qword [temp_head], 0
    mov qword [temp_cursor], 0
    mov qword [temp_end], 0
.loop:
    test r12, r12
    jz .done
    mov r13, [r12]
    mov rdi, r12
    call rt_heap_free
    mov r12, r13
    jmp .loop
.done:
    mov qword [value_count], 0
    DONE

; Value descriptor {rows,cols,data,bytes,row_stride,dtype,owner,reserved}.
; Allocation includes descriptor+payload, but users follow V_DATA only.
; rows/cols and multiplication are checked before allocating or writing.
value_allocate:
    FRAME 0
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    test r12, r12
    jz .size
    test r13, r13
    jz .size
    mov rax, r12
    mul r13
    test rdx, rdx
    jnz .size
    cmp rax, ELEM_CAP
    ja .size
    shl rax, 3
    mov r15, rax
    lea rdi, [rax+VS]
    cmp r14, OWNER_TEMP
    jne .persistent
    call temp_alloc
    jmp .allocated
.persistent:
    call rt_heap_alloc
.allocated:
    test rax, rax
    jz .memory
    mov [rax], r12
    mov [rax+8], r13
    lea rdi, [rax+VS]
    mov [rax+V_DATA], rdi
    mov [rax+V_BYTES], r15
    lea rdx, [r13*8]
    mov [rax+V_STRIDE], rdx
    mov qword [rax+V_DTYPE], 1
    mov [rax+V_OWNER], r14
    mov qword [rax+V_RESERVED], 0
    mov r12, rax
    xor esi, esi
    mov rdx, r15
    call rt_memset
    mov rax, r12
    DONE
.size:
    lea rdi, [err_size]
    jmp .error
.memory:
    lea rdi, [err_memory]
.error:
    call set_error
    xor eax, eax
    DONE

new_value:
    cmp qword [value_count], VALUE_CAP
    jae .full
    inc qword [value_count]
    mov edx, OWNER_TEMP
    jmp value_allocate
.full:
    lea rdi, [err_values]
    sub rsp, 8
    call set_error
    add rsp, 8
    xor eax, eax
    ret

clone_temp:
    FRAME 0
    mov r12, rdi
    mov rdi, [r12]
    mov rsi, [r12+8]
    call new_value
    jmp clone_persistent.copy
clone_persistent:
    FRAME 0
    mov r12, rdi
    mov rdi, [r12]
    mov rsi, [r12+8]
    mov edx, OWNER_WORKSPACE
    call value_allocate
.copy:
    test rax, rax
    jz .done
    mov r13, rax
    mov rdi, [rax+V_DATA]
    mov rsi, [r12+V_DATA]
    mov rdx, [r12+V_BYTES]
    call rt_memcpy
    mov rax, r13
.done:
    DONE

release_persistent:
    test rdi, rdi
    jz .done
    cmp qword [rdi+V_OWNER], OWNER_WORKSPACE
    je rt_heap_free
.done:
    ret

; Symbols: 32-byte name, owned Value pointer, next symbol pointer.
; ans is the static head. New entries and payloads are quota-accounted.
find_symbol:
    FRAME 0
    mov r12, rdi
    lea r13, [symbols]
.loop:
    test r13, r13
    jz .missing
    mov rdi, r12
    mov rsi, r13
    call rt_strcmp
    test eax, eax
    jz .found
    mov r13, [r13+S_NEXT]
    jmp .loop
.found:
    mov rax, r13
    DONE
.missing:
    xor eax, eax
    DONE

; name=NULL for a pure expression, otherwise target name; rsi=temporary result.
; Stage NEW entry, NEW target copy and NEW ans copy before publishing any of them.
; Existing result/ans/entry counts survive every allocation failure.
workspace_commit:
    FRAME 48
    mov r12, rdi
    mov r13, rsi
    xor r14d, r14d
    mov qword [rsp], 0           ; unpublished entry
    mov qword [rsp+8], 0         ; staged target Value
    mov qword [rsp+16], 0        ; staged ans Value
    mov qword [rsp+24], 0        ; old target Value
    test r12, r12
    jz .stage_ans
    call find_symbol
    mov r14, rax
    test r14, r14
    jnz .stage_target
    mov edi, SS
    call rt_heap_alloc
    test rax, rax
    jz .failure
    mov [rsp], rax
    mov r14, rax
    mov rdi, r14
    mov rsi, r12
    mov edx, 32
    call rt_memcpy
.stage_target:
    mov rdi, r13
    call clone_persistent
    test rax, rax
    jz .failure
    mov [rsp+8], rax
.stage_ans:
    mov rdi, r13
    call clone_persistent
    test rax, rax
    jz .failure
    mov [rsp+16], rax
    ; Commit point: no further allocations, validation, or fallible calculations.
    test r14, r14
    jz .publish_ans
    mov rax, [r14+S_VALUE]
    mov [rsp+24], rax
    mov rax, [rsp+8]
    mov [r14+S_VALUE], rax
    cmp qword [rsp], 0
    je .publish_ans
    mov rax, [symbols+S_NEXT]
    mov [r14+S_NEXT], rax
    mov [symbols+S_NEXT], r14
    inc qword [symbol_count]
.publish_ans:
    mov r15, [symbols+S_VALUE]
    mov rax, [rsp+16]
    mov [symbols+S_VALUE], rax
    mov rdi, [rsp+24]
    call release_persistent
    mov rdi, r15
    call release_persistent
    mov eax, 1
    DONE
.failure:
    lea rdi, [err_memory]
    call set_error
    mov rdi, [rsp+8]
    call release_persistent
    mov rdi, [rsp+16]
    call release_persistent
    mov rdi, [rsp]
    call rt_heap_free
    xor eax, eax
    DONE

; Release all persistent payloads and entries. Reset ans without allocating.
workspace_clear:
    FRAME 0
    mov rdi, [symbols+S_VALUE]
    call release_persistent
    lea rax, [boot_value]
    mov [symbols+S_VALUE], rax
    mov r12, [symbols+S_NEXT]
    mov qword [symbols+S_NEXT], 0
.loop:
    test r12, r12
    jz .done
    mov r13, [r12+S_NEXT]
    mov rdi, [r12+S_VALUE]
    call release_persistent
    mov rdi, r12
    call rt_heap_free
    mov r12, r13
    jmp .loop
.done:
    mov qword [symbol_count], 1
    DONE

workspace_drop:
    FRAME 0
    mov r12, rdi
    lea rsi, [name_ans]
    call rt_strcmp
    test eax, eax
    jz .readonly
    lea r13, [symbols]
.loop:
    mov r14, [r13+S_NEXT]
    test r14, r14
    jz .missing
    mov rdi, r12
    mov rsi, r14
    call rt_strcmp
    test eax, eax
    jz .remove
    mov r13, r14
    jmp .loop
.remove:
    mov rax, [r14+S_NEXT]
    mov [r13+S_NEXT], rax
    mov rdi, [r14+S_VALUE]
    call release_persistent
    mov rdi, r14
    call rt_heap_free
    dec qword [symbol_count]
    mov eax, 1
    DONE
.readonly:
    lea rdi, [err_readonly]
    jmp .error
.missing:
    lea rdi, [err_unknown]
.error:
    call set_error
    xor eax, eax
    DONE

expression_reset:
    FRAME 0
    ; Invalidate every consumer before releasing the previous expression arena.
    mov qword [root_node], 0
    mov qword [result_value], 0
    call temp_release
    lea rdi, [nodes]
    xor esi, esi
    mov edx, NODE_CAP * NS
    call rt_memset
    mov qword [node_count], 0
    mov qword [parse_depth], 0
    mov qword [eval_depth], 0
    mov qword [err_msg], 0
    mov qword [err_pos], 0
    mov qword [trace_count], 0
    mov qword [trace_total], 0
    mov qword [trace_node], 0
    mov qword [trace_element], 0
    mov qword [tok_pos], 0
    lea rax, [input_buf]
    mov [lex_ptr], rax
    mov dword [mxcsr_default], 0x1f80
    ldmxcsr [mxcsr_default]
    DONE

; Finite check over owned contiguous payload, not descriptor bytes.
validate_value:
    mov rcx, [rdi+V_BYTES]
    shr rcx, 3
    mov r8, [rdi+V_DATA]
    xor edx, edx
.loop:
    cmp rdx, rcx
    jae .good
    mov rax, [r8+rdx*8]
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

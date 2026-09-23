; Decimal lexer and Pratt parser. No eval(), compiler, or external parser.
section .text
next_token:
    FRAME 0
    mov r12, [lex_ptr]
.skip:
    movzx eax, byte [r12]
    cmp al, ' '
    je .space
    cmp al, 9
    je .space
    cmp al, 13
    jne .start
.space:
    inc r12
    jmp .skip
.start:
    lea rax, [input_buf]
    mov rcx, r12
    sub rcx, rax
    mov [tok_pos], rcx
    mov qword [tok_name], 0
    mov qword [tok_name+8], 0
    mov qword [tok_name+16], 0
    mov qword [tok_name+24], 0
    movzx eax, byte [r12]
    test al, al
    jz .end
    cmp al, 10
    je .end
    cmp al, '#'
    je .end
    cmp al, '%'
    je .end
    cmp al, '0'
    jb .not_digit
    cmp al, '9'
    jbe .number
.not_digit:
    cmp al, '.'
    jne .identifier_check
    movzx ecx, byte [r12+1]
    cmp cl, '*'
    je .emul
    cmp cl, '/'
    je .ediv
    cmp cl, '0'
    jb .badchar
    cmp cl, '9'
    jbe .number
    jmp .badchar
.emul:
    mov eax, T_EMUL
    add r12, 2
    jmp .store
.ediv:
    mov eax, T_EDIV
    add r12, 2
    jmp .store
.identifier_check:
    cmp al, '_'
    je .identifier
    cmp al, 'A'
    jb .single
    cmp al, 'Z'
    jbe .identifier
    cmp al, 'a'
    jb .single
    cmp al, 'z'
    jbe .identifier
.single:
    cmp al, '+'
    je .single_ok
    cmp al, '-'
    je .single_ok
    cmp al, '*'
    je .single_ok
    cmp al, '/'
    je .single_ok
    cmp al, '^'
    je .single_ok
    cmp al, '('
    je .single_ok
    cmp al, ')'
    je .single_ok
    cmp al, '['
    je .single_ok
    cmp al, ']'
    je .single_ok
    cmp al, ','
    je .single_ok
    cmp al, ';'
    je .single_ok
    cmp al, '='
    je .single_ok
    cmp al, 39
    jne .badchar
.single_ok:
    inc r12
    jmp .store
.identifier:
    mov r13, r12
.id_loop:
    movzx eax, byte [r12]
    cmp al, '_'
    je .id_char
    cmp al, '0'
    jb .id_done
    cmp al, '9'
    jbe .id_char
    cmp al, 'A'
    jb .id_done
    cmp al, 'Z'
    jbe .id_char
    cmp al, 'a'
    jb .id_done
    cmp al, 'z'
    ja .id_done
.id_char:
    inc r12
    jmp .id_loop
.id_done:
    mov rdx, r12
    sub rdx, r13
    cmp rdx, 31
    ja .longname
    lea rdi, [tok_name]
    mov rsi, r13
    call rt_memcpy
    mov eax, T_ID
    jmp .store
.number:
    mov r13, r12
.digits:
    movzx eax, byte [r12]
    cmp al, '0'
    jb .dot
    cmp al, '9'
    ja .dot
    inc r12
    jmp .digits
.dot:
    cmp al, '.'
    jne .exponent
    cmp byte [r12+1], '*'
    je .num_done
    cmp byte [r12+1], '/'
    je .num_done
    inc r12
.fraction:
    movzx eax, byte [r12]
    cmp al, '0'
    jb .exponent
    cmp al, '9'
    ja .exponent
    inc r12
    jmp .fraction
.exponent:
    cmp al, 'e'
    je .exp_start
    cmp al, 'E'
    jne .num_done
.exp_start:
    inc r12
    movzx eax, byte [r12]
    cmp al, '+'
    je .exp_sign
    cmp al, '-'
    jne .exp_digit
.exp_sign:
    inc r12
.exp_digit:
    movzx eax, byte [r12]
    cmp al, '0'
    jb .badnum
    cmp al, '9'
    ja .badnum
.exp_loop:
    inc r12
    movzx eax, byte [r12]
    cmp al, '0'
    jb .num_done
    cmp al, '9'
    jbe .exp_loop
.num_done:
    mov r14, r12
    sub r14, r13
    cmp r14, 127
    ja .badnum
    lea rdi, [num_buf]
    mov rsi, r13
    mov rdx, r14
    call rt_memcpy
    lea rax, [num_buf]
    mov byte [rax+r14], 0
    lea rdi, [num_buf]
    lea rsi, [num_end]
    call rt_decimal_from_cstr
    movq rax, xmm0
    mov rcx, rax
    shr rcx, 52
    and ecx, 0x7ff
    cmp ecx, 0x7ff
    je .badnum
    mov [tok_num], rax
    mov eax, T_NUM
    jmp .store
.longname:
    lea rdi, [err_name]
    jmp .error
.badchar:
    lea rdi, [err_char]
    inc r12
    jmp .error
.badnum:
    lea rdi, [err_number]
.error:
    call set_error
.end:
    xor eax, eax
.store:
    mov [tok_type], rax
    mov [lex_ptr], r12
    DONE

; Resolve the six built-ins. Unknown names return zero, not an error.
lookup_function:
    FRAME 0
    mov r12, rdi
    mov ebx, 1
.loop:
    lea rax, [function_names]
    mov rsi, [rax+rbx*8]
    mov rdi, r12
    call rt_strcmp
    test eax, eax
    jz .found
    inc ebx
    cmp ebx, F_LAST
    jbe .loop
    xor ebx, ebx
.found:
    mov eax, ebx
    DONE

parse_statement:
    FRAME 48
    mov qword [rsp+32], 0
    call next_token
    cmp qword [err_msg], 0
    jne .fail
    cmp qword [tok_type], T_ID
    jne .expression
    ; Look ahead for assignment, otherwise rewind the lexer.
    mov rax, [tok_pos]
    mov [rsp+40], rax
    lea rdi, [rsp]
    lea rsi, [tok_name]
    mov edx, 32
    call rt_memcpy
    call next_token
    cmp qword [tok_type], '='
    jne .rewind
    mov qword [rsp+32], 1
    call next_token
    jmp .expression
.rewind:
    lea rax, [input_buf]
    mov [lex_ptr], rax
    call next_token
.expression:
    xor edi, edi
    call parse_expression
    mov r12, rax
    cmp qword [err_msg], 0
    jne .fail
    cmp qword [tok_type], 0
    jne .extra
    cmp qword [rsp+32], 0
    je .return
    call new_node
    test rax, rax
    jz .fail
    mov r13, rax
    mov qword [r13+N_TYPE], ASSIGN
    mov rax, [rsp+40]
    mov [r13+N_POS], rax
    mov [r13+N_LEFT], r12
    lea rdi, [r13+N_NAME]
    lea rsi, [rsp]
    mov edx, 32
    call rt_memcpy
    mov r12, r13
.return:
    mov rax, r12
    DONE
.extra:
    lea rdi, [err_extra]
    call set_error
.fail:
    xor eax, eax
    DONE

; Pratt binding powers: +/- 10; */.*./ 20; prefix +/- 25; ^ 30; ' 40.
; ^ is right associative. Consequently -2^2 == -4 and 2^-2 == 0.25.
parse_expression:
    FRAME 16
    mov r15, rdi
    inc qword [parse_depth]
    cmp qword [parse_depth], DEPTH_CAP
    ja .depth_error
    cmp qword [err_msg], 0
    jne .fail
    mov rax, [tok_type]
    cmp rax, T_NUM
    je .number
    cmp rax, T_ID
    je .identifier
    cmp rax, '('
    je .group
    cmp rax, '['
    je .matrix
    cmp rax, '+'
    je .prefix
    cmp rax, '-'
    je .prefix
    lea rdi, [err_syntax]
    call set_error
    jmp .fail
.number:
    call new_node
    test rax, rax
    jz .fail
    mov r12, rax
    mov qword [r12+N_TYPE], NUM
    mov rax, [tok_num]
    mov [r12+N_NUM], rax
    call next_token
    jmp .infix
.identifier:
    call new_node
    test rax, rax
    jz .fail
    mov r12, rax
    mov qword [r12+N_TYPE], VAR
    lea rdi, [r12+N_NAME]
    lea rsi, [tok_name]
    mov edx, 32
    call rt_memcpy
    call next_token
    cmp qword [tok_type], '('
    jne .infix
    mov qword [r12+N_TYPE], FUNC
    lea rdi, [r12+N_NAME]
    call lookup_function
    mov [r12+N_OP], rax
    test eax, eax
    jnz .arguments
    mov qword [r12+N_TYPE], INDEX
.arguments:
    mov rdi, r12
    call parse_arguments
    cmp qword [err_msg], 0
    jne .fail
    jmp .infix
.group:
    call next_token
    xor edi, edi
    call parse_expression
    mov r12, rax
    cmp qword [err_msg], 0
    jne .fail
    cmp qword [tok_type], ')'
    jne .paren_error
    call next_token
    jmp .infix
.matrix:
    call parse_matrix
    mov r12, rax
    jmp .infix
.prefix:
    mov r13, rax
    call new_node
    test rax, rax
    jz .fail
    mov r12, rax
    mov qword [r12+N_TYPE], UNARY
    mov [r12+N_OP], r13
    call next_token
    mov edi, 25
    call parse_expression
    mov [r12+N_LEFT], rax
.infix:
    cmp qword [err_msg], 0
    jne .fail
    mov r13, [tok_type]
    cmp r13, 39
    je .transpose
    xor r14d, r14d
    cmp r13, '+'
    je .prec_add
    cmp r13, '-'
    je .prec_add
    cmp r13, '*'
    je .prec_mul
    cmp r13, '/'
    je .prec_mul
    cmp r13, T_EMUL
    je .prec_mul
    cmp r13, T_EDIV
    je .prec_mul
    cmp r13, '^'
    jne .return
    mov r14d, 30
    jmp .binary
.prec_add:
    mov r14d, 10
    jmp .binary
.prec_mul:
    mov r14d, 20
.binary:
    cmp r14, r15
    jb .return
    call new_node
    test rax, rax
    jz .fail
    mov rbx, rax
    mov qword [rbx+N_TYPE], BINARY
    mov [rbx+N_OP], r13
    mov [rbx+N_LEFT], r12
    call next_token
    mov rdi, r14
    cmp r13, '^'
    je .rhs
    inc rdi
.rhs:
    call parse_expression
    mov [rbx+N_RIGHT], rax
    mov r12, rbx
    jmp .infix
.transpose:
    cmp r15, 40
    ja .return
    call new_node
    test rax, rax
    jz .fail
    mov qword [rax+N_TYPE], FUNC
    mov qword [rax+N_OP], F_TRANSPOSE
    mov qword [rax+N_ARGC], 1
    mov [rax+N_LEFT], r12
    mov r12, rax
    call next_token
    jmp .infix
.return:
    mov rax, r12
    dec qword [parse_depth]
    DONE
.unknown_func:
    lea rdi, [err_func]
    jmp .error
.paren_error:
    lea rdi, [err_paren]
    jmp .error
.depth_error:
    lea rdi, [err_depth]
.error:
    call set_error
.fail:
    xor eax, eax
    dec qword [parse_depth]
    DONE

parse_matrix:
    FRAME 16
    call new_node
    test rax, rax
    jz .fail
    mov r13, rax
    mov qword [r13+N_TYPE], MATRIX
    xor ebx, ebx
    xor r14d, r14d
    mov r15d, 1
    mov qword [rsp], 0
    call next_token
.element:
    xor edi, edi
    call parse_expression
    cmp qword [err_msg], 0
    jne .fail
    test rbx, rbx
    jnz .append
    mov [r13+N_LEFT], rax
    jmp .linked
.append:
    mov [rbx+N_NEXT], rax
.linked:
    mov rbx, rax
    inc r14
    cmp r14, DIM_CAP
    ja .size
    mov rax, [tok_type]
    cmp rax, ','
    je .comma
    cmp rax, ';'
    je .endrow
    cmp rax, ']'
    jne .syntax
.endrow:
    cmp qword [rsp], 0
    jne .checkwidth
    mov [rsp], r14
.checkwidth:
    cmp r14, [rsp]
    jne .rect
    cmp qword [tok_type], ']'
    je .complete
    inc r15
    cmp r15, DIM_CAP
    ja .size
    xor r14d, r14d
.comma:
    call next_token
    jmp .element
.complete:
    mov [r13+N_ROWS], r15
    mov rax, [rsp]
    mov [r13+N_COLS], rax
    call next_token
    mov rax, r13
    DONE
.rect:
    lea rdi, [err_rect]
    jmp .error
.size:
    lea rdi, [err_size]
    jmp .error
.syntax:
    lea rdi, [err_matrix]
.error:
    call set_error
.fail:
    xor eax, eax
    DONE

; Parse up to three comma-separated arguments and consume closing parenthesis.
; N_NEXT links argument roots only, not their nested children.
parse_arguments:
    FRAME 0
    mov r12, rdi
    xor r13d, r13d
    xor r14d, r14d
    call next_token
    cmp qword [tok_type], ')'
    je .close
.loop:
    cmp r14, 3
    jae .arity
    xor edi, edi
    call parse_expression
    cmp qword [err_msg], 0
    jne .done
    test rax, rax
    jz .done
    test r13, r13
    jnz .append
    mov [r12+N_LEFT], rax
    jmp .linked
.append:
    mov [r13+N_NEXT], rax
.linked:
    mov r13, rax
    inc r14
    mov [r12+N_ARGC], r14
    cmp qword [tok_type], ','
    je .comma
    cmp qword [tok_type], ')'
    jne .paren
.close:
    call next_token
    jmp .done
.comma:
    call next_token
    jmp .loop
.arity:
    lea rdi, [err_arity]
    jmp .error
.paren:
    lea rdi, [err_paren]
.error:
    call set_error
.done:
    DONE

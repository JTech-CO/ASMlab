; Assembly-only terminal views and capture replay. No browser/JS renderer.
section .rodata
banner: db 'ASMlab 0.1.0 | NASM x86-64 | float64 | SSE2',0
rule: db '--------------------------------------------------------------------------',0
fmt_panel: db 10,'%s',10,0
fmt_panel_color: db 10,27,'[1;36m%s',27,'[0m',10,0
p_ast: db '01 / AST   syntax tree -> evaluated shape',0
p_trace: db '02 / EXECUTION   real instruction + captured XMM state',0
p_result: db '03 / RESULT   float64 workspace value',0
p_workspace: db 'WORKSPACE   persistent values (deep copied on assignment)',0
fmt_input: db 10,'  input  %s',10,0
fmt_astprefix: db '  %*s+- #%03ld ',0
empty: db 0
fmt_astnum: db 'number %.10g',0
fmt_astvar: db 'variable %s',0
fmt_astassign: db 'assign %s',0
fmt_astbin: db 'binary %s',0
fmt_astunary: db 'unary %c',0
fmt_astcall: db 'call %s',0
fmt_astmatrix: db 'matrix literal %ld x %ld',0
fmt_astshape: db '  -> %ld x %ld',10,0
fmt_astnl: db 10,0
ast_omitted: db '  ... remaining AST nodes hidden in replay view; normal output shows the tree.',0
symbol_plus: db '+',0
symbol_minus: db '-',0
symbol_mul: db '* (matrix/scalar)',0
symbol_div: db '/ (scalar divisor)',0
symbol_emul: db '.* (elementwise)',0
symbol_ediv: db './ (elementwise)',0
symbol_pow: db '^ (integer scalar)',0
fmt_trace_head: db 10,'  frame %04ld | node #%03ld | element %ld | active lanes %ld/2',10,0
fmt_instruction: db '  @0x%016lx  %s',10,0
trace_lanes: db '                       lane 0                 lane 1',0
fmt_before: db '  XMM0 before  [ %20.12g | %20.12g ]',10,0
fmt_source: db '  XMM1 source  [ %20.12g | %20.12g ]',10,0
fmt_after: db '  XMM0 after   [ %20.12g | %20.12g ]',10,0
fmt_raw_before: db '  before bits  [ 0x%016lx | 0x%016lx ]',10,0
fmt_raw_source: db '  source bits  [ 0x%016lx | 0x%016lx ]',10,0
fmt_raw_after: db '  after bits   [ 0x%016lx | 0x%016lx ]',10,0
fmt_mxcsr: db '  MXCSR 0x%04lx -> 0x%04lx',10,0
fmt_trace_count: db 10,'  %ld / %ld captured frames shown; %ld watched instructions executed.',10,0
trace_tip: db '  :replay = n/p frame navigation | :trace all = full trace | :bits on = hex',0
trace_off_msg: db '  Trace capture is OFF. :trace on enables it for the next expression.',0
trace_none: db '  No watched arithmetic was required (literal, variable, or identity path).',0
trace_trunc: db '  Capture cap reached: later frames were not retained; computation continued.',0
fmt_result_shape: db '  shape %ld x %ld | float64 | display: 8 significant digits',10,0
fmt_column_block: db '  columns %ld..%ld (zero based)',10,0
fmt_row: db '  %2ld |',0
fmt_cell: db ' %15.8g',0
fmt_newline: db 10,0
fmt_plainnum: db '%.17g',0
fmt_open: db '[',0
fmt_close: db ']',0
fmt_comma: db ', ',0
fmt_semicolon: db '; ',0
fmt_varname: db 10,'  %s',10,0
fmt_error: db 'ERROR at byte %ld: %s',10,0
fmt_error_input: db '  %s',10,'  %*s^',10,0
fmt_json_head: db '{"ok":true,"rows":%ld,"cols":%ld,"data":[',0
fmt_json_comma: db ',',0
fmt_json_end: db ']}',10,0
fmt_json_error: db '{"ok":false,"error":"%s","position":%ld}',10,0
replay_clear: db 27,'[2J',27,'[H',0
replay_caption: db 'CAPTURE REPLAY | precompiled kernels, not JIT or a live debugger',0
replay_prompt: db 10,'  [Enter/n] next  [p] previous  [q] finish  > ',0
replay_unavailable: db 'Replay needs a TTY on stdin and stdout and a successful traced expression.',0
section .bss
ast_draw_count: resq 1
ast_draw_limit: resq 1
last_input: resb INPUT_CAP
section .text
panel:
    mov rsi, rdi
    lea rdi, [fmt_panel]
    cmp qword [color_enabled], 0
    je .plain
    lea rdi, [fmt_panel_color]
.plain:
    xor eax, eax
    jmp printf

render_ast:
    FRAME 0
    lea rdi, [p_ast]
    call panel
    mov qword [ast_draw_count], 0
    mov rdi, [root_node]
    xor esi, esi
    call draw_ast
    DONE

draw_ast:
    FRAME 0
    mov r12, rdi
    mov r13, rsi
    test r12, r12
    jz .done
    mov rax, [ast_draw_count]
    cmp rax, [ast_draw_limit]
    jae .done
    inc qword [ast_draw_count]
    lea rdi, [fmt_astprefix]
    lea rsi, [r13*2]
    lea rdx, [empty]
    mov rcx, [r12+N_ID]
    xor eax, eax
    call printf
    mov rax, [r12+N_TYPE]
    cmp rax, NUM
    je .number
    cmp rax, VAR
    je .variable
    cmp rax, ASSIGN
    je .assign
    cmp rax, BINARY
    je .binary
    cmp rax, UNARY
    je .unary
    cmp rax, MATRIX
    je .matrix
    lea rdi, [fmt_astcall]
    mov rax, [r12+N_OP]
    lea rdx, [function_names]
    mov rsi, [rdx+rax*8]
    jmp .print_label
.number:
    lea rdi, [fmt_astnum]
    movsd xmm0, [r12+N_NUM]
    mov eax, 1
    call printf
    jmp .shape
.variable:
    lea rdi, [fmt_astvar]
    lea rsi, [r12+N_NAME]
    jmp .print_label
.assign:
    lea rdi, [fmt_astassign]
    lea rsi, [r12+N_NAME]
    jmp .print_label
.unary:
    lea rdi, [fmt_astunary]
    mov rsi, [r12+N_OP]
    jmp .print_label
.matrix:
    lea rdi, [fmt_astmatrix]
    mov rsi, [r12+N_ROWS]
    mov rdx, [r12+N_COLS]
    jmp .print_label
.binary:
    lea rsi, [symbol_pow]
    mov rax, [r12+N_OP]
    cmp rax, '+'
    jne .notadd
    lea rsi, [symbol_plus]
.notadd:
    cmp rax, '-'
    jne .notsub
    lea rsi, [symbol_minus]
.notsub:
    cmp rax, '*'
    jne .notmul
    lea rsi, [symbol_mul]
.notmul:
    cmp rax, '/'
    jne .notdiv
    lea rsi, [symbol_div]
.notdiv:
    cmp rax, T_EMUL
    jne .notemul
    lea rsi, [symbol_emul]
.notemul:
    cmp rax, T_EDIV
    jne .notediv
    lea rsi, [symbol_ediv]
.notediv:
    lea rdi, [fmt_astbin]
.print_label:
    xor eax, eax
    call printf
.shape:
    mov rax, [r12+N_VALUE]
    test rax, rax
    jz .noshape
    lea rdi, [fmt_astshape]
    mov rsi, [rax]
    mov rdx, [rax+8]
    xor eax, eax
    call printf
    jmp .children
.noshape:
    lea rdi, [fmt_astnl]
    xor eax, eax
    call printf
.children:
    cmp qword [r12+N_TYPE], MATRIX
    je .matrix_children
    mov rdi, [r12+N_LEFT]
    lea rsi, [r13+1]
    call draw_ast
    mov rdi, [r12+N_RIGHT]
    lea rsi, [r13+1]
    call draw_ast
    jmp .done
.matrix_children:
    mov r14, [r12+N_LEFT]
.matrix_loop:
    test r14, r14
    jz .done
    mov rdi, r14
    lea rsi, [r13+1]
    call draw_ast
    mov r14, [r14+N_NEXT]
    jmp .matrix_loop
.done:
    DONE

; rdi = retained frame index. Decimal and raw bits are from saved registers.
draw_frame:
    FRAME 0
    mov r12, rdi
    imul rax, rdi, TS
    lea r13, [trace_records+rax]
    mov r14, [r13]
    mov r8d, 1
    cmp r14, O_ADDPD
    jb .lanes
    mov r8d, 2
.lanes:
    lea rdi, [fmt_trace_head]
    lea rsi, [r12+1]
    mov rdx, [r13+8]
    mov rcx, [r13+16]
    xor eax, eax
    call printf
    lea rdi, [fmt_instruction]
    mov rsi, [r13+24]
    lea rax, [op_names]
    mov rdx, [rax+r14*8]
    xor eax, eax
    call printf
    SAY trace_lanes
    lea rdi, [fmt_before]
    movsd xmm0, [r13+32]
    movsd xmm1, [r13+40]
    mov eax, 2
    call printf
    lea rdi, [fmt_source]
    movsd xmm0, [r13+48]
    movsd xmm1, [r13+56]
    mov eax, 2
    call printf
    lea rdi, [fmt_after]
    movsd xmm0, [r13+64]
    movsd xmm1, [r13+72]
    mov eax, 2
    call printf
    cmp qword [trace_bits], 0
    je .mxcsr
    lea rdi, [fmt_raw_before]
    mov rsi, [r13+32]
    mov rdx, [r13+40]
    xor eax, eax
    call printf
    lea rdi, [fmt_raw_source]
    mov rsi, [r13+48]
    mov rdx, [r13+56]
    xor eax, eax
    call printf
    lea rdi, [fmt_raw_after]
    mov rsi, [r13+64]
    mov rdx, [r13+72]
    xor eax, eax
    call printf
.mxcsr:
    lea rdi, [fmt_mxcsr]
    mov rsi, [r13+88]
    mov rdx, [r13+80]
    xor eax, eax
    call printf
    DONE

render_trace:
    FRAME 0
    lea rdi, [p_trace]
    call panel
    cmp qword [trace_enabled], 0
    je .off
    cmp qword [trace_count], 0
    je .none
    xor ebx, ebx
.loop:
    cmp rbx, [trace_count]
    jae .count
    cmp rbx, [trace_limit]
    jae .count
    mov rdi, rbx
    call draw_frame
    inc rbx
    jmp .loop
.count:
    lea rdi, [fmt_trace_count]
    mov rsi, rbx
    mov rdx, [trace_count]
    mov rcx, [trace_total]
    xor eax, eax
    call printf
    mov rax, [trace_total]
    cmp rax, [trace_count]
    jbe .tip
    SAY trace_trunc
.tip:
    SAY trace_tip
    DONE
.off:
    SAY trace_off_msg
    DONE
.none:
    SAY trace_none
    DONE

; Complete result, with four-column blocks to avoid very wide matrix rows.
print_value_table:
    FRAME 16
    mov r12, rdi
    lea rdi, [fmt_result_shape]
    mov rsi, [r12]
    mov rdx, [r12+8]
    xor eax, eax
    call printf
    xor r13d, r13d
.block:
    cmp r13, [r12+8]
    jae .done
    lea r14, [r13+4]
    mov rax, [r12+8]
    cmp r14, rax
    cmova r14, rax
    cmp qword [r12+8], 4
    jbe .rows
    lea rdi, [fmt_column_block]
    mov rsi, r13
    lea rdx, [r14-1]
    xor eax, eax
    call printf
.rows:
    xor r15d, r15d
.row:
    cmp r15, [r12]
    jae .nextblock
    lea rdi, [fmt_row]
    mov rsi, r15
    xor eax, eax
    call printf
    mov rbx, r13
.cell:
    cmp rbx, r14
    jae .endrow
    mov rax, r15
    imul rax, [r12+8]
    add rax, rbx
    movsd xmm0, [r12+16+rax*8]
    lea rdi, [fmt_cell]
    mov eax, 1
    call printf
    inc rbx
    jmp .cell
.endrow:
    lea rdi, [fmt_newline]
    xor eax, eax
    call printf
    inc r15
    jmp .row
.nextblock:
    mov r13, r14
    jmp .block
.done:
    DONE

print_value_plain:
    FRAME 0
    mov r12, rdi
    mov r13, [r12]
    imul r13, [r12+8]
    cmp r13, 1
    je .start
    lea rdi, [fmt_open]
    xor eax, eax
    call printf
.start:
    xor ebx, ebx
.loop:
    cmp rbx, r13
    jae .end
    test rbx, rbx
    jz .number
    mov rax, rbx
    xor edx, edx
    div qword [r12+8]
    lea rdi, [fmt_comma]
    test rdx, rdx
    jnz .separator
    lea rdi, [fmt_semicolon]
.separator:
    xor eax, eax
    call printf
.number:
    movsd xmm0, [r12+16+rbx*8]
    lea rdi, [fmt_plainnum]
    mov eax, 1
    call printf
    inc rbx
    jmp .loop
.end:
    cmp r13, 1
    je .newline
    lea rdi, [fmt_close]
    xor eax, eax
    call printf
.newline:
    lea rdi, [fmt_newline]
    xor eax, eax
    call printf
    DONE

print_json:
    FRAME 0
    mov r12, rdi
    lea rdi, [fmt_json_head]
    mov rsi, [r12]
    mov rdx, [r12+8]
    xor eax, eax
    call printf
    mov r13, [r12]
    imul r13, [r12+8]
    xor ebx, ebx
.loop:
    cmp rbx, r13
    jae .done
    test rbx, rbx
    jz .number
    lea rdi, [fmt_json_comma]
    xor eax, eax
    call printf
.number:
    lea rdi, [fmt_plainnum]
    movsd xmm0, [r12+16+rbx*8]
    mov eax, 1
    call printf
    inc rbx
    jmp .loop
.done:
    lea rdi, [fmt_json_end]
    xor eax, eax
    call printf
    DONE

render_error:
    FRAME 0
    cmp qword [json_mode], 0
    jne .json
    lea rdi, [fmt_error]
    mov rsi, [err_pos]
    mov rdx, [err_msg]
    xor eax, eax
    call printf
    lea rdi, [fmt_error_input]
    lea rsi, [input_buf]
    mov rdx, [err_pos]
    lea rcx, [empty]
    xor eax, eax
    call printf
    DONE
.json:
    lea rdi, [fmt_json_error]
    mov rsi, [err_msg]
    mov rdx, [err_pos]
    xor eax, eax
    call printf
    DONE

render_result:
    FRAME 0
    cmp qword [json_mode], 0
    jne .json
    cmp qword [quiet_mode], 0
    jne .quiet
    lea rdi, [fmt_input]
    lea rsi, [last_input]
    xor eax, eax
    call printf
    mov qword [ast_draw_limit], NODE_CAP
    call render_ast
    call render_trace
    cmp qword [trace_step], 0
    je .result
    call replay_trace
.result:
    lea rdi, [p_result]
    call panel
    mov rdi, [result_value]
    call print_value_table
    SAY rule
    DONE
.json:
    mov rdi, [result_value]
    call print_json
    DONE
.quiet:
    mov rdi, [result_value]
    call print_value_plain
    DONE

render_workspace:
    FRAME 0
    lea rdi, [p_workspace]
    call panel
    xor ebx, ebx
.loop:
    cmp rbx, [symbol_count]
    jae .done
    imul rax, rbx, SS
    lea r12, [symbols+rax]
    lea rdi, [fmt_varname]
    mov rsi, r12
    xor eax, eax
    call printf
    lea rdi, [r12+32]
    call print_value_table
    inc rbx
    jmp .loop
.done:
    DONE

replay_trace:
    FRAME 0
    cmp qword [interactive_mode], 0
    je .unavailable
    cmp qword [result_value], 0
    je .unavailable
    cmp qword [trace_count], 0
    je .unavailable
    xor ebx, ebx
.frame:
    lea rdi, [replay_clear]
    xor eax, eax
    call printf
    SAY banner
    SAY replay_caption
    lea rdi, [fmt_input]
    lea rsi, [last_input]
    xor eax, eax
    call printf
    mov qword [ast_draw_limit], 10
    call render_ast
    cmp qword [node_count], 10
    jbe .trace
    SAY ast_omitted
.trace:
    lea rdi, [p_trace]
    call panel
    mov rdi, rbx
    call draw_frame
    lea rdi, [fmt_trace_count]
    lea rsi, [rbx+1]
    mov rdx, [trace_count]
    mov rcx, [trace_total]
    xor eax, eax
    call printf
    lea rdi, [replay_prompt]
    xor eax, eax
    call printf
    xor edi, edi
    call fflush
    lea rdi, [step_buf]
    mov esi, 32
    mov rdx, [stdin]
    call fgets
    test rax, rax
    jz .done
    movzx eax, byte [step_buf]
    cmp al, 'q'
    je .done
    cmp al, 'p'
    je .previous
    cmp al, 'n'
    je .next
    cmp al, 10
    jne .frame
.next:
    lea rax, [rbx+1]
    cmp rax, [trace_count]
    jae .done
    inc rbx
    jmp .frame
.previous:
    test rbx, rbx
    jz .frame
    dec rbx
    jmp .frame
.unavailable:
    SAY replay_unavailable
.done:
    mov qword [ast_draw_limit], NODE_CAP
    DONE

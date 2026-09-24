section .rodata
%ifndef ASMLAB_BUILD_ID
%define ASMLAB_BUILD_ID "untracked"
%endif
source_build_id: db ASMLAB_BUILD_ID,0
section .bss
node_starts: resq NODE_CAP
expression_serial: resq 1
execution_mode: resq 1
last_execution_mode: resq 1
mode_explicit: resq 1
trace_json_mode: resq 1
dispatch_entries: resq 1
trace_stage: resq 1
trace_kind: resq 1
trace_k: resq 1
trace_lanes: resq 1
trace_rows: resq 1
trace_cols: resq 1
workbench_requested: resq 1
wb_active: resq 1
final_mxcsr: resq 1
section .rodata
stage_none: db 'none',0
stage_elementwise: db 'elementwise',0
stage_negate: db 'negate',0
stage_transpose: db 'transpose-copy',0
stage_sqrt: db 'sqrt',0
stage_sum: db 'sum-accumulate',0
stage_dot_product: db 'dot-product',0
stage_dot_accumulate: db 'dot-accumulate',0
stage_dot_reduce: db 'dot-reduce',0
stage_trig_reduce: db 'trig-range-reduction',0
stage_trig_poly: db 'trig-polynomial',0
stage_trig_reconstruct: db 'trig-reconstruct',0
stage_log_normalize: db 'log-normalize',0
stage_log_transform: db 'log-transform',0
stage_log_poly: db 'log-polynomial',0
stage_log_reconstruct: db 'log-reconstruct',0
stage_power: db 'power-by-squaring',0
stage_linspace: db 'linspace-sample',0
stage_index: db 'index-read',0
stage_names: dq stage_none,stage_elementwise,stage_negate,stage_transpose,stage_sqrt,stage_sum
             dq stage_dot_product,stage_dot_accumulate,stage_dot_reduce,stage_trig_reduce,stage_trig_poly
             dq stage_trig_reconstruct,stage_log_normalize,stage_log_transform,stage_log_poly,stage_log_reconstruct
             dq stage_power,stage_linspace,stage_index
kind_names: dq kind_none,kind_output,kind_input,kind_matmul
kind_none: db 'none',0
kind_output: db 'output-element',0
kind_input: db 'input-element',0
kind_matmul: db 'matmul-output',0
node_type_names: dq type_none,type_num,type_var,type_bin,type_unary,type_call,type_mat,type_assign,type_index
type_none: db 'none',0
type_num: db 'number',0
type_var: db 'variable',0
type_bin: db 'binary',0
type_unary: db 'unary',0
type_call: db 'call',0
type_mat: db 'matrix',0
type_assign: db 'assign',0
type_index: db 'index',0
j_open: db '{"schema_version":2,"format":"asmlab.trace","ok":true,"isa":"x86_64","backend":"sse2","build_id":',0
j_mode: db ',"mode":"%s","expression_id":%ld,"source":',0
j_capture: db ',"capture":{"policy":"prefix","capacity":8192,"retained":%ld,"executed_watched":%ld,"dropped":%ld,"dispatcher_entries":%ld},',0
j_compute_capture: db ',"capture":{"policy":"disabled-compute","capacity":8192,"retained":0,"executed_watched":null,"dropped":0,"dispatcher_entries":0},',0
j_fp: db '"evaluation_mxcsr":"0x1f80","final_mxcsr":"0x%04lx","nodes":[',0
j_node: db '{"id":%ld,"type":"%s","anchor":%ld,"span":[%ld,%ld],"label":',0
j_shape: db ',"shape":[%ld,%ld],"children":[',0
j_child: db '%ld',0
j_node_end: db ']}',0
j_events: db '],"events":[',0
j_event: db '{"sequence":%ld,"expression_id":%ld,"node":%ld,"span":[%ld,%ld],',0
j_stage: db '"stage":"%s","context":{"kind":"%s","element":%ld,"k":%ld,',0
j_coord: db '"row":%ld,"col":%ld,"rows":%ld,"cols":%ld},',0
j_instr: db '"instruction":{"pc":"0x%016lx","opcode":"%s","destination":"XMM0","sources":["XMM0","XMM1"]},',0
j_lanes: db '"lanes":{"hardware":%ld,"active":%ld},"before":["0x%016lx","0x%016lx"],',0
j_operands: db '"source":["0x%016lx","0x%016lx"],"after":["0x%016lx","0x%016lx"],',0
j_mxcsr: db '"mxcsr_before":"0x%04lx","mxcsr_after":"0x%04lx"}',0
j_result: db '],"result":',0
j_end: db '}',10,0
j_quote: db '"',0
j_char: db '%c',0
j_escape: db '\u%04lx',0
j_error: db '{"schema_version":2,"format":"asmlab.trace","ok":false,"expression_id":%ld,"source":',0
j_error_message: db ',"error":',0
j_error_tail: db ',"position":%ld,"snapshot_available":false}',10,0
j_unavailable: db '{"schema_version":2,"ok":false,"error":"No successful expression snapshot is available."}',0
j_label_num: db '%.17g',0
j_label_op: db '%c',0
j_comma: db ',',0
section .text
; Postorder span union. Error anchor N_POS is untouched; spans include children.
trace_prepare_spans:
    FRAME 0
    mov r12, rdi
    test r12, r12
    jz .done
    mov rdi, [r12+N_LEFT]
    call .child
    cmp qword [r12+N_TYPE], MATRIX
    je .siblings
    cmp qword [r12+N_TYPE], FUNC
    je .siblings
    cmp qword [r12+N_TYPE], INDEX
    je .siblings
    mov rdi, [r12+N_RIGHT]
    call .child
    jmp .done
.siblings:
    mov r14, [r12+N_LEFT]
.loop:
    test r14, r14
    jz .done
    mov r14, [r14+N_NEXT]
    mov rdi, r14
    call .child
    jmp .loop
.child:
    test rdi, rdi
    jz .nochild
    push rbx
    mov rbx, rdi
    call trace_prepare_spans
    mov rax, [rbx+N_ID]
    mov rdx, [node_starts+rax*8]
    mov rcx, [r12+N_ID]
    cmp rdx, [node_starts+rcx*8]
    jae .end
    mov [node_starts+rcx*8], rdx
.end:
    mov rdx, [rbx+N_END]
    cmp rdx, [r12+N_END]
    jbe .pop
    mov [r12+N_END], rdx
.pop:
    pop rbx
.nochild:
    ret
.done:
    DONE

; Trusted integer/float formats only. Source/identifier text is always escaped.
trace_json_string:
    FRAME 0
    mov r12, rdi
    lea rdi, [j_quote]
    xor eax, eax
    call rt_console_format
.loop:
    movzx esi, byte [r12]
    test esi, esi
    jz .end
    inc r12
    cmp esi, 32
    jb .escape
    cmp esi, '"'
    je .escape
    cmp esi, 92
    je .escape
    lea rdi, [j_char]
    jmp .emit
.escape:
    lea rdi, [j_escape]
.emit:
    xor eax, eax
    call rt_console_format
    jmp .loop
.end:
    lea rdi, [j_quote]
    xor eax, eax
    call rt_console_format
    DONE

trace_export:
    FRAME 16
    cmp qword [result_value], 0
    je .unavailable
    lea rdi, [j_open]
    xor eax, eax
    call rt_console_format
    lea rdi, [source_build_id]
    call trace_json_string
    lea rsi, [mode_observe]
    cmp qword [last_execution_mode], 0
    je .mode
    lea rsi, [mode_compute]
.mode:
    lea rdi, [j_mode]
    mov rdx, [expression_serial]
    xor eax, eax
    call rt_console_format
    lea rdi, [last_input]
    call trace_json_string
    cmp qword [last_execution_mode], 0
    jne .compute
    lea rdi, [j_capture]
    mov rsi, [trace_count]
    mov rdx, [trace_total]
    mov rcx, rdx
    sub rcx, rsi
    mov r8, [dispatch_entries]
    xor eax, eax
    call rt_console_format
    jmp .fp
.compute:
    lea rdi, [j_compute_capture]
    xor eax, eax
    call rt_console_format
.fp:
    lea rdi, [j_fp]
    mov rsi, [final_mxcsr]
    xor eax, eax
    call rt_console_format
    xor ebx, ebx
.nodes:
    cmp rbx, [node_count]
    jae .events
    test rbx, rbx
    jz .node
    lea rdi, [j_comma]
    xor eax, eax
    call rt_console_format
.node:
    imul r12, rbx, NS
    lea r12, [nodes+r12]
    lea rdi, [j_node]
    mov rsi, rbx
    mov rax, [r12+N_TYPE]
    mov rdx, [node_type_names+rax*8]
    mov rcx, [r12+N_POS]
    mov r8, [node_starts+rbx*8]
    mov r9, [r12+N_END]
    xor eax, eax
    call rt_console_format
    mov rax, [r12+N_TYPE]
    cmp rax, VAR
    je .name
    cmp rax, ASSIGN
    je .name
    cmp rax, INDEX
    je .name
    cmp rax, FUNC
    je .function
    cmp rax, NUM
    je .number
    cmp rax, BINARY
    je .operator
    cmp rax, UNARY
    je .operator
    lea rdi, [empty]
    call trace_json_string
    jmp .shape
 .operator:
    mov rdi, [r12+N_OP]
    call binary_symbol
    mov rdi, rax
    call trace_json_string
    jmp .shape
.function:
    mov rax, [r12+N_OP]
    mov rdi, [function_names+rax*8]
    call trace_json_string
    jmp .shape
.name:
    lea rdi, [r12+N_NAME]
    call trace_json_string
    jmp .shape
.number:
    ; JSON labels are text; numerical results remain typed in result.data.
    lea rdi, [j_quote]
    xor eax, eax
    call rt_console_format
    lea rdi, [j_label_num]
    movsd xmm0, [r12+N_NUM]
    mov eax, 1
    call rt_console_format
    lea rdi, [j_quote]
    xor eax, eax
    call rt_console_format
.shape:
    mov rax, [r12+N_VALUE]
    xor esi, esi
    xor edx, edx
    test rax, rax
    jz .shape_print
    mov rsi, [rax]
    mov rdx, [rax+8]
.shape_print:
    lea rdi, [j_shape]
    xor eax, eax
    call rt_console_format
    mov r14, [r12+N_LEFT]
    test r14, r14
    jz .node_end
    lea rdi, [j_child]
    mov rsi, [r14+N_ID]
    xor eax, eax
    call rt_console_format
    cmp qword [r12+N_TYPE], MATRIX
    je .list
    cmp qword [r12+N_TYPE], FUNC
    je .list
    cmp qword [r12+N_TYPE], INDEX
    je .list
    mov r14, [r12+N_RIGHT]
    test r14, r14
    jz .node_end
    call .child_print
    jmp .node_end
.list:
    mov r14, [r14+N_NEXT]
    test r14, r14
    jz .node_end
    call .child_print
    jmp .list
.child_print:
    sub rsp, 8
    lea rdi, [j_comma]
    xor eax, eax
    call rt_console_format
    lea rdi, [j_child]
    mov rsi, [r14+N_ID]
    xor eax, eax
    call rt_console_format
    add rsp, 8
    ret
.node_end:
    lea rdi, [j_node_end]
    xor eax, eax
    call rt_console_format
    inc rbx
    jmp .nodes
.events:
    lea rdi, [j_events]
    xor eax, eax
    call rt_console_format
    xor ebx, ebx
.event_loop:
    cmp rbx, [trace_count]
    jae .result
    test rbx, rbx
    jz .event
    lea rdi, [j_comma]
    xor eax, eax
    call rt_console_format
.event:
    imul r12, rbx, TS
    lea r12, [trace_records+r12]
    lea rdi, [j_event]
    mov rsi, [r12+TR_SEQ]
    mov rdx, [r12+TR_EXPR]
    mov rcx, [r12+8]
    mov r8, [r12+TR_START]
    mov r9, [r12+TR_END]
    xor eax, eax
    call rt_console_format
    lea rdi, [j_stage]
    mov rax, [r12+TR_STAGE]
    mov rsi, [stage_names+rax*8]
    mov rax, [r12+TR_KIND]
    mov rdx, [kind_names+rax*8]
    mov rcx, [r12+16]
    mov r8, [r12+TR_K]
    xor eax, eax
    call rt_console_format
    mov rax, [r12+16]
    xor edx, edx
    mov rcx, [r12+TR_COLS]
    test rcx, rcx
    jz .unknown_coord
    div rcx
    mov rsi, rax
    jmp .coord
.unknown_coord:
    mov rsi, -1
    mov rdx, -1
.coord:
    lea rdi, [j_coord]
    mov rcx, [r12+TR_ROWS]
    mov r8, [r12+TR_COLS]
    xor eax, eax
    call rt_console_format
    lea rdi, [j_instr]
    mov rsi, [r12+24]
    mov rax, [r12]
    mov rdx, [op_names+rax*8]
    xor eax, eax
    call rt_console_format
    lea rdi, [j_lanes]
    mov rsi, [r12+TR_HWLANES]
    mov rdx, [r12+TR_ACTIVE]
    mov rcx, [r12+32]
    mov r8, [r12+40]
    xor eax, eax
    call rt_console_format
    lea rdi, [j_operands]
    mov rsi, [r12+48]
    mov rdx, [r12+56]
    mov rcx, [r12+64]
    mov r8, [r12+72]
    xor eax, eax
    call rt_console_format
    lea rdi, [j_mxcsr]
    mov rsi, [r12+88]
    mov rdx, [r12+80]
    xor eax, eax
    call rt_console_format
    inc rbx
    jmp .event_loop
.result:
    lea rdi, [j_result]
    xor eax, eax
    call rt_console_format
    mov rdi, [result_value]
    call print_json_inline
    lea rdi, [j_end]
    xor eax, eax
    call rt_console_format
    DONE
.unavailable:
    SAY j_unavailable
    DONE

; Returns an operation's static label; no formatting or numerical work.
binary_symbol:
    lea rax, [symbol_pow]
    cmp rdi, '+'
    je .add
    cmp rdi, '-'
    je .sub
    cmp rdi, '*'
    je .mul
    cmp rdi, '/'
    je .div
    cmp rdi, T_EMUL
    je .emul
    cmp rdi, T_EDIV
    je .ediv
    ret
.add: lea rax, [symbol_plus]
    ret
.sub: lea rax, [symbol_minus]
    ret
.mul: lea rax, [symbol_mul]
    ret
.div: lea rax, [symbol_div]
    ret
.emul: lea rax, [symbol_emul]
    ret
.ediv: lea rax, [symbol_ediv]
    ret

trace_export_error:
    FRAME 0
    lea rdi, [j_error]
    mov rsi, [expression_serial]
    xor eax, eax
    call rt_console_format
    lea rdi, [input_buf]
    call trace_json_string
    lea rdi, [j_error_message]
    xor eax, eax
    call rt_console_format
    mov rdi, [err_msg]
    call trace_json_string
    lea rdi, [j_error_tail]
    mov rsi, [err_pos]
    xor eax, eax
    call rt_console_format
    DONE

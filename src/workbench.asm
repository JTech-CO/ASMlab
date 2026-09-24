; Observable Workbench: an optional single-threaded native TUI, no ncurses/libc.
; A cell buffer clips every write. Captured state is read, never recalculated for display.
section .rodata
wb_unavailable: db 'Workbench requires native Linux x86-64 and TTY stdin/stdout (not --json/--quiet).',0
%ifdef ASMLAB_LIBC_REFERENCE
section .text
wb_run:
    lea rdi, [wb_unavailable]
    jmp rt_console_puts
%else
%define WB_STRIDE 200
%define WB_MAX_ROWS 64
%define WB_HISTORY_CAP 64
%define KEY_UP 256
%define KEY_DOWN 257
%define KEY_RIGHT 258
%define KEY_LEFT 259
%define KEY_HOME 260
%define KEY_END 261
%define KEY_PGUP 262
%define KEY_PGDN 263
%define KEY_DELETE 264
section .rodata
wb_home: db 27,'[H',0
wb_clear: db 27,'[2J',27,'[H',0
wb_crlf: db 13,10,0
wb_title: db 'ASMlab 0.5.0 / OBSERVABLE WORKBENCH',0
wb_next: db '  NEXT: ',0
wb_runmode: db '  LAST: ',0
wb_source: db 'SOURCE ',0
wb_welcome: db 'e: enter an expression. Example: sqrt([1,4,9,16])+2',0
wb_ast_title: db 'AST / completed node values',0
wb_event_title: db 'INSTRUCTIONS  ',0
wb_node_title: db 'node #',0
wb_bytes_title: db '  bytes ',0
wb_arrow: db '>',0
wb_blank: db ' ',0
wb_sep: db ' | ',0
wb_colon: db ': ',0
wb_dash: db '-',0
wb_hash: db '#',0
wb_slash: db '/',0
wb_x: db 'x',0
wb_dot: db '..',0
wb_open: db ' [',0
wb_close: db ']',0
wb_arrow_to: db ' -> ',0
wb_plus: db '+',0
wb_star: db '*',0
wb_power: db '^',0
wb_emul: db '.*',0
wb_ediv: db './',0
wb_regs_title: db 'REGISTERS / captured bits and values',0
wb_pc: db 'PC ',0
wb_xmm0: db 'XMM0 in  ',0
wb_xmm1: db 'XMM1 src ',0
wb_after: db 'XMM0 out ',0
wb_mxcsr: db 'MXCSR ',0
wb_lanes: db '  lanes ',0
wb_hexprefix: db '0x',0
wb_compute_note: db 'COMPUTE snapshot: no captured instructions.',0
wb_noevents: db 'No observed arithmetic for this node/run.',0
wb_novalue: db 'No completed value. e to evaluate; q returns.',0
wb_value_title: db 'VALUE node #',0
wb_final_title: db '  FINAL ',0
wb_value_note: db '  (completed node value; not a partial accumulator)',0
wb_row: db 'r',0
wb_col: db ' c',0
wb_captured: db ' kept/',0
wb_total: db ' executed; ',0
wb_dropped: db ' dropped',0
wb_context: db '  elem ',0
wb_k: db ' k ',0
wb_help: db 'Tab focus | arrows move | PgUp/Dn | g/G ends | / search | f next | b bits | e edit | m mode | c clear | q back',0
wb_focus_events: db 'FOCUS instructions. Enter/n next, p previous; / searches opcode or algorithm stage.',0
wb_focus_ast: db 'FOCUS AST. Up/Down selects a node and its first retained instruction. Tab: result.',0
wb_focus_result: db 'FOCUS value. Arrows scroll rows/columns; Home/End jump. Coordinates shown here are 1-based.',0
wb_edit_label: db 'EDIT > ',0
wb_search_label: db 'FIND > ',0
wb_editor_help: db 'Enter submit | Esc cancel | Up/Down history | Left/Right edit | Ctrl-U clear',0
wb_search_help: db 'Case-sensitive opcode / stage substring. Enter search; Esc cancel; f finds next.',0
wb_notfound: db 'No matching retained instruction. Search never invents missing captures.',0
wb_history_note: db 'History recalls SOURCE for a NEW execution; it does not restore an old workspace.',0
wb_capacity_note: db 'Input capacity reached (expression 4095 / search 63). Extra bytes not inserted.',0
wb_command_note: db 'Use expressions here. Colon commands remain available in the classic REPL (q).',0
wb_clear_note: db 'Workspace cleared; expression snapshot invalidated. History contains source text only.',0
wb_size_note: db 'Need 80x24 minimum. Resize; q exits.',0
wb_mode_note: db 'Mode changed for NEXT execution only. Existing captured evidence is unchanged.',0
wb_expr_note: db 'New execution complete. Select an instruction to link AST, registers, and value.',0
wb_fault_note: db 'Terminal I/O failed; restoring terminal state.',0
wb_space: db ' ',0
wb_cursor_label: db "cursor ",0
section .bss
alignb 16
wb_cells: resb WB_STRIDE * WB_MAX_ROWS
wb_output: resb (WB_STRIDE+2) * WB_MAX_ROWS
wb_num: resb 128
wb_columns: resq 1
wb_rows: resq 1
wb_actual_columns: resq 1
wb_actual_rows: resq 1
wb_dirty: resq 1
wb_position: resq 1
wb_remaining: resq 1
wb_left: resq 1
wb_right: resq 1
wb_listrows: resq 1
wb_resultrow: resq 1
wb_focus: resq 1
wb_event: resq 1
wb_event_top: resq 1
wb_tree_count: resq 1
wb_tree_index: resq 1
wb_tree_top: resq 1
wb_tree: resq NODE_CAP*2
wb_selected_node: resq 1
wb_row_offset: resq 1
wb_col_offset: resq 1
wb_notice: resq 1
wb_editing: resq 1
wb_edit_len: resq 1
wb_edit_cursor: resq 1
wb_edit: resb INPUT_CAP
wb_draft: resb INPUT_CAP
wb_search: resb 64
wb_history: resb WB_HISTORY_CAP*INPUT_CAP
wb_history_count: resq 1
wb_history_next: resq 1
wb_history_position: resq 1
wb_key_saved: resq 1
wb_exit_signal: resq 1
wb_seq: resb 16
section .text
%macro AT 3
    mov rdi, %1
    mov rsi, %2
    mov rdx, %3
    call wb_at
%endmacro
%macro TEXT 1
    lea rdi, [%1]
    call wb_put
%endmacro
%macro UINT 1
    mov rdi, %1
    call wb_uint
%endmacro
%macro SINT 1
    mov rdi, %1
    call wb_sint
%endmacro
; All output is ASCII; one cell = one byte. Rightmost terminal column is unused.
wb_at:
    xor eax, eax
    mov [wb_remaining], rax
    cmp rdi, [wb_rows]
    jae .done
    cmp rsi, [wb_columns]
    jae .done
    imul rax, rdi, WB_STRIDE
    add rax, rsi
    mov [wb_position], rax
    mov rcx, [wb_columns]
    sub rcx, rsi
    cmp rdx, rcx
    cmova rdx, rcx
    mov [wb_remaining], rdx
.done:
    ret
wb_put:
    mov rax, [wb_position]
    mov rcx, [wb_remaining]
.loop:
    test rcx, rcx
    jz .done
    mov dl, [rdi]
    test dl, dl
    jz .done
    inc rdi
    ; Do not interpret source strings as terminal controls.
    cmp dl, 32
    jb .space
    cmp dl, 127
    jb .store
.space:
    mov dl, ' '
.store:
    mov [wb_cells+rax], dl
    inc rax
    dec rcx
    jmp .loop
.done:
    mov [wb_position], rax
    mov [wb_remaining], rcx
    ret
wb_char:
    mov rax, [wb_position]
    cmp qword [wb_remaining], 0
    je .done
    mov [wb_cells+rax], dil
    inc qword [wb_position]
    dec qword [wb_remaining]
.done:
    ret
wb_uint:
    sub rsp, 8
    mov rdx, rdi
    lea rdi, [wb_num]
    mov esi, 128
    call rt_format_u64
    lea rdi, [wb_num]
    call wb_put
    add rsp, 8
    ret
wb_sint:
    sub rsp, 8
    mov rdx, rdi
    lea rdi, [wb_num]
    mov esi, 128
    call rt_format_i64
    lea rdi, [wb_num]
    call wb_put
    add rsp, 8
    ret
wb_hex:
    sub rsp, 8
    mov rdx, rdi
    lea rdi, [wb_num]
    mov esi, 128
    call rt_format_hex64
    lea rdi, [wb_hexprefix]
    call wb_put
    lea rdi, [wb_num]
    call wb_put
    add rsp, 8
    ret
wb_float:
    sub rsp, 8
    mov rdx, rdi
    lea rdi, [wb_num]
    mov esi, 128
    mov ecx, 8
    call rt_format_f64
    lea rdi, [wb_num]
    call wb_put
    add rsp, 8
    ret

wb_build_tree:
    FRAME 0
    mov qword [wb_tree_count], 0
    mov rdi, [root_node]
    xor esi, esi
    call wb_tree_walk
    DONE
wb_tree_walk:
    FRAME 0
    mov r12, rdi
    mov r13, rsi
    test r12, r12
    jz .done
    mov rax, [wb_tree_count]
    cmp rax, NODE_CAP
    jae .done
    inc qword [wb_tree_count]
    shl rax, 4
    mov [wb_tree+rax], r12
    mov [wb_tree+rax+8], r13
    mov rdi, [r12+N_LEFT]
    lea rsi, [r13+1]
    call wb_tree_walk
    mov rax, [r12+N_TYPE]
    cmp rax, FUNC
    je .list
    cmp rax, INDEX
    je .list
    cmp rax, MATRIX
    je .list
    mov rdi, [r12+N_RIGHT]
    lea rsi, [r13+1]
    call wb_tree_walk
    jmp .done
.list:
    mov r14, [r12+N_LEFT]
.loop:
    test r14, r14
    jz .done
    mov r14, [r14+N_NEXT]
    mov rdi, r14
    lea rsi, [r13+1]
    call wb_tree_walk
    jmp .loop
.done:
    DONE

; Choose a real retained frame and link the matching AST node.
wb_select_event:
    FRAME 0
    cmp qword [trace_count], 0
    je .none
    xor eax, eax
    test rdi, rdi
    cmovs rdi, rax
    mov rax, [trace_count]
    dec rax
    cmp rdi, rax
    cmova rdi, rax
    mov [wb_event], rdi
    imul rax, rdi, TS
    mov rdx, [trace_records+rax+8]
    mov [wb_selected_node], rdx
    xor ebx, ebx
.find:
    cmp rbx, [wb_tree_count]
    jae .scroll
    mov rax, rbx
    shl rax, 4
    mov rax, [wb_tree+rax]
    cmp [rax+N_ID], rdx
    je .found
    inc rbx
    jmp .find
.found:
    mov [wb_tree_index], rbx
.scroll:
    mov qword [wb_row_offset], 0
    mov qword [wb_col_offset], 0
    call wb_scroll_selection
    DONE
.none:
    mov qword [wb_event], -1
    DONE
wb_select_node:
    FRAME 0
    cmp qword [wb_tree_count], 0
    je .done
    mov rax, [wb_tree_index]
    shl rax, 4
    mov rax, [wb_tree+rax]
    mov rdx, [rax+N_ID]
    mov [wb_selected_node], rdx
    mov qword [wb_event], -1
    xor ebx, ebx
.loop:
    cmp rbx, [trace_count]
    jae .scroll
    imul rax, rbx, TS
    cmp [trace_records+rax+8], rdx
    je .found
    inc rbx
    jmp .loop
.found:
    mov [wb_event], rbx
.scroll:
    mov qword [wb_row_offset], 0
    mov qword [wb_col_offset], 0
    call wb_scroll_selection
.done:
    DONE
wb_scroll_selection:
    mov rax, [wb_event]
    cmp rax, 0
    jl .ast
    cmp rax, [wb_event_top]
    jae .after_top
    mov [wb_event_top], rax
.after_top:
    mov rcx, [wb_listrows]
    cmp rcx, 1
    jae .list_ok
    mov ecx, 4
.list_ok:
    mov rdx, [wb_event_top]
    add rdx, rcx
    cmp rax, rdx
    jb .ast
    sub rax, rcx
    inc rax
    mov [wb_event_top], rax
.ast:
    mov rax, [wb_tree_index]
    cmp rax, [wb_tree_top]
    jae .ast_end
    mov [wb_tree_top], rax
.ast_end:
    mov rcx, [wb_rows]
    sub rcx, 13
    cmp rcx, 1
    jge .ast_height
    mov ecx, 8
.ast_height:
    mov rdx, [wb_tree_top]
    add rdx, rcx
    cmp rax, rdx
    jb .done
    sub rax, rcx
    inc rax
    mov [wb_tree_top], rax
.done:
    mov qword [wb_dirty], 1
    ret
wb_refresh_snapshot:
    FRAME 0
    mov qword [wb_event_top], 0
    mov qword [wb_tree_top], 0
    mov qword [wb_tree_index], 0
    mov qword [wb_selected_node], 0
    mov qword [wb_row_offset], 0
    mov qword [wb_col_offset], 0
    mov qword [wb_event], -1
    call wb_build_tree
    cmp qword [trace_count], 0
    je .node
    xor edi, edi
    call wb_select_event
    jmp .done
.node:
    call wb_select_node
.done:
    mov qword [wb_dirty], 1
    DONE

wb_node_label:
    FRAME 0
    mov r12, rdi
    mov rax, [r12+N_TYPE]
    cmp rax, NUM
    je .num
    cmp rax, VAR
    je .name
    cmp rax, ASSIGN
    je .name
    cmp rax, INDEX
    je .name
    cmp rax, FUNC
    je .fn
    cmp rax, MATRIX
    je .mat
    mov rdi, [r12+N_OP]
    cmp rdi, T_EMUL
    je .emul
    cmp rdi, T_EDIV
    je .ediv
    call wb_char
    jmp .done
.emul:
    TEXT wb_emul
    jmp .done
.ediv:
    TEXT wb_ediv
    jmp .done
.num:
    mov rdi, [r12+N_NUM]
    call wb_float
    jmp .done
.name:
    lea rdi, [r12+N_NAME]
    call wb_put
    jmp .done
.fn:
    mov rax, [r12+N_OP]
    mov rdi, [function_names+rax*8]
    call wb_put
    jmp .done
.mat:
    mov rdi, [node_type_names+MATRIX*8]
    call wb_put
.done:
    DONE

wb_render:
    FRAME 32
    lea rdi, [wb_cells]
    mov esi, ' '
    mov edx, WB_STRIDE*WB_MAX_ROWS
    call rt_memset
    AT 0,0,[wb_columns]
    TEXT wb_title
    TEXT wb_next
    lea rdi, [mode_observe]
    cmp qword [execution_mode], 0
    je .next_mode
    lea rdi, [mode_compute]
.next_mode:
    call wb_put
    TEXT wb_runmode
    lea rdi, [mode_observe]
    cmp qword [last_execution_mode], 0
    je .last_mode
    lea rdi, [mode_compute]
.last_mode:
    call wb_put
    TEXT wb_hash
    UINT [expression_serial]
    cmp qword [wb_actual_columns], 80
    jb .small
    cmp qword [wb_actual_rows], 24
    jb .small
    AT 1,0,[wb_columns]
    TEXT wb_source
    cmp byte [last_input], 0
    je .welcome
    lea rdi, [last_input]
    ; Source viewport follows the selected token rather than always showing column0.
    cmp qword [root_node], 0
    je .source_emit
    mov rax, [wb_selected_node]
    mov rax, [node_starts+rax*8]
    cmp rax, 16
    jb .source_emit
    sub rax, 16
    add rdi, rax
.source_emit:
    call wb_put
    jmp .header2
.welcome:
    TEXT wb_welcome
.header2:
    AT 2,0,[wb_columns]
    cmp qword [root_node], 0
    je .header_empty
    TEXT wb_node_title
    UINT [wb_selected_node]
    TEXT wb_bytes_title
    mov rax, [wb_selected_node]
    UINT [node_starts+rax*8]
    TEXT wb_dot
    mov rax, [wb_selected_node]
    imul rax, NS
    UINT [nodes+rax+N_END]
    TEXT wb_sep
    UINT [trace_count]
    TEXT wb_captured
    UINT [trace_total]
    TEXT wb_total
    mov rdi, [trace_total]
    sub rdi, [trace_count]
    call wb_uint
    TEXT wb_dropped
    jmp .divider
.header_empty:
    TEXT wb_novalue
.divider:
    ; Divider and AST area.
    AT 3,0,[wb_columns]
    mov rbx, [wb_columns]
.line:
    mov edi, '-'
    call wb_char
    dec rbx
    jnz .line
    AT 4,0,[wb_left]
    TEXT wb_ast_title
    cmp qword [wb_focus], 1
    jne .ast_rows
    TEXT wb_arrow
.ast_rows:
    mov ebx, 5
    mov r13, [wb_tree_top]
.ast_loop:
    mov rax, [wb_resultrow]
    dec rax
    cmp rbx, rax
    jae .instructions
    cmp r13, [wb_tree_count]
    jae .instructions
    mov r14, r13
    shl r14, 4
    mov r12, [wb_tree+r14]
    AT rbx,0,[wb_left]
    mov edi, ' '
    mov rax, [r12+N_ID]
    cmp rax, [wb_selected_node]
    jne .ast_mark
    mov edi, '>'
.ast_mark:
    call wb_char
    mov r15, [wb_tree+r14+8]
    cmp r15, 5
    jbe .indent
    mov r15d, 5
.indent:
    test r15, r15
    jz .ast_label
    TEXT wb_blank
    TEXT wb_blank
    dec r15
    jmp .indent
.ast_label:
    TEXT wb_hash
    UINT [r12+N_ID]
    TEXT wb_blank
    mov rdi, r12
    call wb_node_label
    mov rax, [r12+N_VALUE]
    test rax, rax
    jz .next_ast
    mov r14, rax
    TEXT wb_blank
    UINT [r14]
    TEXT wb_x
    UINT [r14+8]
.next_ast:
    inc r13
    inc rbx
    jmp .ast_loop
.instructions:
    AT 4,[wb_right],[wb_columns]
    TEXT wb_event_title
    cmp qword [wb_focus], 0
    jne .event_rows
    TEXT wb_arrow
.event_rows:
    mov ebx, 5
    mov r13, [wb_event_top]
    mov r14, [wb_listrows]
.events:
    test r14, r14
    jz .registers
    cmp r13, [trace_count]
    jae .registers
    AT rbx,[wb_right],[wb_columns]
    mov edi, ' '
    cmp r13, [wb_event]
    jne .event_mark
    mov edi, '>'
.event_mark:
    call wb_char
    lea rdi, [r13+1]
    call wb_uint
    TEXT wb_blank
    imul r12, r13, TS
    lea r12, [trace_records+r12]
    TEXT wb_hash
    UINT [r12+8]
    TEXT wb_blank
    mov rax, [r12]
    mov rdi, [op_names+rax*8]
    call wb_put
    TEXT wb_blank
    mov rax, [r12+TR_STAGE]
    mov rdi, [stage_names+rax*8]
    call wb_put
    inc rbx
    inc r13
    dec r14
    jmp .events
.registers:
    mov rbx, [wb_listrows]
    add rbx, 5
    AT rbx,[wb_right],[wb_columns]
    TEXT wb_regs_title
    inc rbx
    AT rbx,[wb_right],[wb_columns]
    cmp qword [last_execution_mode], 0
    jne .compute_note
    mov rax, [wb_event]
    test rax, rax
    js .noevent
    imul r12, rax, TS
    lea r12, [trace_records+r12]
    TEXT wb_pc
    mov rdi, [r12+24]
    call wb_hex
    TEXT wb_context
    UINT [r12+16]
    TEXT wb_lanes
    UINT [r12+TR_ACTIVE]
    TEXT wb_slash
    UINT [r12+TR_HWLANES]
    TEXT wb_k
    SINT [r12+TR_K]
    inc rbx
    AT rbx,[wb_right],[wb_columns]
    TEXT wb_xmm0
    lea rdi, [r12+32]
    call wb_lanepair
    inc rbx
    AT rbx,[wb_right],[wb_columns]
    TEXT wb_xmm1
    lea rdi, [r12+48]
    call wb_lanepair
    inc rbx
    AT rbx,[wb_right],[wb_columns]
    TEXT wb_after
    lea rdi, [r12+64]
    call wb_lanepair
    inc rbx
    AT rbx,[wb_right],[wb_columns]
    TEXT wb_mxcsr
    mov rdi, [r12+88]
    call wb_hex
    TEXT wb_arrow_to
    mov rdi, [r12+80]
    call wb_hex
    jmp .value
.compute_note:
    TEXT wb_compute_note
    jmp .value
.noevent:
    TEXT wb_noevents
.value:
    mov rbx, [wb_resultrow]
    AT rbx,0,[wb_columns]
    cmp qword [root_node], 0
    je .novalue
    cmp qword [result_value], 0
    je .novalue
    TEXT wb_value_title
    UINT [wb_selected_node]
    mov rax, [wb_selected_node]
    imul rax, NS
    mov r12, [nodes+rax+N_VALUE]
    test r12, r12
    jz .novalue
    TEXT wb_blank
    UINT [r12]
    TEXT wb_x
    UINT [r12+8]
    TEXT wb_final_title
    mov r14, [result_value]
    test r14, r14
    jz .final_done
    UINT [r14]
    TEXT wb_x
    UINT [r14+8]
.final_done:
    TEXT wb_value_note
    cmp qword [wb_focus], 2
    jne .value_rows
    TEXT wb_arrow
.value_rows:
    mov r13, [wb_row_offset]
    mov rax, [r12]
    dec rax
    cmp r13, rax
    cmova r13, rax
    mov [wb_row_offset], r13
    mov r14, [wb_col_offset]
    mov rax, [r12+8]
    dec rax
    cmp r14, rax
    cmova r14, rax
    mov [wb_col_offset], r14
    inc rbx
.row_loop:
    mov rax, [wb_rows]
    sub rax, 2
    cmp rbx, rax
    jae .footer
    cmp r13, [r12]
    jae .footer
    AT rbx,0,[wb_columns]
    TEXT wb_row
    lea rdi, [r13+1]
    call wb_uint
    TEXT wb_col
    lea rdi, [r14+1]
    call wb_uint
    TEXT wb_colon
    mov r15, r14
.cell_loop:
    cmp qword [wb_remaining], 24
    jb .next_row
    cmp r15, [r12+8]
    jae .next_row
    mov rax, r13
    imul rax, [r12+8]
    add rax, r15
    mov rdx, [r12+V_DATA]
    mov rdi, [rdx+rax*8]
    call wb_float
    TEXT wb_sep
    inc r15
    jmp .cell_loop
.next_row:
    inc r13
    inc rbx
    jmp .row_loop
.novalue:
    inc rbx
    AT rbx,0,[wb_columns]
    TEXT wb_novalue
    jmp .footer
.small:
    AT 2,0,[wb_columns]
    TEXT wb_size_note
    cmp qword [wb_rows], 4
    jb .paint
.footer:
    mov rbx, [wb_rows]
    sub rbx, 2
    AT rbx,0,[wb_columns]
    cmp qword [wb_editing], 0
    jne .editor_line
    TEXT wb_help
    inc rbx
    AT rbx,0,[wb_columns]
    mov rdi, [wb_notice]
    test rdi, rdi
    jnz .notice
    lea rdi, [wb_focus_events]
    cmp qword [wb_focus], 0
    je .notice
    lea rdi, [wb_focus_ast]
    cmp qword [wb_focus], 1
    je .notice
    lea rdi, [wb_focus_result]
.notice:
    call wb_put
    jmp .paint
.editor_line:
    cmp qword [wb_editing], 2
    je .search_label
    TEXT wb_edit_label
    jmp .edit_source
.search_label:
    TEXT wb_search_label
.edit_source:
    mov r15, [wb_edit_cursor]
    mov rax, [wb_columns]
    sub rax, 12
    xor r14d, r14d
    cmp r15, rax
    jb .editor_pos
    mov r14, r15
    sub r14, rax
    inc r14
.editor_pos:
    lea rdi, [wb_edit+r14]
    call wb_put
    ; Show an unambiguous cursor offset without overwriting help text.
    inc rbx
    AT rbx,0,[wb_columns]
    TEXT wb_cursor_label
    UINT [wb_edit_cursor]
    TEXT wb_sep
    mov rdi, [wb_notice]
    test rdi, rdi
    jz .editor_usage
    call wb_put
    jmp .paint
.editor_usage:
    cmp qword [wb_editing], 2
    je .search_help
    TEXT wb_editor_help
    jmp .paint
.search_help:
    TEXT wb_search_help
.paint:
    lea rdi, [wb_home]
    mov esi, 3
    call rt_console_write_bytes
    ; Contiguous output frame, CRLF between rows, no LF after bottom row.
    lea rdi, [wb_output]
    xor ebx, ebx
.pack:
    imul rax, rbx, WB_STRIDE
    lea rsi, [wb_cells+rax]
    mov rcx, [wb_columns]
    rep movsb
    inc rbx
    cmp rbx, [wb_rows]
    jae .packed
    mov byte [rdi], 13
    mov byte [rdi+1], 10
    add rdi, 2
    jmp .pack
.packed:
    lea rax, [wb_output]
    sub rdi, rax
    mov rsi, rdi
    mov rdi, rax
    call rt_console_write_bytes
    test rax, rax
    js .done
    call rt_output_flush
.done:
    DONE
wb_lanepair:
    FRAME 0
    mov r13, rdi
    mov rdi, [r13]
    cmp qword [trace_bits], 0
    jne .hex0
    call wb_float
    jmp .lane1
.hex0:
    call wb_hex
.lane1:
    TEXT wb_sep
    mov rdi, [r13+8]
    cmp qword [trace_bits], 0
    jne .hex1
    call wb_float
    DONE
.hex1:
    call wb_hex
    DONE

; Return key code; ESC-sequence timeout does not block forever on a bare escape.
wb_getkey:
    FRAME 0
    mov edi, 100
    call rt_terminal_poll
    cmp rax, 27
    jne .done
    mov edi, 60
    call rt_terminal_poll
    cmp rax, -3
    je .done
    cmp rax, '['
    je .sequence
    cmp rax, 'O'
    je .sequence
    mov eax, 27
    jmp .done
.sequence:
    xor ebx, ebx
.more:
    cmp ebx, 12
    jae .ignored
    mov edi, 100
    call rt_terminal_poll
    cmp rax, -3
    je .done
    cmp rax, 0
    jl .ignored
    mov [wb_seq+rbx], al
    inc ebx
    cmp al, 'A'
    je .up
    cmp al, 'B'
    je .down
    cmp al, 'C'
    je .right
    cmp al, 'D'
    je .left
    cmp al, 'H'
    je .home
    cmp al, 'F'
    je .end
    cmp al, '~'
    je .tilde
    cmp al, '0'
    jb .ignored
    cmp al, '9'
    jbe .more
    cmp al, ';'
    je .more
    jmp .ignored
.tilde:
    cmp byte [wb_seq], '1'
    je .home
    cmp byte [wb_seq], '4'
    je .end
    cmp byte [wb_seq], '5'
    je .pgup
    cmp byte [wb_seq], '6'
    je .pgdn
    cmp byte [wb_seq], '3'
    je .delete
.ignored:
    mov rax, -1
    jmp .done
.up: mov eax, KEY_UP
    jmp .done
.down: mov eax, KEY_DOWN
    jmp .done
.right: mov eax, KEY_RIGHT
    jmp .done
.left: mov eax, KEY_LEFT
    jmp .done
.home: mov eax, KEY_HOME
    jmp .done
.end: mov eax, KEY_END
    jmp .done
.pgup: mov eax, KEY_PGUP
    jmp .done
.pgdn: mov eax, KEY_PGDN
    jmp .done
.delete: mov eax, KEY_DELETE
.done:
    DONE

wb_history_add:
    FRAME 0
    mov r12, rdi
    cmp byte [r12], 0
    je .done
    mov rax, [wb_history_next]
    shl rax, 12
    lea rdi, [wb_history+rax]
    mov rsi, r12
    mov edx, INPUT_CAP
    call rt_memcpy
    inc qword [wb_history_next]
    and qword [wb_history_next], WB_HISTORY_CAP-1
    cmp qword [wb_history_count], WB_HISTORY_CAP
    jae .done
    inc qword [wb_history_count]
.done:
    DONE
wb_edit_begin:
    FRAME 0
    mov [wb_editing], rdi
    mov qword [wb_history_position], 0
    mov qword [wb_edit_len], 0
    mov qword [wb_edit_cursor], 0
    mov byte [wb_edit], 0
    mov byte [wb_draft], 0
    mov qword [wb_notice], 0
    mov qword [wb_dirty], 1
    DONE
; EDI key. Native editor: printable ASCII, 4095-byte expression / 63-byte search.
wb_edit_key:
    FRAME 0
    mov r12, rdi
    cmp edi, 27
    je .cancel
    cmp edi, 10
    je .submit
    cmp edi, 13
    je .submit
    cmp edi, 21
    je .clear
    cmp edi, KEY_UP
    je .history_up
    cmp edi, KEY_DOWN
    je .history_down
    cmp edi, KEY_LEFT
    je .left
    cmp edi, KEY_RIGHT
    je .right
    cmp edi, KEY_HOME
    je .home
    cmp edi, KEY_END
    je .end
    cmp edi, 127
    je .backspace
    cmp edi, 8
    je .backspace
    cmp edi, KEY_DELETE
    je .delete
    cmp edi, 32
    jb .done
    cmp edi, 126
    ja .done
    mov eax, INPUT_CAP-1
    cmp qword [wb_editing], 2
    jne .capacity
    mov eax, 63
.capacity:
    cmp [wb_edit_len], rax
    jae .full
    mov rbx, [wb_edit_cursor]
    lea rdi, [wb_edit+rbx+1]
    lea rsi, [wb_edit+rbx]
    mov rdx, [wb_edit_len]
    sub rdx, rbx
    inc rdx
    call rt_memmove
    mov [wb_edit+rbx], r12b
    inc qword [wb_edit_len]
    inc qword [wb_edit_cursor]
    jmp .changed
.backspace:
    cmp qword [wb_edit_cursor], 0
    je .done
    dec qword [wb_edit_cursor]
.delete:
    mov rbx, [wb_edit_cursor]
    cmp rbx, [wb_edit_len]
    jae .done
    lea rdi, [wb_edit+rbx]
    lea rsi, [wb_edit+rbx+1]
    mov rdx, [wb_edit_len]
    sub rdx, rbx
    call rt_memmove
    dec qword [wb_edit_len]
    jmp .changed
.left:
    cmp qword [wb_edit_cursor], 0
    je .done
    dec qword [wb_edit_cursor]
    jmp .changed
.right:
    mov rax, [wb_edit_cursor]
    cmp rax, [wb_edit_len]
    jae .done
    inc qword [wb_edit_cursor]
    jmp .changed
.home:
    mov qword [wb_edit_cursor], 0
    jmp .changed
.end:
    mov rax, [wb_edit_len]
    mov [wb_edit_cursor], rax
    jmp .changed
.clear:
    mov byte [wb_edit], 0
    mov qword [wb_edit_len], 0
    mov qword [wb_edit_cursor], 0
    jmp .changed
.history_up:
    cmp qword [wb_editing], 1
    jne .done
    mov rax, [wb_history_position]
    cmp rax, [wb_history_count]
    jae .done
    test rax, rax
    jnz .older
    lea rdi, [wb_draft]
    lea rsi, [wb_edit]
    mov edx, INPUT_CAP
    call rt_memcpy
.older:
    inc qword [wb_history_position]
    jmp .recall
.history_down:
    cmp qword [wb_editing], 1
    jne .done
    cmp qword [wb_history_position], 0
    je .done
    dec qword [wb_history_position]
.recall:
    mov rax, [wb_history_position]
    test rax, rax
    jz .draft
    mov rcx, [wb_history_next]
    sub rcx, rax
    and ecx, WB_HISTORY_CAP-1
    shl rcx, 12
    lea rsi, [wb_history+rcx]
    jmp .copy_history
.draft:
    lea rsi, [wb_draft]
.copy_history:
    lea rdi, [wb_edit]
    mov edx, INPUT_CAP
    call rt_memcpy
    lea rdi, [wb_edit]
    call rt_strlen
    mov [wb_edit_len], rax
    mov [wb_edit_cursor], rax
    lea rax, [wb_history_note]
    mov [wb_notice], rax
    jmp .changed
.submit:
    cmp qword [wb_editing], 2
    je .search_submit
    ; Screen editor accepts expressions, not commands with stream output side effects.
    lea rdi, [wb_edit]
.leading:
    cmp byte [rdi], ' '
    jne .first
    inc rdi
    jmp .leading
.first:
    cmp byte [rdi], ':'
    je .colon
    cmp byte [rdi], 0
    je .cancel
    lea rdi, [wb_edit]
    call wb_history_add
    lea rdi, [input_buf]
    lea rsi, [wb_edit]
    mov edx, INPUT_CAP
    call rt_memcpy
    mov qword [wb_editing], 0
    call process_line
    call wb_refresh_snapshot
    lea rax, [wb_expr_note]
    cmp qword [err_msg], 0
    je .notice
    mov rax, [err_msg]
.notice:
    mov [wb_notice], rax
    jmp .changed
.search_submit:
    lea rdi, [wb_search]
    lea rsi, [wb_edit]
    mov edx, 64
    call rt_memcpy
    mov qword [wb_editing], 0
    call wb_find_next
    jmp .changed
.colon:
    lea rax, [wb_command_note]
    mov [wb_notice], rax
.cancel:
    mov qword [wb_editing], 0
    jmp .changed
.full:
    lea rax, [wb_capacity_note]
    mov [wb_notice], rax
.changed:
    mov qword [wb_dirty], 1
.done:
    DONE

wb_contains:
    ; haystack RDI, needle RSI -> EAX boolean, trusted NUL strings.
    cmp byte [rsi], 0
    je .no
.next:
    cmp byte [rdi], 0
    je .no
    xor ecx, ecx
.match:
    mov al, [rsi+rcx]
    test al, al
    jz .yes
    cmp al, [rdi+rcx]
    jne .advance
    inc rcx
    jmp .match
.advance:
    inc rdi
    jmp .next
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret
wb_find_next:
    FRAME 0
    mov rbx, [wb_event]
    mov r13, [trace_count]
.loop:
    test r13, r13
    jz .notfound
    inc rbx
    cmp rbx, [trace_count]
    jb .index
    xor ebx, ebx
.index:
    imul r12, rbx, TS
    lea r12, [trace_records+r12]
    mov rax, [r12]
    mov rdi, [op_names+rax*8]
    lea rsi, [wb_search]
    call wb_contains
    test eax, eax
    jnz .found
    mov rax, [r12+TR_STAGE]
    mov rdi, [stage_names+rax*8]
    lea rsi, [wb_search]
    call wb_contains
    test eax, eax
    jnz .found
    dec r13
    jmp .loop
.found:
    mov rdi, rbx
    call wb_select_event
    mov qword [wb_notice], 0
    DONE
.notfound:
    lea rax, [wb_notfound]
    mov [wb_notice], rax
    DONE

wb_run:
    FRAME 0
    cmp qword [wb_active], 0
    jne .unavailable
    cmp qword [interactive_mode], 0
    je .unavailable
    mov rax, [json_mode]
    or rax, [quiet_mode]
    jnz .unavailable
    call rt_output_flush
    test rax, rax
    js .io_fault
    call rt_terminal_enter
    test rax, rax
    js .unavailable
    mov qword [wb_active], 1
    mov qword [wb_exit_signal], 0
    mov qword [wb_editing], 0
    mov qword [wb_notice], 0
    mov qword [wb_actual_columns], 0
    mov qword [wb_actual_rows], 0
    call wb_refresh_snapshot
    cmp qword [wb_history_count], 0
    jne .loop
    lea rdi, [last_input]
    call wb_history_add
.loop:
    call rt_terminal_size
    mov r12, rax
    mov r13, rdx
    cmp rax, [wb_actual_columns]
    jne .resize
    cmp rdx, [wb_actual_rows]
    jne .resize
    test rcx, rcx
    jz .ready
.resize:
    mov [wb_actual_columns], r12
    mov [wb_actual_rows], r13
    dec r12                            ; leave terminal's wrap column unused
    cmp r12, WB_STRIDE
    jbe .width
    mov r12d, WB_STRIDE
.width:
    cmp r12, 1
    jae .width_good
    mov r12d, 1
.width_good:
    mov [wb_columns], r12
    cmp r13, WB_MAX_ROWS
    jbe .height
    mov r13d, WB_MAX_ROWS
.height:
    cmp r13, 1
    jae .height_good
    mov r13d, 1
.height_good:
    mov [wb_rows], r13
    mov rax, r12
    xor edx, edx
    mov ecx, 3
    div rcx
    mov [wb_left], rax
    inc rax
    mov [wb_right], rax
    mov rax, r13
    sub rax, 18
    cmp rax, 4
    jge .list_min
    mov eax, 4
.list_min:
    cmp rax, 12
    jle .list_max
    mov eax, 12
.list_max:
    mov [wb_listrows], rax
    sub r13, 7
    mov [wb_resultrow], r13
    call wb_scroll_selection
    lea rdi, [wb_clear]
    mov esi, 7
    call rt_console_write_bytes
    mov qword [wb_dirty], 1
.ready:
    cmp qword [wb_dirty], 0
    je .input
    call wb_render
    test rax, rax
    js .io_fault_live
    mov qword [wb_dirty], 0
.input:
    call wb_getkey
    cmp rax, -3
    je .signal_exit
    cmp rax, -2
    je .io_fault_live
    test rax, rax
    js .loop
    mov [wb_key_saved], rax
    cmp qword [wb_editing], 0
    jne .edit_key
    cmp eax, 'q'
    je .leave
    cmp eax, 4
    je .leave
    cmp eax, 'e'
    je .edit
    cmp eax, '/'
    je .search
    cmp eax, 'f'
    je .find
    cmp eax, 'b'
    je .bits
    cmp eax, 'm'
    je .mode
    cmp eax, 'c'
    je .clear
    cmp eax, 9
    je .tab
    cmp eax, 12
    je .dirty
    mov qword [wb_notice], 0
    cmp qword [wb_focus], 1
    je .ast_keys
    cmp qword [wb_focus], 2
    je .value_keys
    mov rdi, [wb_event]
    cmp eax, KEY_DOWN
    je .next
    cmp eax, KEY_RIGHT
    je .next
    cmp eax, 'n'
    je .next
    cmp eax, 10
    je .next
    cmp eax, 13
    je .next
    cmp eax, KEY_UP
    je .previous
    cmp eax, KEY_LEFT
    je .previous
    cmp eax, 'p'
    je .previous
    cmp eax, KEY_PGDN
    je .pg_next
    cmp eax, KEY_PGUP
    je .pg_previous
    cmp eax, 'g'
    je .first
    cmp eax, KEY_HOME
    je .first
    cmp eax, 'G'
    je .last
    cmp eax, KEY_END
    je .last
    jmp .loop
.next:
    inc rdi
    jmp .select
.previous:
    dec rdi
    jmp .select
.pg_next:
    add rdi, [wb_listrows]
    jmp .select
.pg_previous:
    sub rdi, [wb_listrows]
    jmp .select
.first:
    xor edi, edi
    jmp .select
.last:
    mov rdi, [trace_count]
    dec rdi
.select:
    call wb_select_event
    jmp .dirty
.ast_keys:
    mov rdi, [wb_tree_index]
    cmp eax, KEY_DOWN
    je .ast_next
    cmp eax, KEY_UP
    je .ast_previous
    cmp eax, 'g'
    je .ast_first
    cmp eax, KEY_HOME
    je .ast_first
    cmp eax, 'G'
    je .ast_last
    cmp eax, KEY_END
    je .ast_last
    jmp .loop
.ast_next:
    inc rdi
    jmp .ast_select
.ast_previous:
    dec rdi
    jmp .ast_select
.ast_first:
    xor edi, edi
    jmp .ast_select
.ast_last:
    mov rdi, [wb_tree_count]
    dec rdi
.ast_select:
    cmp qword [wb_tree_count], 0
    je .loop
    xor eax, eax
    test rdi, rdi
    cmovs rdi, rax
    mov rax, [wb_tree_count]
    dec rax
    cmp rdi, rax
    cmova rdi, rax
    mov [wb_tree_index], rdi
    call wb_select_node
    jmp .dirty
.value_keys:
    cmp qword [root_node], 0
    je .loop
    cmp qword [result_value], 0
    je .loop
    cmp eax, KEY_DOWN
    je .row_next
    cmp eax, KEY_UP
    je .row_prev
    cmp eax, KEY_RIGHT
    je .col_next
    cmp eax, KEY_LEFT
    je .col_prev
    cmp eax, KEY_HOME
    je .value_home
    cmp eax, 'g'
    je .value_home
    cmp eax, KEY_END
    je .value_end
    cmp eax, 'G'
    je .value_end
    jmp .loop
.row_next:
    inc qword [wb_row_offset]
    jmp .dirty
.row_prev:
    cmp qword [wb_row_offset], 0
    je .loop
    dec qword [wb_row_offset]
    jmp .dirty
.col_next:
    inc qword [wb_col_offset]
    jmp .dirty
.col_prev:
    cmp qword [wb_col_offset], 0
    je .loop
    dec qword [wb_col_offset]
    jmp .dirty
.value_home:
    mov qword [wb_row_offset], 0
    mov qword [wb_col_offset], 0
    jmp .dirty
.value_end:
    mov rax, [wb_selected_node]
    imul rax, NS
    mov rax, [nodes+rax+N_VALUE]
    test rax, rax
    jz .loop
    mov rcx, [rax]
    dec rcx
    mov [wb_row_offset], rcx
    mov rcx, [rax+8]
    dec rcx
    mov [wb_col_offset], rcx
    jmp .dirty
.tab:
    inc qword [wb_focus]
    cmp qword [wb_focus], 3
    jb .tab_ok
    mov qword [wb_focus], 0
.tab_ok:
    mov qword [wb_notice], 0
    jmp .dirty
.mode:
    xor qword [execution_mode], 1
    mov rax, [execution_mode]
    xor rax, 1
    mov [trace_enabled], rax
    lea rax, [wb_mode_note]
    mov [wb_notice], rax
    jmp .dirty
.bits:
    xor qword [trace_bits], 1
    jmp .dirty
.clear:
    call expression_reset
    call workspace_clear
    mov byte [last_input], 0
    call wb_refresh_snapshot
    lea rax, [wb_clear_note]
    mov [wb_notice], rax
    jmp .dirty
.edit:
    mov edi, 1
    call wb_edit_begin
    jmp .dirty
.search:
    mov edi, 2
    call wb_edit_begin
    jmp .dirty
.find:
    call wb_find_next
    jmp .dirty
.edit_key:
    mov rdi, [wb_key_saved]
    call wb_edit_key
.dirty:
    mov qword [wb_dirty], 1
    jmp .loop
.signal_exit:
    mov [wb_exit_signal], rdx
    add rdx, 128
    mov [exit_status], rdx
    jmp .leave
.io_fault_live:
    mov qword [exit_status], 2
.leave:
    call rt_output_flush
    call rt_terminal_leave
    test rax, rax
    jns .restored
    mov qword [exit_status], 2
.restored:
    mov qword [wb_active], 0
    mov qword [wb_editing], 0
    xor eax, eax
    cmp qword [wb_exit_signal], 0
    je .done
    mov eax, 2
.done:
    DONE
.io_fault:
    mov qword [exit_status], 2
    mov eax, 2
    DONE
.unavailable:
    SAY wb_unavailable
    xor eax, eax
    DONE
%unmacro AT 3
%unmacro TEXT 1
%unmacro UINT 1
%unmacro SINT 1
%endif

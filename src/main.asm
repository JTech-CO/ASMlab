section .rodata
usage: db 'Usage: asmlab [--quiet|--json] [--all] [--bits] [--step]',10
       db '              [--color|--no-color] [-e EXPRESSION | -f FILE]',10
       db '              [--memory-mib 1..1024] [--mode observe|compute]',10
       db '              [--trace-json] [--workbench]',10
       db '       asmlab --help | --version',10
%ifdef ASMLAB_LIBC_REFERENCE
       db 'Runtime: development-only libc/CRT comparison backend; NOT L3-Core.',10
%else
       db 'Runtime: Linux x86-64 / WSL2; L3-Core; own runtime; no libc or CRT.',10
%endif
       db 'All math, parser, evaluator, tracing, and terminal UI are NASM assembly.',0
help_text: db 'EXPRESSIONS',10
       db '  x = 2^3 + 1                  float64 scalars; pi, e, and ans',10
       db '  A = [1,2;3,4]                commas = columns; semicolons = rows',10
       db '  A*A   A.*A   A+2   A/2      matrix product / elementwise / broadcast',10
       db '  transpose(A)   A',39,'         real matrix transpose',10
       db '  sin(pi/4) cos(0) sqrt(A) log(A) sum(A)',10
       db '  ^ uses scalar integer exponents [-1024,1024]; 0^0 = 1',10
       db '  sin/cos: |x| <= 1e6 radians; log: natural log, x>0; sqrt: x>=0',10
       db '  zeros(n[,m]) ones(n[,m]) eye(n[,m]) size(A[,dim])',10
       db '  linspace(a,b,n)   A(row,col)   # 1-based scalar indices',10
       db 'COMMANDS',10
       db '  :help  :vars  :memory  :drop NAME  :clear  :quit',10
       db '  :trace on|off|all   :bits on|off   :step on|off   :replay',10
       db '  :mode observe|compute   :trace json   :workbench',10
       db 'MODES / WORKBENCH',10
       db '  Observe captures real instructions; Compute uses inline non-capturing SSE2.',10
       db '  JSON/quiet default to Compute; --trace-json defaults to Observe.',10
       db '  --mode overrides the default. :trace off = Compute, on/all = Observe.',10
       db '  --workbench requires native Linux TTY/ANSI, at least 80 columns x 24 rows.',10
       db '  Workbench: Tab focus, arrows/pages, e edit, / search, f next, b bits, m mode, q exit.',10
       db 'TRACE',10
       db '  Real pre/post XMM captures from precompiled SSE2 kernels, not a JIT.',10
       db '  Replay happens AFTER evaluation: Enter/n=next, p=previous, q=finish.',10
       db '  Default: 6 frames shown; at most 8192 retained; overflow is disclosed.',10
       db 'LIMITS',10
       db '  1048576 elements/value; 64 MiB default heap quota; 512 AST nodes; depth 64.',10
       db '  Matmul <=16777216 terms. Table preview <=16x16; JSON/quiet are complete.',10
       db '  No slices/indexed assignment, complex/symbolic math, plots, solver, or MATLAB compatibility.',0
startup_tip: db 'Type :help for syntax. Try sqrt([1,4,9,16]) + 2',0
prompt: db 10,'asmlab> ',0
opt_help: db '--help',0
opt_h: db '-h',0
opt_version: db '--version',0
opt_quiet: db '--quiet',0
opt_q: db '-q',0
opt_json: db '--json',0
opt_all: db '--all',0
opt_bits: db '--bits',0
opt_step: db '--step',0
opt_color: db '--color',0
opt_nocolor: db '--no-color',0
opt_expr: db '-e',0
opt_file: db '-f',0
opt_memory: db '--memory-mib',0
cmd_memory: db ':memory',0
cmd_drop: db ':drop ',0
cmd_help: db ':help',0
cmd_vars: db ':vars',0
cmd_clear: db ':clear',0
cmd_quit: db ':quit',0
cmd_exit: db ':exit',0
cmd_traceon: db ':trace on',0
cmd_traceoff: db ':trace off',0
cmd_traceall: db ':trace all',0
cmd_bitson: db ':bits on',0
cmd_bitsoff: db ':bits off',0
cmd_stepon: db ':step on',0
cmd_stepoff: db ':step off',0
cmd_replay: db ':replay',0
setting_msg: db 'Setting updated.',0
cleared_msg: db 'Workspace cleared. ans = 0.',0
err_command: db 'Unknown command. Type :help.',0
err_open: db 'Cannot open input file.',0
err_read: db 'Input stream read failed.',0
err_args: db 'Invalid command-line arguments. Run asmlab --help.',0
opt_mode: db '--mode',0
mode_observe: db 'observe',0
mode_compute: db 'compute',0
opt_workbench: db '--workbench',0
opt_tracejson: db '--trace-json',0
cmd_observe: db ':mode observe',0
cmd_compute: db ':mode compute',0
cmd_workbench: db ':workbench',0
cmd_export: db ':trace json',0
section .text
global main
main:
    FRAME 32
    mov r12d, edi
    mov r13, rsi
    mov qword [rsp], 0
    mov qword [rsp+8], 0
    mov qword [rsp+16], 0
    mov qword [trace_enabled], 1
    mov qword [trace_limit], 6
    mov qword [ast_draw_limit], NODE_CAP
    xor edi, edi
    call rt_is_tty
    mov ebx, eax
    mov edi, 1
    call rt_is_tty
    mov [color_enabled], rax
    and eax, ebx
    mov [interactive_mode], rax
    call rt_input_stdin
    mov [input_stream], rax
    call workspace_clear
    mov ebx, 1
.args:
    cmp ebx, r12d
    jae .configured
    mov r14, [r13+rbx*8]
    mov rdi, r14
    lea rsi, [opt_help]
    call rt_strcmp
    test eax, eax
    jz .help
    mov rdi, r14
    lea rsi, [opt_h]
    call rt_strcmp
    test eax, eax
    jz .help
    mov rdi, r14
    lea rsi, [opt_version]
    call rt_strcmp
    test eax, eax
    jz .version
    mov rdi, r14
    lea rsi, [opt_quiet]
    call rt_strcmp
    test eax, eax
    jz .quiet
    mov rdi, r14
    lea rsi, [opt_q]
    call rt_strcmp
    test eax, eax
    jz .quiet
    mov rdi, r14
    lea rsi, [opt_json]
    call rt_strcmp
    test eax, eax
    jz .json
    mov rdi, r14
    lea rsi, [opt_all]
    call rt_strcmp
    test eax, eax
    jz .all
    mov rdi, r14
    lea rsi, [opt_bits]
    call rt_strcmp
    test eax, eax
    jz .bits
    mov rdi, r14
    lea rsi, [opt_step]
    call rt_strcmp
    test eax, eax
    jz .step
    mov rdi, r14
    lea rsi, [opt_color]
    call rt_strcmp
    test eax, eax
    jz .color
    mov rdi, r14
    lea rsi, [opt_nocolor]
    call rt_strcmp
    test eax, eax
    jz .nocolor
    mov rdi, r14
    lea rsi, [opt_expr]
    call rt_strcmp
    test eax, eax
    jz .expr
    mov rdi, r14
    lea rsi, [opt_file]
    call rt_strcmp
    test eax, eax
    jz .file
    mov rdi, r14
    lea rsi, [opt_memory]
    call rt_strcmp
    test eax, eax
    jz .memory_option
    mov rdi, r14
    lea rsi, [opt_mode]
    call rt_strcmp
    test eax, eax
    jz .mode_option
    mov rdi, r14
    lea rsi, [opt_workbench]
    call rt_strcmp
    test eax, eax
    jz .workbench_option
    mov rdi, r14
    lea rsi, [opt_tracejson]
    call rt_strcmp
    test eax, eax
    jz .tracejson_option
    jmp .badargs
.workbench_option:
    mov qword [workbench_requested], 1
    jmp .nextarg
.tracejson_option:
    mov qword [trace_json_mode], 1
    mov qword [json_mode], 1
    jmp .nextarg
.mode_option:
    inc ebx
    cmp ebx, r12d
    jae .badargs
    mov r14, [r13+rbx*8]
    mov rdi, r14
    lea rsi, [mode_observe]
    call rt_strcmp
    test eax, eax
    jz .mode_observe
    mov rdi, r14
    lea rsi, [mode_compute]
    call rt_strcmp
    test eax, eax
    jnz .badargs
    mov qword [execution_mode], 1
    jmp .mode_set
.mode_observe:
    mov qword [execution_mode], 0
.mode_set:
    mov qword [mode_explicit], 1
    jmp .nextarg
.memory_option:
    inc ebx
    cmp ebx, r12d
    jae .badargs
    mov r14, [r13+rbx*8]
    mov rdi, r14
    call rt_strlen
    mov rsi, rax
    mov rdi, r14
    call rt_parse_u64
    test rax, rax
    jnz .badargs
    cmp rdx, 1
    jb .badargs
    cmp rdx, 1024
    ja .badargs
    mov rdi, rdx
    shl rdi, 20
    call rt_memory_set_limit
    test rax, rax
    jnz .badargs
    jmp .nextarg
.quiet:
    mov qword [quiet_mode], 1
    mov qword [trace_enabled], 0
    jmp .nextarg
.json:
    mov qword [json_mode], 1
    mov qword [trace_enabled], 0
    jmp .nextarg
.all:
    mov qword [trace_limit], TRACE_CAP
    jmp .nextarg
.bits:
    mov qword [trace_bits], 1
    jmp .nextarg
.step:
    mov qword [trace_step], 1
    jmp .nextarg
.color:
    mov qword [color_enabled], 1
    jmp .nextarg
.nocolor:
    mov qword [color_enabled], 0
    jmp .nextarg
.expr:
    mov r15d, 1
    jmp .source
.file:
    mov r15d, 2
.source:
    cmp qword [rsp], 0
    jne .badargs
    inc ebx
    cmp ebx, r12d
    jae .badargs
    mov [rsp], r15
    mov rax, [r13+rbx*8]
    mov [rsp+8], rax
.nextarg:
    inc ebx
    jmp .args
.configured:
    cmp qword [mode_explicit], 0
    jne .mode_ready
    cmp qword [trace_json_mode], 0
    jne .mode_ready
    mov rax, [quiet_mode]
    or rax, [json_mode]
    jz .mode_ready
    mov qword [execution_mode], 1
.mode_ready:
    mov rax, [execution_mode]
    xor rax, 1
    mov [trace_enabled], rax
    cmp qword [workbench_requested], 0
    je .presentation
    cmp qword [interactive_mode], 0
    je .badargs
    mov rax, [quiet_mode]
    or rax, [json_mode]
    jnz .badargs
    cmp qword [rsp], 2
    je .badargs
    cmp qword [rsp], 1
    je .presentation
    call wb_run
    jmp .finish
.presentation:
    cmp qword [json_mode], 0
    jne .source_ready
    cmp qword [quiet_mode], 0
    jne .source_ready
    SAY banner
    SAY startup_tip
.source_ready:
    cmp qword [rsp], 1
    je .single_expr
    cmp qword [rsp], 2
    jne .read_loop
    mov rdi, [rsp+8]
    call rt_input_open_read
    test rax, rax
    jz .open_error
    mov [input_stream], rax
    mov qword [rsp+16], 1
    ; A script never consumes stdin for replay.
    mov qword [interactive_mode], 0
    jmp .read_loop
.single_expr:
    mov rdi, [rsp+8]
    call rt_strlen
    cmp rax, INPUT_CAP
    jae .long_expr
    lea rdx, [rax+1]
    lea rdi, [input_buf]
    mov rsi, [rsp+8]
    call rt_memcpy
    call process_line
    cmp qword [workbench_requested], 0
    je .finish
    call wb_run
    jmp .finish
.read_loop:
    cmp qword [interactive_mode], 0
    je .read
    cmp qword [json_mode], 0
    jne .read
    cmp qword [quiet_mode], 0
    jne .read
    lea rdi, [prompt]
    xor eax, eax
    call rt_console_format
    xor edi, edi
    call rt_output_flush
.read:
    call read_input_line
    test eax, eax
    jz .eof
    cmp eax, 1
    je .line
    cmp eax, -3
    je .read_error
    mov ebx, eax
    call expression_reset
    lea rdi, [err_line]
    cmp ebx, -1
    je .input_error
    lea rdi, [err_char]
.input_error:
    call set_error
    mov rax, [input_fault_pos]
    mov [err_pos], rax
    call render_error
    mov qword [exit_status], 1
    jmp .read_loop
.line:
    call process_line
    cmp eax, 2
    je .finish
    jmp .read_loop
.eof:
    mov rdi, [input_stream]
    call rt_input_error
    test eax, eax
    jnz .read_error
.finish:
    cmp qword [rsp+16], 0
    je .return
    mov rdi, [input_stream]
    call rt_input_close
    test eax, eax
    jz .return
    mov qword [exit_status], 2
.return:
    call temp_release
    call workspace_clear
    mov eax, [exit_status]
    DONE
.help:
    SAY usage
    SAY help_text
    xor eax, eax
    DONE
.version:
    SAY banner
    xor eax, eax
    DONE
.badargs:
    SAY err_args
    mov eax, 2
    DONE
.open_error:
    lea rdi, [err_open]
    jmp .io_error
.read_error:
    lea rdi, [err_read]
.io_error:
    mov [err_msg], rdi
    mov qword [err_pos], 0
    call render_error
    mov qword [exit_status], 2
    jmp .finish
.long_expr:
    call expression_reset
    lea rdi, [err_line]
    call set_error
    call render_error
    mov qword [exit_status], 1
    jmp .finish

; Process an expression or a colon command. Return 2 only for :quit/:exit.
process_line:
    FRAME 0
    ; Strip trailing whitespace. Leading whitespace is accepted.
    lea rdi, [input_buf]
    call rt_strlen
    lea r12, [input_buf]
.trim:
    test rax, rax
    jz .empty
    movzx ecx, byte [r12+rax-1]
    cmp cl, ' '
    je .cut
    cmp cl, 9
    je .cut
    cmp cl, 13
    je .cut
    cmp cl, 10
    jne .sanitize
.cut:
    dec rax
    mov byte [r12+rax], 0
    jmp .trim
.sanitize:
    mov rdi, r12
    call sanitize_input
    test eax, eax
    jz .leading
    call expression_reset
    lea rdi, [err_char]
    call set_error
    mov rax, [input_fault_pos]
    mov [err_pos], rax
    jmp .error
.leading:
    cmp byte [r12], ' '
    je .advance
    cmp byte [r12], 9
    jne .content
.advance:
    inc r12
    jmp .leading
.content:
    cmp byte [r12], 0
    je .empty
    cmp byte [r12], '#'
    je .empty
    cmp byte [r12], '%'
    je .empty
    cmp byte [r12], ':'
    je .command
    call expression_reset
    inc qword [expression_serial]
    mov rax, [execution_mode]
    mov [last_execution_mode], rax
    lea rdi, [last_input]
    lea rsi, [input_buf]
    mov edx, INPUT_CAP
    call rt_memcpy
    call parse_statement
    cmp qword [err_msg], 0
    jne .error
    test rax, rax
    jz .empty
    mov [root_node], rax
    mov rdi, rax
    call trace_prepare_spans
    mov rax, [root_node]
    ; Numerical trace starts clean, independent of decimal/parser side effects.
    ldmxcsr [mxcsr_default]
    mov rdi, rax
    cmp qword [execution_mode], 0
    jne .compute
    call eval_node
    jmp .evaluated
.compute:
    call eval_node_compute
.evaluated:
    mov qword [final_mxcsr], 0
    stmxcsr [final_mxcsr]
    cmp qword [err_msg], 0
    jne .error
    test rax, rax
    jz .empty
    mov r13, rax
    mov r12, [root_node]
    xor edi, edi
    cmp qword [r12+N_TYPE], ASSIGN
    jne .commit
    lea rdi, [r12+N_NAME]
.commit:
    mov rsi, r13
    call workspace_commit
    test eax, eax
    jz .error
    mov [result_value], r13
    cmp qword [wb_active], 0
    jne .empty
    call render_result
.empty:
    xor eax, eax
    DONE
.error:
    mov qword [result_value], 0
    mov qword [exit_status], 1
    cmp qword [wb_active], 0
    jne .discard_failed
    call render_error
.discard_failed:
    ; Failed expressions retain no dangling AST/arena pointers for replay.
    mov qword [root_node], 0
    mov qword [trace_count], 0
    mov qword [trace_total], 0
    call temp_release
    xor eax, eax
    DONE
.command:
    mov rdi, r12
    call process_command
    DONE

process_command:
    FRAME 0
    mov r12, rdi
    lea rsi, [cmd_help]
    call rt_strcmp
    test eax, eax
    jz .help
    mov rdi, r12
    lea rsi, [cmd_vars]
    call rt_strcmp
    test eax, eax
    jz .vars
    mov rdi, r12
    lea rsi, [cmd_clear]
    call rt_strcmp
    test eax, eax
    jz .clear
    mov rdi, r12
    lea rsi, [cmd_quit]
    call rt_strcmp
    test eax, eax
    jz .quit
    mov rdi, r12
    lea rsi, [cmd_exit]
    call rt_strcmp
    test eax, eax
    jz .quit
    mov rdi, r12
    lea rsi, [cmd_traceon]
    call rt_strcmp
    test eax, eax
    jz .traceon
    mov rdi, r12
    lea rsi, [cmd_traceoff]
    call rt_strcmp
    test eax, eax
    jz .traceoff
    mov rdi, r12
    lea rsi, [cmd_traceall]
    call rt_strcmp
    test eax, eax
    jz .traceall
    mov rdi, r12
    lea rsi, [cmd_bitson]
    call rt_strcmp
    test eax, eax
    jz .bitson
    mov rdi, r12
    lea rsi, [cmd_bitsoff]
    call rt_strcmp
    test eax, eax
    jz .bitsoff
    mov rdi, r12
    lea rsi, [cmd_stepon]
    call rt_strcmp
    test eax, eax
    jz .stepon
    mov rdi, r12
    lea rsi, [cmd_stepoff]
    call rt_strcmp
    test eax, eax
    jz .stepoff
    mov rdi, r12
    lea rsi, [cmd_replay]
    call rt_strcmp
    test eax, eax
    jz .replay
    mov rdi, r12
    lea rsi, [cmd_memory]
    call rt_strcmp
    test eax, eax
    jz .memory
    mov rdi, r12
    lea rsi, [cmd_observe]
    call rt_strcmp
    test eax, eax
    jz .traceon
    mov rdi, r12
    lea rsi, [cmd_compute]
    call rt_strcmp
    test eax, eax
    jz .traceoff
    mov rdi, r12
    lea rsi, [cmd_workbench]
    call rt_strcmp
    test eax, eax
    jz .workbench
    mov rdi, r12
    lea rsi, [cmd_export]
    call rt_strcmp
    test eax, eax
    jz .export
    mov rdi, r12
    mov esi, 6
    call rt_strnlen
    cmp rax, 6
    jb .unknown_command
    mov rdi, r12
    lea rsi, [cmd_drop]
    mov edx, 6
    call rt_memcmp
    test eax, eax
    jz .drop
.unknown_command:
    mov qword [err_msg], 0
    mov qword [tok_pos], 0
    lea rdi, [err_command]
    call set_error
    call render_error
    mov qword [exit_status], 1
    jmp .done
.help:
    SAY help_text
    jmp .done
.vars:
    call render_workspace
    jmp .done
.clear:
    call expression_reset
    call workspace_clear
    cmp qword [json_mode], 0
    jne .done
    cmp qword [quiet_mode], 0
    jne .done
    SAY cleared_msg
    jmp .done
.memory:
    call render_memory
    jmp .done
.drop:
    mov qword [err_msg], 0
    mov qword [tok_pos], 6
    lea rdi, [r12+6]
    call workspace_drop
    test eax, eax
    jnz .changed
    call render_error
    mov qword [exit_status], 1
    jmp .done
.traceon:
    mov qword [execution_mode], 0
    mov qword [trace_enabled], 1
    mov qword [trace_limit], 6
    jmp .changed
.traceoff:
    mov qword [execution_mode], 1
    mov qword [trace_enabled], 0
    jmp .changed
.traceall:
    mov qword [execution_mode], 0
    mov qword [trace_enabled], 1
    mov qword [trace_limit], TRACE_CAP
    jmp .changed
.bitson:
    mov qword [trace_bits], 1
    jmp .changed
.bitsoff:
    mov qword [trace_bits], 0
    jmp .changed
.stepon:
    mov qword [trace_step], 1
    jmp .changed
.stepoff:
    mov qword [trace_step], 0
.changed:
    cmp qword [json_mode], 0
    jne .done
    cmp qword [quiet_mode], 0
    jne .done
    SAY setting_msg
    jmp .done
.workbench:
    call wb_run
    test eax, eax
    jnz .quit
    jmp .done
.export:
    call trace_export
    jmp .done
.replay:
    call replay_trace
.done:
    xor eax, eax
    DONE
.quit:
    mov eax, 2
    DONE

; Return 1=line, 0=EOF, -1=overlong, -2=control byte, -3=I/O failure.
; rt_input_getc uses an opaque, backend-owned buffered stream. We reject the ENTIRE line, not a truncated prefix.
read_input_line:
    FRAME 0
    xor ebx, ebx
    xor r12d, r12d
    xor r13d, r13d
    lea r14, [input_buf]
    mov qword [input_fault_pos], 0
.loop:
    mov rdi, [input_stream]
    call rt_input_getc
    cmp eax, -1
    je .eof
    mov r13d, 1
    cmp eax, 10
    je .done
    cmp rbx, INPUT_CAP-1
    jae .overlong
    cmp eax, 9
    je .store
    cmp eax, 13
    je .store
    cmp eax, 32
    jb .invalid
    cmp eax, 127
    jne .store
.invalid:
    test r12d, r12d
    jnz .replace
    mov r12d, -2
    mov [input_fault_pos], rbx
.replace:
    mov eax, '?'
.store:
    mov [r14+rbx], al
    inc rbx
    jmp .loop
.overlong:
    mov r12d, -1
    mov qword [input_fault_pos], INPUT_CAP-1
    jmp .loop
.eof:
    mov rdi, [input_stream]
    call rt_input_error
    test eax, eax
    jnz .ioerror
    test r13d, r13d
    jz .empty
.done:
    mov byte [r14+rbx], 0
    mov eax, 1
    test r12d, r12d
    cmovne eax, r12d
    DONE
.empty:
    xor eax, eax
    DONE
.ioerror:
    mov eax, -3
    DONE

; -e arguments also pass through this check; trailing newlines were stripped.
sanitize_input:
    xor eax, eax
    xor ecx, ecx
.loop:
    movzx edx, byte [rdi+rcx]
    test edx, edx
    jz .done
    cmp edx, 9
    je .next
    cmp edx, 32
    jb .invalid
    cmp edx, 127
    jne .next
.invalid:
    test eax, eax
    jnz .replace
    mov [input_fault_pos], rcx
.replace:
    mov byte [rdi+rcx], '?'
    mov eax, 1
.next:
    inc rcx
    jmp .loop
.done:
    ret
section .bss
input_fault_pos: resq 1

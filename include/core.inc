; ASMlab - shared layout and ABI helpers. All application code is NASM x86-64.
bits 64
default rel

%define INPUT_CAP 4096
%define NODE_CAP 512
%define VALUE_CAP 512
%define VAR_CAP 64
%define DIM_CAP 16
%define ELEM_CAP 256
%define TRACE_CAP 8192
%define DEPTH_CAP 64
%define NS 128
%define VS 2064
%define SS 2096
%define TS 96
%define N_TYPE 0
%define N_OP 8
%define N_LEFT 16
%define N_RIGHT 24
%define N_NUM 32
%define N_NAME 40
%define N_ROWS 72
%define N_COLS 80
%define N_VALUE 88
%define N_ID 96
%define N_POS 104
%define N_NEXT 112
%define NUM 1
%define VAR 2
%define BINARY 3
%define UNARY 4
%define FUNC 5
%define MATRIX 6
%define ASSIGN 7
%define T_NUM 256
%define T_ID 257
%define T_EMUL 258
%define T_EDIV 259
%define F_SIN 1
%define F_COS 2
%define F_SQRT 3
%define F_LOG 4
%define F_TRANSPOSE 5
%define F_SUM 6
%define O_ADDSD 1
%define O_SUBSD 2
%define O_MULSD 3
%define O_DIVSD 4
%define O_SQRTSD 5
%define O_ADDPD 6
%define O_SUBPD 7
%define O_MULPD 8
%define O_DIVPD 9
%define O_SQRTPD 10
%define O_MOVAPD 11
%define O_XORPD 12

; At every external call rsp is aligned to 16 bytes, SysV AMD64.
; Reserve local space in multiples of 16; use rsp-relative local slots.
%macro FRAME 1
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, %1 + 8
%endmacro
%macro DONE 0
    lea rsp, [rbp-40]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
%endmacro
%macro OP 1
    mov edi, %1
    call exec_sse
%endmacro
%macro SAY 1
    lea rdi, [%1]
    call puts
%endmacro

extern printf, puts, fgets, fflush, getchar, isatty, stdin
extern strcmp, strlen, memcpy, memset, strtod, strchr
extern fopen, fclose, fgetc, ferror, __errno_location

section .rodata
zero: dq 0.0
one: dq 1.0
two: dq 2.0
half: dq 0.5
pi: dq 3.1415926535897932384626433832795
const_e: dq 2.7182818284590452353602874713527
ln_two: dq 0.6931471805599453094172321214582
sqrt_two: dq 1.4142135623730950488016887242097
inv_pio2: dq 0.6366197723675813430755350534901
pio2_hi: dq 1.57079632673412561417
pio2_lo: dq 6.07710050650619224932e-11
trig_bound: dq 1000000.0
pow_bound: dq 1024.0
scale_subnormal: dq 18014398509481984.0
align 16
abs_mask: dq 0x7fffffffffffffff, 0x7fffffffffffffff
sign_mask: dq 0x8000000000000000, 0x8000000000000000
name_pi: db 'pi',0
name_e: db 'e',0
name_ans: db 'ans',0
fn_sin: db 'sin',0
fn_cos: db 'cos',0
fn_sqrt: db 'sqrt',0
fn_log: db 'log',0
fn_transpose: db 'transpose',0
fn_sum: db 'sum',0
function_names: dq 0, fn_sin, fn_cos, fn_sqrt, fn_log, fn_transpose, fn_sum
err_syntax: db 'Expected a number, variable, function call, or bracketed expression.',0
err_char: db 'Unsupported character. Identifiers are ASCII; matrix columns use commas.',0
err_number: db 'Invalid or out-of-range decimal number.',0
err_name: db 'Identifiers may contain at most 31 ASCII characters.',0
err_paren: db 'Missing closing parenthesis.',0
err_extra: db 'Unexpected trailing token. Use one expression per line.',0
err_matrix: db 'Invalid matrix: use commas between columns and semicolons between rows.',0
err_rect: db 'Matrix rows must have the same number of columns.',0
err_size: db 'Matrix limit is 16 rows x 16 columns.',0
err_nodes: db 'Expression exceeds the 512-node limit.',0
err_depth: db 'Expression nesting exceeds the 64-level limit.',0
err_values: db 'Expression exceeds the temporary-value limit.',0
err_unknown: db 'Undefined variable.',0
err_func: db 'Unknown function. Available: sin cos sqrt log transpose sum.',0
err_shape: db 'Incompatible matrix dimensions.',0
err_div: db 'Division by zero.',0
err_real: db 'sqrt requires nonnegative real input.',0
err_log: db 'log requires strictly positive real input.',0
err_trig: db 'sin/cos require |x| <= 1000000 radians in this MVP.',0
err_pow: db '^ requires scalar operands and an integer exponent in [-1024,1024].',0
err_nonfinite: db 'Non-finite arithmetic result (overflow or invalid operation).',0
err_scalar: db 'Each matrix literal element must evaluate to a scalar.',0
err_rightdiv: db '/ accepts only a scalar divisor. Use ./ for elementwise division.',0
err_readonly: db 'pi, e, ans, and built-in function names cannot be assigned.',0
err_symbols: db 'The workspace supports 63 user variables plus ans.',0
err_line: db 'Input line is too long (maximum 4095 bytes); the whole line was rejected.',0

section .bss
alignb 16
input_buf: resb INPUT_CAP
lex_ptr: resq 1
tok_type: resq 1
tok_pos: resq 1
tok_num: resq 1
tok_name: resb 32
num_buf: resb 128
num_end: resq 1
err_msg: resq 1
err_pos: resq 1
node_count: resq 1
value_count: resq 1
parse_depth: resq 1
eval_depth: resq 1
root_node: resq 1
result_value: resq 1
nodes: resb NODE_CAP * NS
values: resb VALUE_CAP * VS
symbols: resb VAR_CAP * SS
symbol_count: resq 1
trace_count: resq 1
trace_total: resq 1
trace_node: resq 1
trace_element: resq 1
trace_enabled: resq 1
trace_limit: resq 1
trace_bits: resq 1
trace_step: resq 1
trace_replay: resq 1
trace_records: resb TRACE_CAP * TS
trace_scratch: resb TS
color_enabled: resq 1
quiet_mode: resq 1
json_mode: resq 1
interactive_mode: resq 1
exit_status: resq 1
input_stream: resq 1
step_buf: resb 32
mxcsr_default: resd 1

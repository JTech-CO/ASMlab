; Sole definition of application constants and fixed workspace.
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
fn_zeros: db 'zeros',0
fn_ones: db 'ones',0
fn_eye: db 'eye',0
fn_size: db 'size',0
fn_linspace: db 'linspace',0
function_names: dq 0, fn_sin, fn_cos, fn_sqrt, fn_log, fn_transpose, fn_sum, fn_zeros, fn_ones, fn_eye, fn_size, fn_linspace
err_syntax: db 'Expected a number, variable, function call, or bracketed expression.',0
err_char: db 'Unsupported character. Identifiers are ASCII; matrix columns use commas.',0
err_number: db 'Invalid or out-of-range decimal number.',0
err_name: db 'Identifiers may contain at most 31 ASCII characters.',0
err_paren: db 'Missing closing parenthesis.',0
err_extra: db 'Unexpected trailing token. Use one expression per line.',0
err_matrix: db 'Invalid matrix: use commas between columns and semicolons between rows.',0
err_rect: db 'Matrix rows must have the same number of columns.',0
err_size: db 'Dimensions must be positive integers; at most 1048576 elements per value.',0
err_nodes: db 'Expression exceeds the 512-node limit.',0
err_depth: db 'Expression nesting exceeds the 64-level limit.',0
err_values: db 'Expression exceeds the temporary-value limit.',0
err_unknown: db 'Undefined variable.',0
err_func: db 'Unknown function or indexed variable.',0
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
err_scalar_arg: db 'Function endpoint arguments must be scalar.',0
err_memory: db 'Memory quota exhausted or Linux allocation failed; workspace and ans are unchanged.',0
err_arity: db 'Wrong number of arguments for this function or index.',0
err_index: db 'Index must be an integer within the 1-based row/column bounds.',0
err_work: db 'Matrix product exceeds the 16777216-term work limit.',0
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
temp_head: resq 1
temp_cursor: resq 1
temp_end: resq 1
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

; ans has a static, allocation-free zero bootstrap. User values are heap owned.
section .data
align 16
symbols: db 'ans',0
    times 28 db 0
    dq boot_value, 0
boot_value:
    dq 1, 1, zero, 8, 8, 1, OWNER_STATIC, 0

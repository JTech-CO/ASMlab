; Application translation unit; runtime modules are separately assembled and linked.
%include "include/core.inc"
%include "src/core_storage.asm"
%include "src/runtime.asm"
%include "src/parser.asm"
%include "src/kernels.asm"
%include "src/math.asm"
%include "src/evaluator.asm"
%include "src/workspace_functions.asm"

; Specialize the exact same algorithm bodies with inline SSE2 operations.
compute_section_begin:
%define COMPUTE_BUILD 1
%define elementwise elementwise_compute
%define matmul matmul_compute
%define transpose_value transpose_value_compute
%define negate_value negate_value_compute
%define math_sin math_sin_compute
%define math_cos math_cos_compute
%define math_trig math_trig_compute
%define math_log math_log_compute
%define math_power math_power_compute
%define eval_node eval_node_compute
%define assignment_allowed assignment_allowed_compute
%define apply_function apply_function_compute
%define eval_call eval_call_compute
%define positive_integer positive_integer_compute
%define create_array create_array_compute
%define size_value size_value_compute
%define index_value index_value_compute
%define linspace_value linspace_value_compute
%include "src/kernels.asm"
%include "src/math.asm"
%include "src/evaluator.asm"
%include "src/workspace_functions.asm"
%undef elementwise
%undef matmul
%undef transpose_value
%undef negate_value
%undef math_sin
%undef math_cos
%undef math_trig
%undef math_log
%undef math_power
%undef eval_node
%undef assignment_allowed
%undef apply_function
%undef eval_call
%undef positive_integer
%undef create_array
%undef size_value
%undef index_value
%undef linspace_value
compute_section_end:
%undef COMPUTE_BUILD

%include "src/trace_v2.asm"
%include "src/workbench.asm"
%include "src/view.asm"
%include "src/main.asm"
section .note.GNU-stack noalloc noexec nowrite progbits

; Application translation unit; runtime modules are separately assembled and linked.
%include "include/core.inc"
%include "src/core_storage.asm"
%include "src/runtime.asm"
%include "src/parser.asm"
%include "src/kernels.asm"
%include "src/math.asm"
%include "src/evaluator.asm"
%include "src/view.asm"
%include "src/main.asm"
section .note.GNU-stack noalloc noexec nowrite progbits

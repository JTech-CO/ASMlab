; Application declarations/layouts; no storage and no libc symbols.
%ifndef ASMLAB_CORE_INC
%define ASMLAB_CORE_INC 1
%include "include/abi.inc"
%include "include/layout.inc"
%include "include/rt/api.inc"
%macro OP 1
    mov edi, %1
    call exec_sse
%endmacro
%macro SAY 1
    lea rdi, [%1]
    call rt_console_puts
%endmacro
%endif

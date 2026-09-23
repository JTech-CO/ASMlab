; Explicit Level 2 compatibility adapter, NOT a standalone runtime.
; FILE pointers, libc globals and formatting/decimal libc calls live ONLY here.
; The app receives opaque handles and must never inspect their representation.
%include "include/abi.inc"
extern printf, puts, fflush, isatty, stdin
extern fopen, fclose, fgetc, ferror, fgets, strtod
section .rodata
read_mode: db 'r',0
section .bss
stdin_handle: resq 1
script_handle: resq 1
section .text
global rt_console_printf, rt_console_puts, rt_output_flush, rt_is_tty
global rt_input_stdin, rt_input_open_read, rt_input_close
global rt_input_getc, rt_input_gets, rt_input_error
; IMPORTANT: a tail jump preserves AL (SysV vector varargs count) and all stack
; arguments. This temporary formatting API is NOT the final typed writer API.
rt_console_printf:
    jmp printf wrt ..plt
rt_console_puts:
    jmp puts wrt ..plt
rt_output_flush:
    xor edi, edi
    jmp fflush wrt ..plt
rt_is_tty:
    jmp isatty wrt ..plt
rt_input_stdin:
    mov rax, [stdin wrt ..got]
    mov rax, [rax]
    mov [stdin_handle], rax
    lea rax, [stdin_handle]
    ret
; One open script per process, matching the bounded v0.1.1 CLI.
; returns opaque pointer, or NULL (also when the script slot is busy).
rt_input_open_read:
    cmp qword [script_handle], 0
    jne .busy
    sub rsp, 8
    lea rsi, [read_mode]
    call fopen wrt ..plt
    add rsp, 8
    test rax, rax
    jz .done
    mov [script_handle], rax
    lea rax, [script_handle]
.done:
    ret
.busy:
    xor eax, eax
    ret
; Borrowed stdin is not closed. The owned script slot is invalidated even if
; fclose fails. This wrapper is deliberately single-threaded and not an API server.
rt_input_close:
    lea rax, [stdin_handle]
    cmp rdi, rax
    je .borrowed
    lea rax, [script_handle]
    cmp rdi, rax
    jne .invalid
    mov rdi, [script_handle]
    test rdi, rdi
    jz .invalid
    mov qword [script_handle], 0
    jmp fclose wrt ..plt
.borrowed:
    xor eax, eax
    ret
.invalid:
    mov eax, -1
    ret
; getc -> 0..255 or -1. error(handle) distinguishes EOF from stream error.
rt_input_getc:
    mov rdi, [rdi]
    jmp fgetc wrt ..plt
rt_input_error:
    mov rdi, [rdi]
    jmp ferror wrt ..plt
; (dst, int capacity, opaque handle) -> dst or NULL (fgets semantics).
rt_input_gets:
    mov rdx, [rdx]
    jmp fgets wrt ..plt
; (NUL string, end-pointer slot) -> XMM0 double. The application lexer still
; controls token grammar/length/finite-result policy. No homemade f64 converter
; is claimed in v0.2.0. See the independent decimal boundary tests.
global rt_decimal_from_cstr
rt_decimal_from_cstr:
    jmp strtod wrt ..plt
section .note.GNU-stack noalloc noexec nowrite progbits

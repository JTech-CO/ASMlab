; Deterministic DEVELOPMENT-ONLY syscall provider. Same fd_io.o, fake leaf OS.
; Callbacks have SysV (fd,buf,count)->signed result. NOT linked into production.
%include "include/abi.inc"
section .bss
read_hook: resq 1
write_hook: resq 1
close_hook: resq 1
section .text
global rt_test_set_io
rt_test_set_io:
    mov [read_hook], rdi
    mov [write_hook], rsi
    mov [close_hook], rdx
    ret
%macro HOOK 2
global %1
%1:
    cmp qword [%2], 0
    je %%unset
    jmp [%2]
%%unset:
    mov rax, -38
    ret
%endmacro
HOOK rt_sys_read, read_hook
HOOK rt_sys_write, write_hook
HOOK rt_sys_close, close_hook
global rt_sys_openat
rt_sys_openat:
    mov rax, -38
    ret
section .note.GNU-stack noalloc noexec nowrite progbits

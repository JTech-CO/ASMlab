; Standalone no-libc demonstration, NOT the ASMlab expression evaluator.
%include "include/abi.inc"
%include "include/rt/foundation.inc"
extern rt_strcmp, rt_strlen
extern rt_parse_u64, rt_parse_i64
extern rt_fd_open_read, rt_fd_close, rt_fd_write_all
extern rt_reader_init, rt_reader_getc
extern rt_writer_init, rt_writer_write, rt_writer_flush
extern rt_writer_cstr, rt_writer_i64, rt_writer_u64, rt_writer_hex64
section .rodata
version: db 'ASMlab 0.5.0 runtime-smoke | Linux x86-64 | no libc/CRT',10,0
help: db 'Standalone runtime foundation; not the math REPL.',10
      db '  --version | --echo | --cat FILE | --u64 N | --i64 N | --hex64 N',10,0
arg_version: db '--version',0
arg_echo: db '--echo',0
arg_cat: db '--cat',0
arg_u64: db '--u64',0
arg_i64: db '--i64',0
arg_hex: db '--hex64',0
newline: db 10,0
bad_args: db 'runtime-smoke: invalid arguments or integer',10
bad_args_len: equ $-bad_args
bad_io: db 'runtime-smoke: I/O failure',10
bad_io_len: equ $-bad_io
section .bss
alignb 16
reader: resb RT_READER_SIZE
writer: resb RT_WRITER_SIZE
one_byte: resb 1
section .text
global rt_program_main
rt_program_main:
    FRAME 16
    mov r12, rdi
    mov r13, rsi
    mov qword [rsp], -1          ; owned fd, if any
    lea rdi, [writer]
    mov esi, 1
    call rt_writer_init
    cmp r12, 1
    je .help
    mov r14, [r13+8]
    mov rdi, r14
    lea rsi, [arg_version]
    call rt_strcmp
    test eax, eax
    jz .version
    mov rdi, r14
    lea rsi, [arg_echo]
    call rt_strcmp
    test eax, eax
    jz .echo
    mov rdi, r14
    lea rsi, [arg_cat]
    call rt_strcmp
    test eax, eax
    jz .cat
    cmp r12, 3
    jne .args_error
    xor r15d, r15d
    mov rdi, r14
    lea rsi, [arg_u64]
    call rt_strcmp
    test eax, eax
    jz .number
    inc r15d
    mov rdi, r14
    lea rsi, [arg_i64]
    call rt_strcmp
    test eax, eax
    jz .number
    inc r15d
    mov rdi, r14
    lea rsi, [arg_hex]
    call rt_strcmp
    test eax, eax
    jnz .args_error
.number:
    mov rdi, [r13+16]
    call rt_strlen
    mov rsi, rax
    mov rdi, [r13+16]
    cmp r15d, 1
    je .signed_parse
    call rt_parse_u64
    jmp .parsed
.signed_parse:
    call rt_parse_i64
.parsed:
    test rax, rax
    jnz .args_error
    mov rsi, rdx
    lea rdi, [writer]
    cmp r15d, 1
    je .signed_format
    cmp r15d, 2
    je .hex_format
    call rt_writer_u64
    jmp .number_done
.signed_format:
    call rt_writer_i64
    jmp .number_done
.hex_format:
    call rt_writer_hex64
.number_done:
    test rax, rax
    jnz .io_error
    lea rdi, [writer]
    lea rsi, [newline]
    call rt_writer_cstr
    jmp .flush
.version:
    cmp r12, 2
    jne .args_error
    lea rsi, [version]
    jmp .print
.help:
    lea rsi, [help]
.print:
    lea rdi, [writer]
    call rt_writer_cstr
    jmp .flush
.echo:
    cmp r12, 2
    jne .args_error
    xor esi, esi
    jmp .reader
.cat:
    cmp r12, 3
    jne .args_error
    mov rdi, [r13+16]
    call rt_fd_open_read
    test rax, rax
    js .io_error
    mov [rsp], rax
    mov rsi, rax
.reader:
    lea rdi, [reader]
    call rt_reader_init
.loop:
    lea rdi, [reader]
    call rt_reader_getc
    cmp rax, -1
    je .end_input
    test rax, rax
    js .io_error
    mov [one_byte], al
    lea rdi, [writer]
    lea rsi, [one_byte]
    mov edx, 1
    call rt_writer_write
    test rax, rax
    jnz .io_error
    jmp .loop
.end_input:
    xor eax, eax
.flush:
    test rax, rax
    jnz .io_error
    lea rdi, [writer]
    call rt_writer_flush
    test rax, rax
    jnz .io_error
    xor ebx, ebx
    jmp .close
.args_error:
    lea rsi, [bad_args]
    mov edx, bad_args_len
    jmp .error
.io_error:
    lea rsi, [bad_io]
    mov edx, bad_io_len
.error:
    mov edi, 2
    call rt_fd_write_all
    mov ebx, 2
.close:
    mov rdi, [rsp]
    cmp rdi, -1
    je .return
    call rt_fd_close
    test rax, rax
    jz .return
    mov ebx, 2
.return:
    mov eax, ebx
    DONE
section .note.GNU-stack noalloc noexec nowrite progbits

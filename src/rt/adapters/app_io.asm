; L3 application adapter: fixed Reader/Writer contexts + Linux syscall only.
; No FILE*, libc, CRT, dynamic allocation, network or external process execution.
%include "include/abi.inc"
%include "include/rt/foundation.inc"
extern rt_reader_init, rt_reader_getc, rt_reader_error
extern rt_writer_init, rt_writer_write, rt_writer_flush, rt_writer_cstr
extern rt_fd_open_read, rt_fd_close, rt_fd_write_all, rt_sys_ioctl, rt_strlen
section .bss
alignb 16
console_writer: resb RT_WRITER_SIZE
stdin_reader: resb RT_READER_SIZE
script_reader: resb RT_READER_SIZE
script_live: resq 1
section .rodata
newline: db 10
output_error: db 'ASMlab: output write/flush failed.',10
output_error_len: equ $-output_error
section .text
global rt_host_init, rt_host_finish
rt_host_init:
    FRAME 0
    lea rdi, [console_writer]
    mov esi, 1
    call rt_writer_init
    lea rdi, [stdin_reader]
    xor esi, esi
    call rt_reader_init
    xor eax, eax
    DONE
; (main exit status) -> final status. All return paths flush, including --help.
rt_host_finish:
    FRAME 0
    mov r12d, edi
    cmp qword [script_live], 0
    je .flush
    lea rdi, [script_reader]
    call rt_input_close
    test eax, eax
    jz .flush
    mov r12d, 2
.flush:
    call rt_output_flush
    test rax, rax
    jz .done
    mov edi, 2
    lea rsi, [output_error]
    mov edx, output_error_len
    call rt_fd_write_all
    mov r12d, 2
.done:
    mov eax, r12d
    DONE
; (bytes,length) -> writer status. Private frontend formatting sink.
global rt_console_write_bytes, rt_console_fault
rt_console_write_bytes:
    mov rdx, rsi
    mov rsi, rdi
    lea rdi, [console_writer]
    jmp rt_writer_write
; (negative error) -> latch first output/format error.
rt_console_fault:
    cmp qword [console_writer+RT_W_STATUS], 0
    jne .done
    mov [console_writer+RT_W_STATUS], rdi
.done:
    mov rax, [console_writer+RT_W_STATUS]
    ret
global rt_console_puts, rt_output_flush, rt_is_tty
rt_console_puts:
    FRAME 0
    mov rsi, rdi
    lea rdi, [console_writer]
    call rt_writer_cstr
    test rax, rax
    jnz .done
    lea rdi, [newline]
    mov esi, 1
    call rt_console_write_bytes
.done:
    DONE
rt_output_flush:
    lea rdi, [console_writer]
    jmp rt_writer_flush
rt_is_tty:
    FRAME 48
    mov esi, 0x5401            ; TCGETS, Linux x86-64 struct termios fits 48 bytes
    mov rdx, rsp
    call rt_sys_ioctl
    test rax, rax
    sete al
    movzx eax, al
    DONE
global rt_input_stdin, rt_input_open_read, rt_input_close
rt_input_stdin:
    lea rax, [stdin_reader]    ; Never reinitialize: REPL and replay share buffer.
    ret
rt_input_open_read:
    FRAME 0
    cmp qword [script_live], 0
    jne .fail
    call rt_fd_open_read
    test rax, rax
    js .fail
    mov rsi, rax
    lea rdi, [script_reader]
    call rt_reader_init
    mov qword [script_live], 1
    lea rax, [script_reader]
    DONE
.fail:
    xor eax, eax
    DONE
rt_input_close:
    lea rax, [stdin_reader]
    cmp rdi, rax
    je .borrowed
    lea rax, [script_reader]
    cmp rdi, rax
    jne .bad
    cmp qword [script_live], 0
    je .bad
    mov qword [script_live], 0
    mov rdi, [script_reader+RT_R_FD]
    sub rsp, 8
    call rt_fd_close
    add rsp, 8
    test rax, rax
    jns .borrowed
.bad:
    mov eax, -1
    ret
.borrowed:
    xor eax, eax
    ret
global rt_input_getc, rt_input_error, rt_input_gets
rt_input_getc:
    sub rsp, 8
    call rt_reader_getc
    add rsp, 8
    test rax, rax
    jns .done
    mov eax, -1               ; core queries rt_input_error for EOF/error
.done:
    ret
rt_input_error:
    sub rsp, 8
    call rt_reader_error
    add rsp, 8
    test rax, rax
    setne al
    movzx eax, al
    ret
; (dst, capacity, live reader) -> dst or NULL. Replay's bounded line input.
; All reads use the same Reader as the expression loop (no buffered input loss).
rt_input_gets:
    FRAME 0
    mov r12, rdi
    movsxd r13, esi
    mov r14, rdx
    xor ebx, ebx
    cmp r13, 1
    jle .fail
    dec r13
.loop:
    cmp rbx, r13
    jae .ok
    mov rdi, r14
    call rt_reader_getc
    cmp rax, -2
    je .fail
    cmp rax, -1
    je .eof
    mov [r12+rbx], al
    inc rbx
    cmp al, 10
    jne .loop
.ok:
    mov byte [r12+rbx], 0
    mov rax, r12
    DONE
.eof:
    test rbx, rbx
    jnz .ok
.fail:
    xor eax, eax
    DONE
section .note.GNU-stack noalloc noexec nowrite progbits

; TUI only: consume already buffered input without making a syscall or changing EOF.
; RAX=byte0..255, -1=no pending byte. Same Reader as canonical REPL/replay.
section .text
global rt_input_try_byte
rt_input_try_byte:
    mov rcx, [stdin_reader+RT_R_POS]
    cmp rcx, [stdin_reader+RT_R_END]
    jae .empty
    lea rdx, [stdin_reader+RT_R_BUF]
    movzx eax, byte [rdx+rcx]
    inc rcx
    mov [stdin_reader+RT_R_POS], rcx
    ret
.empty:
    mov rax, -1
    ret

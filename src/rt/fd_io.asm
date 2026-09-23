; Independent fd + buffered I/O foundation. All errors are negative Linux errno.
; These routines are NOT yet used by the full application's libc stream adapter.
%include "include/abi.inc"
%include "include/rt/foundation.inc"
extern rt_sys_read, rt_sys_write, rt_sys_openat, rt_sys_close
extern rt_memcpy, rt_memmove, rt_strlen
extern rt_format_u64, rt_format_i64, rt_format_hex64
section .text
global rt_fd_open_read, rt_fd_close, rt_fd_read, rt_fd_write_all
; path -> fd or -errno. Read-only, close-on-exec; no global errno.
rt_fd_open_read:
    mov rsi, rdi
    mov rdi, -100                 ; AT_FDCWD
    mov edx, 0x80000              ; O_RDONLY | O_CLOEXEC
    xor ecx, ecx
    jmp rt_sys_openat
rt_fd_close:
    jmp rt_sys_close              ; Linux close is deliberately NOT retried.
; (fd,buffer,length) -> bytes >=0 or -errno. Retry only EINTR.
rt_fd_read:
    FRAME 0
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
.retry:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call rt_sys_read
    cmp rax, -RT_EINTR
    je .retry
    DONE
; (fd,bytes,length) -> RAX status:0/-errno, RDX bytes actually written.
; EAGAIN propagates (no busy spin); no-progress write -> EIO; count 0 -> success.
rt_fd_write_all:
    FRAME 0
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor r15d, r15d
.loop:
    cmp r15, r14
    jae .ok
    mov rdi, r12
    lea rsi, [r13+r15]
    mov rdx, r14
    sub rdx, r15
    call rt_sys_write
    cmp rax, -RT_EINTR
    je .loop
    test rax, rax
    js .done
    jz .stalled
    ; A kernel cannot return more than requested. This also fails closed for
    ; a broken development fault-injection provider.
    mov rcx, r14
    sub rcx, r15
    cmp rax, rcx
    ja .stalled
    add r15, rax
    jmp .loop
.ok:
    xor eax, eax
    jmp .done
.stalled:
    mov rax, -RT_EIO
.done:
    mov rdx, r15
    DONE

global rt_reader_init, rt_reader_getc, rt_reader_error
; (storage, fd) -> 0. Borrow fd; initialize fixed header, not the data buffer.
rt_reader_init:
    mov [rdi+RT_R_FD], rsi
    mov qword [rdi+RT_R_POS], 0
    mov qword [rdi+RT_R_END], 0
    mov qword [rdi+RT_R_STATUS], 0
    xor eax, eax
    ret
; (reader) -> byte (0..255), -1 EOF, -2 error. RDX = raw -errno on error, else 0.
; Internal status is 0=ready, 1=EOF, -errno=error, so EPERM cannot alias EOF.
; Sticky EOF/error avoids repeated syscalls. Reinitialize to reuse the reader.
rt_reader_getc:
    FRAME 0
    mov r12, rdi
    mov rax, [r12+RT_R_STATUS]
    test rax, rax
    jnz .status
    mov rax, [r12+RT_R_POS]
    cmp rax, [r12+RT_R_END]
    jb .buffered
    mov rdi, [r12+RT_R_FD]
    lea rsi, [r12+RT_R_BUF]
    mov edx, RT_IO_CAP
    call rt_fd_read
    test rax, rax
    js .failure
    jz .eof
    cmp rax, RT_IO_CAP
    ja .broken_provider
    mov [r12+RT_R_END], rax
    mov qword [r12+RT_R_POS], 0
    xor eax, eax
.buffered:
    inc qword [r12+RT_R_POS]
    movzx eax, byte [r12+RT_R_BUF+rax]
    xor edx, edx
    DONE
.broken_provider:
    mov rax, -RT_EIO
    jmp .failure
.eof:
    mov eax, 1
.failure:
    mov [r12+RT_R_STATUS], rax
.status:
    xor edx, edx
    cmp rax, 1
    je .return_eof
    mov rdx, rax
    mov rax, -2
    DONE
.return_eof:
    mov rax, -1
    DONE
rt_reader_error:
    mov rax, [rdi+RT_R_STATUS]
    test rax, rax
    js .done
    xor eax, eax
.done:
    ret

global rt_writer_init, rt_writer_write, rt_writer_flush
rt_writer_init:
    mov [rdi+RT_W_FD], rsi
    mov qword [rdi+RT_W_USED], 0
    mov qword [rdi+RT_W_STATUS], 0
    xor eax, eax
    ret
; (writer) -> status, RDX bytes written in THIS flush.
; On partial failure discard written prefix, keep unwritten suffix in buffer,
; set sticky error. Later calls return it, rather than duplicating output.
rt_writer_flush:
    FRAME 16
    mov r12, rdi
    mov rax, [r12+RT_W_STATUS]
    xor edx, edx
    test rax, rax
    jnz .done
    mov rdi, [r12+RT_W_FD]
    lea rsi, [r12+RT_W_BUF]
    mov rdx, [r12+RT_W_USED]
    call rt_fd_write_all
    mov [rsp], rax
    mov [rsp+8], rdx
    sub [r12+RT_W_USED], rdx
    test rax, rax
    jz .restore
    mov [r12+RT_W_STATUS], rax
    test rdx, rdx
    jz .restore
    lea rdi, [r12+RT_W_BUF]
    lea rsi, [rdi+rdx]
    mov rdx, [r12+RT_W_USED]
    call rt_memmove
.restore:
    mov rax, [rsp]
    mov rdx, [rsp+8]
.done:
    DONE
; (writer, bytes, length) -> RAX status, RDX INPUT bytes accepted this call.
; Accepted bytes may be buffered, NOT durable. Caller must check final flush.
; Input span must not alias the writer's internal buffer.
rt_writer_write:
    FRAME 16
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor r15d, r15d
    mov rax, [r12+RT_W_STATUS]
    test rax, rax
    jnz .done
.loop:
    cmp r15, r14
    jae .ok
    mov rax, [r12+RT_W_USED]
    cmp rax, RT_IO_CAP
    jb .copy
    mov rdi, r12
    call rt_writer_flush
    test rax, rax
    jnz .done
    mov rax, [r12+RT_W_USED]
.copy:
    mov ebx, RT_IO_CAP
    sub rbx, rax
    mov rcx, r14
    sub rcx, r15
    cmp rbx, rcx
    cmova rbx, rcx
    lea rdi, [r12+RT_W_BUF+rax]
    lea rsi, [r13+r15]
    mov rdx, rbx
    call rt_memcpy
    add [r12+RT_W_USED], rbx
    add r15, rbx
    jmp .loop
.ok:
    xor eax, eax
.done:
    mov rdx, r15
    DONE

global rt_writer_cstr, rt_writer_u64, rt_writer_i64, rt_writer_hex64
rt_writer_cstr:
    FRAME 0
    mov r12, rdi
    mov r13, rsi
    mov rdi, rsi
    call rt_strlen
    mov rdx, rax
    mov rdi, r12
    mov rsi, r13
    call rt_writer_write
    DONE
%macro INTEGER_WRITER 2
%1:
    FRAME 32
    mov r12, rdi
    mov rdx, rsi
    mov rdi, rsp
    mov esi, 32
    call %2
    test rax, rax
    js %%done
    mov rdx, rax
    mov rdi, r12
    mov rsi, rsp
    call rt_writer_write
%%done:
    DONE
%endmacro
INTEGER_WRITER rt_writer_u64, rt_format_u64
INTEGER_WRITER rt_writer_i64, rt_format_i64
INTEGER_WRITER rt_writer_hex64, rt_format_hex64
section .note.GNU-stack noalloc noexec nowrite progbits

; Linux x86-64 workbench host. libc-free, kernel termios (36 bytes), not libc termios.
; Signal handlers only set flags. Restoration is performed at a safe UI boundary.
%include "include/abi.inc"
extern rt_sys_ioctl, rt_fd_write_all, rt_input_try_byte
section .rodata
terminal_signals: dq 1,2,3,13,15,18,20,28
terminal_enter_text: db 27,'[?1049h',27,'[?25l',27,'[2J',27,'[H'
terminal_enter_len: equ $-terminal_enter_text
terminal_leave_text: db 27,'[0m',27,'[?25h',27,'[?1049l'
terminal_leave_len: equ $-terminal_leave_text
section .data
align 8
terminal_action: dq terminal_handler, 0x04000000, terminal_sigreturn, 0
section .bss
alignb 16
terminal_saved: resb 36
terminal_raw: resb 36
terminal_old_actions: resb 8*32
terminal_actions_count: resq 1
terminal_live: resq 1
terminal_exit_signal: resq 1
terminal_suspend: resq 1
terminal_resize: resq 1
terminal_pollfd: resb 8
terminal_key: resb 1
terminal_winsize: resb 8
section .text
global rt_terminal_enter, rt_terminal_leave, rt_terminal_poll, rt_terminal_size
terminal_sigreturn:
    mov eax, 15
    syscall
terminal_handler:
    cmp edi, 28
    je .resize
    cmp edi, 18
    je .resize
    cmp edi, 20
    je .suspend
    mov [terminal_exit_signal], rdi
    ret
.resize:
    mov qword [terminal_resize], 1
    ret
.suspend:
    mov qword [terminal_suspend], 1
    ret
rt_terminal_enter:
    FRAME 0
    cmp qword [terminal_live], 0
    jne .busy
    mov qword [terminal_exit_signal], 0
    mov qword [terminal_suspend], 0
    mov qword [terminal_actions_count], 0
    xor edi, edi
    mov esi, 0x5401
    lea rdx, [terminal_saved]
    call rt_sys_ioctl
    test rax, rax
    js .done
    lea rsi, [terminal_saved]
    lea rdi, [terminal_raw]
    mov ecx, 36
    rep movsb
    ; c_lflag: retain ISIG, disable canonical/echo/echo-newline/extended input.
    and dword [terminal_raw+12], ~ (2 | 8 | 64 | 32768)
    ; c_iflag: no XON/XOFF or CR translation. Explicit screen CRLF needs no OPOST.
    and dword [terminal_raw], ~(1024 | 256 | 64 | 128)
    and dword [terminal_raw+4], ~1      ; OPOST restored on exit/suspend
    mov byte [terminal_raw+17+6], 1      ; VMIN
    mov byte [terminal_raw+17+5], 0      ; VTIME
    xor ebx, ebx
.install:
    cmp ebx, 8
    jae .raw
    mov rdi, [terminal_signals+rbx*8]
    lea rsi, [terminal_action]
    mov rdx, rbx
    shl rdx, 5
    lea rdx, [terminal_old_actions+rdx]
    mov r10d, 8                        ; kernel sigset size, NOT libc sizeof
    mov eax, 13                        ; rt_sigaction
    syscall
    test rax, rax
    js .unwind
    inc ebx
    mov [terminal_actions_count], rbx
    jmp .install
.raw:
    call terminal_raw_enable
    test rax, rax
    js .unwind
    mov qword [terminal_live], 1
    call terminal_screen_enter
    test rax, rax
    js .unwind_live
    xor eax, eax
.done:
    DONE
.busy:
    mov rax, -16
    DONE
.unwind_live:
    mov r12, rax
    call rt_terminal_leave
    mov rax, r12
    DONE
.unwind:
    mov r12, rax
    call terminal_actions_restore
    mov rax, r12
    DONE
terminal_raw_enable:
    xor edi, edi
    mov esi, 0x5402                    ; TCSETS, no input discard
    lea rdx, [terminal_raw]
    jmp rt_sys_ioctl
terminal_restore_mode:
    xor edi, edi
    mov esi, 0x5402
    lea rdx, [terminal_saved]
    jmp rt_sys_ioctl
terminal_screen_enter:
    mov edi, 1
    lea rsi, [terminal_enter_text]
    mov edx, terminal_enter_len
    jmp rt_fd_write_all
terminal_screen_leave:
    mov edi, 1
    lea rsi, [terminal_leave_text]
    mov edx, terminal_leave_len
    jmp rt_fd_write_all
terminal_actions_restore:
    FRAME 0
    mov rbx, [terminal_actions_count]
.loop:
    test rbx, rbx
    jz .done
    dec rbx
    mov rdi, [terminal_signals+rbx*8]
    mov rsi, rbx
    shl rsi, 5
    lea rsi, [terminal_old_actions+rsi]
    xor edx, edx
    mov r10d, 8
    mov eax, 13
    syscall
    jmp .loop
.done:
    mov qword [terminal_actions_count], 0
    DONE
rt_terminal_leave:
    FRAME 0
    xor r12d, r12d
    cmp qword [terminal_live], 0
    je .actions
    call terminal_restore_mode
    mov r12, rax
    call terminal_screen_leave
    test r12, r12
    cmovz r12, rax
    mov qword [terminal_live], 0
.actions:
    call terminal_actions_restore
    mov rax, r12
    DONE
; timeout(ms) -> byte0..255; -1 timeout/interrupted; -2 EOF/IO; -3 termination with RDX=signal.
rt_terminal_poll:
    FRAME 0
    mov r12d, edi
    mov rdx, [terminal_exit_signal]
    test rdx, rdx
    jnz .signal
    cmp qword [terminal_suspend], 0
    je .buffer
    mov qword [terminal_suspend], 0
    call terminal_restore_mode
    test rax, rax
    js .error
    call terminal_screen_leave
    mov eax, 39                         ; getpid
    syscall
    mov rdi, rax
    mov esi, 19                         ; stop only after restoring terminal
    mov eax, 62                         ; kill
    syscall
    ; Resumes here after SIGCONT. A later render will repaint the current snapshot.
    mov rdx, [terminal_exit_signal]
    test rdx, rdx
    jnz .signal
    call terminal_raw_enable
    test rax, rax
    js .error
    call terminal_screen_enter
    test rax, rax
    js .error
    mov qword [terminal_resize], 1
.buffer:
    call rt_input_try_byte              ; do not lose canonical REPL read-ahead
    cmp rax, 0
    jge .done
    mov dword [terminal_pollfd], 0
    mov word [terminal_pollfd+4], 1     ; POLLIN
    mov word [terminal_pollfd+6], 0
    lea rdi, [terminal_pollfd]
    mov esi, 1
    mov edx, r12d
    mov eax, 7                         ; poll
    syscall
    cmp rax, -4
    je .timeout
    test rax, rax
    js .error
    jz .timeout
    test word [terminal_pollfd+6], 1
    jz .error                          ; HUP/ERR/NVAL without readable data
    xor eax, eax                       ; read exactly one byte, after readiness
    xor edi, edi
    lea rsi, [terminal_key]
    mov edx, 1
    syscall
    cmp rax, -4
    je .timeout
    cmp rax, 1
    jne .error
    movzx eax, byte [terminal_key]
.done:
    xor edx, edx
    DONE
.timeout:
    mov rdx, [terminal_exit_signal]
    test rdx, rdx
    jnz .signal
    mov rax, -1
    DONE
.error:
    mov rax, -2
    DONE
.signal:
    mov rax, -3
    DONE
; RAX=columns, RDX=rows; RCX=redraw-needed flag (includes suspend/resume).
rt_terminal_size:
    FRAME 0
    mov edi, 1
    mov esi, 0x5413
    lea rdx, [terminal_winsize]
    call rt_sys_ioctl
    test rax, rax
    js .fallback
    movzx eax, word [terminal_winsize+2]
    movzx edx, word [terminal_winsize]
    test eax, eax
    jz .fallback
    test edx, edx
    jz .fallback
    jmp .done
.fallback:
    mov eax, 80
    mov edx, 24
.done:
    mov rcx, [terminal_resize]
    mov qword [terminal_resize], 0
    DONE
section .note.GNU-stack noalloc noexec nowrite progbits

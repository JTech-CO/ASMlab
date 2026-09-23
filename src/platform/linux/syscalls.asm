; Linux x86-64 raw syscall ABI ONLY. No libc syscall(), errno or TLS.
%include "include/abi.inc"
section .text
global rt_sys_read, rt_sys_write, rt_sys_openat, rt_sys_close, rt_sys_ioctl, rt_sys_exit
rt_sys_read:
    xor eax, eax
    syscall
    ret
rt_sys_write:
    mov eax, 1
    syscall
    ret
rt_sys_openat:
    mov r10, rcx            ; SysV fourth argument -> Linux syscall fourth argument
    mov eax, 257
    syscall
    ret
rt_sys_close:
    mov eax, 3
    syscall                ; Do NOT retry close on EINTR on Linux.
    ret
rt_sys_ioctl:
    mov eax, 16
    syscall
    ret
rt_sys_exit:
    mov eax, 231            ; exit_group(status), does not return
    syscall
    ud2
section .note.GNU-stack noalloc noexec nowrite progbits

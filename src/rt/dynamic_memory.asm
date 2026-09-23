; Quota-accounted anonymous mappings. Private header is 32 bytes.
; This is a bounded single-threaded allocator, NOT a general malloc ABI.
%include "include/abi.inc"
extern rt_sys_mmap, rt_sys_munmap, rt_memory_abort
section .data
heap_limit: dq 67108864
section .bss
heap_used: resq 1
heap_peak: resq 1
heap_live: resq 1
heap_maps: resq 1
heap_unmaps: resq 1
section .text
global rt_heap_alloc, rt_heap_free, rt_memory_set_limit, rt_memory_stats
; rdi = positive payload size. rax=aligned pointer, rdx=0; or rax=0,rdx=-errno.
; The full page-rounded mapping, including metadata, is charged BEFORE use.
rt_heap_alloc:
    FRAME 0
    mov r12, rdi
    test rdi, rdi
    jz .invalid
    mov r13, rdi
    add r13, 32+4095
    jc .overflow
    and r13, -4096
    mov rax, [heap_used]
    add rax, r13
    jc .overflow
    cmp rax, [heap_limit]
    ja .quota
    xor edi, edi
    mov rsi, r13
    mov edx, 3                  ; PROT_READ | PROT_WRITE
    mov ecx, 0x22               ; MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    call rt_sys_mmap
    cmp rax, -4095
    jae .kernel_error
    ; Anonymous mappings are zero initialized. Do not expose the header.
    mov [rax], r13
    mov [rax+8], r12
    mov qword [rax+16], 0
    mov qword [rax+24], 0
    add [heap_used], r13
    mov rdx, [heap_used]
    cmp rdx, [heap_peak]
    jbe .count
    mov [heap_peak], rdx
.count:
    inc qword [heap_live]
    inc qword [heap_maps]
    add rax, 32
    xor edx, edx
    DONE
.invalid:
    mov rdx, -22
    jmp .failed
.overflow:
    mov rdx, -75
    jmp .failed
.quota:
    mov rdx, -12
    jmp .failed
.kernel_error:
    mov rdx, rax
.failed:
    xor eax, eax
    DONE
; Own live pointer or NULL only. Duplicate/arbitrary free is outside the ABI.
; A valid mapping's unexpected munmap failure is fatal; never fake a release.
rt_heap_free:
    test rdi, rdi
    jz .null
    FRAME 0
    sub rdi, 32
    mov r12, [rdi]
    mov rsi, r12
    call rt_sys_munmap
    test rax, rax
    jnz .fatal
    sub [heap_used], r12
    dec qword [heap_live]
    inc qword [heap_unmaps]
    xor eax, eax
    DONE
.fatal:
    jmp rt_memory_abort
.null:
    xor eax, eax
    ret
; Bytes; 1MiB..1GiB, >=live mapped bytes. No reallocations or resets.
rt_memory_set_limit:
    cmp rdi, 1048576
    jb .bad
    cmp rdi, 1073741824
    ja .bad
    cmp rdi, [heap_used]
    jb .busy
    mov [heap_limit], rdi
    xor eax, eax
    ret
.bad:
    mov rax, -22
    ret
.busy:
    mov rax, -16
    ret
; rdi = writable 48 bytes. used, peak, quota, live, successful maps, unmaps.
rt_memory_stats:
    mov rax, [heap_used]
    mov [rdi], rax
    mov rax, [heap_peak]
    mov [rdi+8], rax
    mov rax, [heap_limit]
    mov [rdi+16], rax
    mov rax, [heap_live]
    mov [rdi+24], rax
    mov rax, [heap_maps]
    mov [rdi+32], rax
    mov rax, [heap_unmaps]
    mov [rdi+40], rax
    xor eax, eax
    ret
section .note.GNU-stack noalloc noexec nowrite progbits

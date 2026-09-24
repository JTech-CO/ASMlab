; One arithmetic source, two assembly-time specializations. No runtime JIT.
%ifndef ASMLAB_OBSERVATION_INC
%define ASMLAB_OBSERVATION_INC 1
%macro OP 1
%ifdef COMPUTE_BUILD
%if %1 = O_ADDSD
    addsd xmm0, xmm1
%elif %1 = O_SUBSD
    subsd xmm0, xmm1
%elif %1 = O_MULSD
    mulsd xmm0, xmm1
%elif %1 = O_DIVSD
    divsd xmm0, xmm1
%elif %1 = O_SQRTSD
    sqrtsd xmm0, xmm1
%elif %1 = O_ADDPD
    addpd xmm0, xmm1
%elif %1 = O_SUBPD
    subpd xmm0, xmm1
%elif %1 = O_MULPD
    mulpd xmm0, xmm1
%elif %1 = O_DIVPD
    divpd xmm0, xmm1
%elif %1 = O_SQRTPD
    sqrtpd xmm0, xmm1
%elif %1 = O_MOVAPD
    movapd xmm0, xmm1
%elif %1 = O_XORPD
    xorpd xmm0, xmm1
%else
%error Unsupported compute opcode
%endif
%else
    mov edi, %1
    call exec_sse
%endif
%endmacro
%macro TRACE_SET 2
%ifndef COMPUTE_BUILD
    mov qword [%1], %2
%endif
%endmacro
%macro TRACE_SHAPE 1
%ifndef COMPUTE_BUILD
    push rax
    mov rax, [%1]
    mov [trace_rows], rax
    mov rax, [%1+8]
    mov [trace_cols], rax
    pop rax
%endif
%endmacro
%endif

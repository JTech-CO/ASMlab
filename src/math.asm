; Original small-range polynomial kernels. No libm, x87 FSIN/FCOS, or BLAS.
; sin/cos: split pi/2 range reduction, |x|<=1e6, |r|<=pi/4.
; log: normalize x=2^k*m, atanh series, |z|<=0.171573.
; These are bounded real float64 kernels, not correctly-rounded libm replacements.
section .rodata
sin_coeff:
    dq 2.8114572543455206e-15, -7.647163731819816e-13
    dq 1.6059043836821613e-10, -2.505210838544172e-8
    dq 2.7557319223985893e-6, -1.9841269841269841e-4
    dq 8.333333333333333e-3, -1.6666666666666666e-1, 1.0
cos_coeff:
    dq -1.5619206968586225e-16, 4.779477332387385e-14
    dq -1.1470745597729725e-11, 2.08767569878681e-9
    dq -2.755731922398589e-7, 2.48015873015873e-5
    dq -1.388888888888889e-3, 4.1666666666666664e-2, -0.5, 1.0
log_coeff:
    dq 0.04, 0.043478260869565216, 0.047619047619047616
    dq 0.05263157894736842, 0.058823529411764705
    dq 0.06666666666666667, 0.07692307692307693
    dq 0.09090909090909091, 0.1111111111111111
    dq 0.14285714285714285, 0.2, 0.3333333333333333, 1.0
section .text
math_sin:
    xor esi, esi
    jmp math_trig
math_cos:
    mov esi, 1
    jmp math_trig

math_trig:
    FRAME 32
    mov r12d, esi
    movsd [rsp], xmm0
    movapd xmm1, xmm0
    andpd xmm1, [abs_mask]
    ucomisd xmm1, [trig_bound]
    ja .domain
    ; Preserve sin(-0), return cos(+-0)=1 exactly.
    pxor xmm2, xmm2
    ucomisd xmm1, xmm2
    jne .reduce
    test r12d, r12d
    jz .return
    movsd xmm0, [one]
    jmp .return
.reduce:
    movsd xmm1, [inv_pio2]
    OP O_MULSD
    cvtsd2si rbx, xmm0
    pxor xmm0, xmm0
    cvtsi2sd xmm0, rbx
    movsd xmm1, [pio2_hi]
    OP O_MULSD
    movapd xmm1, xmm0
    movsd xmm0, [rsp]
    OP O_SUBSD
    movsd [rsp+8], xmm0
    pxor xmm0, xmm0
    cvtsi2sd xmm0, rbx
    movsd xmm1, [pio2_lo]
    OP O_MULSD
    movapd xmm1, xmm0
    movsd xmm0, [rsp+8]
    OP O_SUBSD
    movsd [rsp+16], xmm0
    movapd xmm1, xmm0
    OP O_MULSD
    movapd xmm7, xmm0
    ; sin: even quadrant -> sin polynomial; cos: odd -> sin polynomial.
    mov rax, rbx
    xor rax, r12
    and eax, 1
    mov r14d, eax
    test r12d, r12d
    jnz .cos_sign
    mov r15, rbx
    jmp .sign_ready
.cos_sign:
    lea r15, [rbx+1]
.sign_ready:
    and r15d, 2
    test r14d, r14d
    jnz .cos_poly
    lea r13, [sin_coeff]
    mov r12d, 9
    jmp .poly
.cos_poly:
    lea r13, [cos_coeff]
    mov r12d, 10
.poly:
    movsd xmm0, [r13]
    mov ebx, 1
.horner:
    movapd xmm1, xmm7
    OP O_MULSD
    movsd xmm1, [r13+rbx*8]
    OP O_ADDSD
    inc ebx
    cmp ebx, r12d
    jb .horner
    test r14d, r14d
    jnz .sign
    movsd xmm1, [rsp+16]
    OP O_MULSD
.sign:
    test r15d, r15d
    jz .return
    movapd xmm1, xmm0
    pxor xmm0, xmm0
    OP O_SUBSD
.return:
    DONE
.domain:
    lea rdi, [err_trig]
    call set_error
    pxor xmm0, xmm0
    DONE

math_log:
    FRAME 16
    pxor xmm1, xmm1
    ucomisd xmm0, xmm1
    jbe .domain
    xor r12d, r12d
    movq rax, xmm0
    mov rcx, rax
    shr rcx, 52
    and ecx, 0x7ff
    test ecx, ecx
    jnz .normalize
    movsd xmm1, [scale_subnormal]
    OP O_MULSD
    mov r12, -54
    movq rax, xmm0
    mov rcx, rax
    shr rcx, 52
    and ecx, 0x7ff
.normalize:
    sub rcx, 1023
    add r12, rcx
    mov rdx, 0x000fffffffffffff
    and rax, rdx
    mov rdx, 0x3ff0000000000000
    or rax, rdx
    movq xmm0, rax
    ucomisd xmm0, [sqrt_two]
    jbe .z
    movsd xmm1, [half]
    OP O_MULSD
    inc r12
.z:
    movapd xmm6, xmm0
    movsd xmm1, [one]
    OP O_SUBSD
    movsd [rsp], xmm0
    movapd xmm0, xmm6
    movsd xmm1, [one]
    OP O_ADDSD
    movapd xmm1, xmm0
    movsd xmm0, [rsp]
    OP O_DIVSD
    movsd [rsp], xmm0
    movapd xmm1, xmm0
    OP O_MULSD
    movapd xmm7, xmm0
    lea r13, [log_coeff]
    movsd xmm0, [r13]
    mov ebx, 1
.horner:
    movapd xmm1, xmm7
    OP O_MULSD
    movsd xmm1, [r13+rbx*8]
    OP O_ADDSD
    inc ebx
    cmp ebx, 13
    jb .horner
    movsd xmm1, [rsp]
    OP O_MULSD
    movsd xmm1, [two]
    OP O_MULSD
    movsd [rsp+8], xmm0
    pxor xmm0, xmm0
    cvtsi2sd xmm0, r12
    movsd xmm1, [ln_two]
    OP O_MULSD
    movsd xmm1, [rsp+8]
    OP O_ADDSD
    DONE
.domain:
    lea rdi, [err_log]
    call set_error
    pxor xmm0, xmm0
    DONE

; Integer scalar exponentiation by squaring. 0^0 is defined as 1.
math_power:
    FRAME 16
    movsd [rsp], xmm0
    movapd xmm2, xmm1
    andpd xmm2, [abs_mask]
    ucomisd xmm2, [pow_bound]
    ja .domain
    cvttsd2si r12, xmm1
    pxor xmm2, xmm2
    cvtsi2sd xmm2, r12
    ucomisd xmm1, xmm2
    jne .domain
    test r12, r12
    jns .ready
    movq rax, xmm0
    shl rax, 1
    jz .divzero
    movapd xmm1, xmm0
    movsd xmm0, [one]
    OP O_DIVSD
    movsd [rsp], xmm0
    neg r12
.ready:
    movsd xmm0, [one]
    movsd [rsp+8], xmm0
.loop:
    test r12, r12
    jz .return
    test r12, 1
    jz .square
    movsd xmm0, [rsp+8]
    movsd xmm1, [rsp]
    OP O_MULSD
    movsd [rsp+8], xmm0
.square:
    shr r12, 1
    jz .return
    movsd xmm0, [rsp]
    movapd xmm1, xmm0
    OP O_MULSD
    movsd [rsp], xmm0
    jmp .loop
.return:
    movsd xmm0, [rsp+8]
    DONE
.domain:
    lea rdi, [err_pow]
    jmp .error
.divzero:
    lea rdi, [err_div]
.error:
    call set_error
    pxor xmm0, xmm0
    DONE

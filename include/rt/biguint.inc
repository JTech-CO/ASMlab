; Internal exact-decimal workspace. 64 limbs = 4096 bits; no heap allocation.
; Callers prove capacity from the 127-byte decimal token / binary64 limits.
%ifndef ASMLAB_BIGUINT_INC
%define ASMLAB_BIGUINT_INC 1
%define BU_LIMBS 64
%define BU_SIZE 520
%define BU_SLOT 528
%endif

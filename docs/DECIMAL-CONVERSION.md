# Exact decimal conversion in ASMlab v0.3.0

Status: implemented and integrated into the full native application. The libc conversion adapter remains only in development comparison builds. These are original, deliberately simple **integer reference algorithms**, not Ryu/Eisel-Lemire ports and not shortest-string implementations.

## Public conversion contract

`rt_parse_f64(bytes,length)` accepts a full ASCII decimal span of 1..127 bytes. Grammar: optional sign, decimal mantissa with at least one digit, optional e/E exponent with optional sign and at least one digit. No spaces, NUL, hex, NaN/Inf, suffixes or locale separators. It returns status in RAX and raw binary64 bits in RDX. Success is 0, malformed/out-of-contract input is -22, overflow is -34 plus signed infinity bits. Underflow may succeed as a subnormal or signed zero. The application's lexer rejects overflow/nonfinite results as before.

`rt_format_f64(dst,capacity,bits,precision)` accepts precision 1..17 and returns byte length excluding NUL, -22 for invalid precision or -28 for insufficient capacity. Capacity includes NUL; failure does not write the destination. The special strings `nan`, `inf`, and their signed forms are allowed for trace metadata only. The expression language does not admit those values.

Both routines preserve MXCSR exactly and use **integer arithmetic only**; moving bits into XMM0 in the compatibility entry is not a floating-point calculation. Their nearest-even policy is independent of the caller's FP rounding/FTZ/DAZ settings. This is a design contract supported by code structure and tests, not a machine-checked proof over every possible input.

## Decimal to binary64

1. Parse the significand into a bounded unsigned multiword integer. Track the decimal exponent exactly within a saturated exponent classification. All syntax is checked even when the magnitude will be zero/overflow.
2. Form the exact rational `N/D = significand × 10^decimal_exponent`. Conservative decimal magnitude classification handles enormous exponents before allocating/looping over their magnitude. `0e999...` still yields zero; an incomplete exponent is an error.
3. Determine `floor(log2(N/D))` with integer bit lengths and an exact comparison.
4. For normal values, scale to a 53-bit significand unit. For subnormals, scale to the fixed `2^-1074` unit.
5. Divide using shifted-denominator integer subtraction. Keep the exact remainder. Compare `2 × remainder` to the denominator, incrementing only above halfway or on an odd-significand tie.
6. Handle carry into the next exponent, normal/subnormal transition, overflow and sign packing.

There is no repeated float64 `×10` accumulation, approximate scaling table, host parser, FPU dependence or external fallback.

## Binary64 to decimal

Decompose a finite magnitude as `m × 2^e`. For nonnegative e, shift the integer m. For negative e, use the exact identity:

```text
m × 2^(-k) = (m × 5^k) × 10^(-k)
```

Convert the resulting integer to exact decimal digits with integer division by ten. Round once to the requested number of significant decimal digits using the discarded digit, sticky tail and even-last-digit rule. Handle a carry across all nines. Strip trailing insignificant zeros and use the general-format choice: scientific notation when the final exponent is below -4 or at least the requested precision; fixed notation otherwise. Scientific exponents have a sign and at least two digits.

JSON and quiet output use precision 17 for binary64 round-trip preservation; result tables use 8, register lanes 12, AST literals 10. Lower-precision display is not an exact serialization and can print a rounded magnitude outside the original binary64 range (for example maximum finite at precision 1). Raw trace hex remains authoritative. Signed zero is preserved. External JSON consumers have their own number handling; the round-trip contract concerns the ASMlab parser and formatter.

## Bounds and ownership

The internal `bu_*` helpers operate on 64 little-endian 64-bit limbs (4096 bits) and an active-length header. They are not a general arbitrary-precision user API. The lexer limit and binary64 exponent range bound all temporary values. Decimal parsing after conservative classification needs fewer than 2048 bits, including numerator scaling; formatting needs fewer than 2600 bits. The 800-byte exact-digit scratch exceeds the maximum required binary64 expansion coefficient. Final general-format output is bounded well below its local 80-byte scratch.

Scratch is on each call's stack, not in shared global math state. Internal helpers assume validated, adequately sized storage and do not add general overflow/pointer validation. Application limits are not enlarged. No heap, mmap or allocator is introduced.

## Validation

`tests/decimal_exact.py` checks parsed outputs against **exact rational intervals between neighboring binary64 midpoints**. This oracle does not simply trust Python float parsing or reproduce the assembly quotient algorithm. It separately checks decimal output against Decimal exact quantization and Python spelling, then performs raw-bit round trips. ABI probes run under a non-default MXCSR state and verify callee-saved registers, DF and unchanged MXCSR. Protected-page child tests check span/terminator and output boundaries.

The corpus includes decimal exponent sweeps, random long mantissas, normal/subnormal/overflow boundaries, signed zero, rounding ties, every finite binary exponent, random raw bit patterns, all 1..17 precisions at selected boundaries, inadequate output capacities, invalid grammar and trace-only nonfinite formatting. Finite tests are evidence, not exhaustive correctness proof. Elementary `sin/cos/log` accuracy is **not** upgraded by this conversion work; see [NUMERICS.md](NUMERICS.md).

[Actual results](../evidence/l3/decimal-exact.json) · [ABI](RUNTIME-ABI.md)

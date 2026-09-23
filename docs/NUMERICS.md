# ASMlab 0.4.0 - numerical contract

This document describes the algorithms implemented in `src/math.asm` and `src/kernels.asm`. It is an implementation specification, not a claim of complete MATLAB compatibility or of correctly rounded elementary functions for every input.

## Representation and arithmetic environment

Every scalar and matrix element is IEEE 754 binary64 (float64). Matrices store elements in row-major order. A 1 x 1 matrix is treated as a scalar. The evaluator accepts finite inputs, validates every evaluated node's result, and rejects NaN and infinity. Subnormal results and underflow to zero are permitted. Negative zero is preserved by the unary negation kernel's sign-bit XOR and by `sin(-0)` / hardware square root.

Each expression starts with MXCSR = `0x1f80`: rounding to nearest, masked floating-point exceptions, and no flush-to-zero or denormals-are-zero mode. Sticky exception status may change during execution. Each watched instruction records MXCSR both before and after execution. A nonzero precision/underflow status bit is not by itself a language error. Arithmetic domains and finite results are checked separately.

Decimal text is tokenized in assembly and converted by the project's integer-only exact rational parser. Output uses the project's exact binary64-to-decimal formatter through `rt_console_format`. No libc float conversion/formatting is linked into the native app. See [DECIMAL-CONVERSION.md](DECIMAL-CONVERSION.md). JSON/quiet precision17 is the serialization path; display rounding is not computation precision.

The evaluator additionally resets MXCSR immediately after successful parsing and before numerical evaluation. This isolates libc parser side effects in the development comparison backend and makes trace flags refer to numerical execution, not string conversion. Relative to v0.2.0, a first frame after an inexact decimal literal can therefore start with clean flags rather than inheriting `strtod` flags. Actual kernel operands/results and instructions are unchanged.

## Function domains

| Function or operator | Accepted inputs | Implementation |
|---|---|---|
| `sin(x)`, `cos(x)` | Finite real x, absolute value <= 1,000,000 radians | Split pi/2 range reduction, quadrant selection, Horner polynomial |
| `sqrt(x)` | Finite real x >= 0, including signed zero | `sqrtpd` for two cells or `sqrtsd` for a tail |
| `log(x)` | Positive finite real x, including subnormal inputs | Binary exponent normalization and an atanh-series polynomial |
| `a^n` | Scalar a and integer n from -1024 through 1024 | Exponentiation by squaring |
| Division | Nonzero divisor(s) | SSE2 scalar or packed division |

Functions apply elementwise to vectors and matrices. One invalid element makes the whole expression fail. Failed assignments do not overwrite the existing variable or `ans`. `0^0` is defined to be 1; `0` to a negative exponent is a division-by-zero error. Fractional exponents and complex results are outside this MVP.

## sin and cos

The original input x is reduced as follows, using binary64 arithmetic:

```text
q = round_to_nearest(x * (2/pi))
r = (x - q*pio2_hi) - q*pio2_lo
pio2_hi = 1.57079632673412561417
pio2_lo = 6.07710050650619224932e-11
```

The selected input bound keeps q small enough for this deliberately bounded reduction scheme. The intended reduced interval is approximately [-pi/4, pi/4]. Low quadrant bits select either the sine or cosine polynomial and its sign. This is not a general full-range Payne-Hanek implementation, so larger inputs are rejected instead of returning an unqualified approximation.

The sine kernel evaluates an odd Taylor polynomial through r^17. The cosine kernel evaluates an even Taylor polynomial through r^18. Coefficients are stored as binary64 constants; both are evaluated with Horner's method using SSE2 multiply and add instructions, not FMA. Intermediate watched arithmetic is part of the trace.

In exact arithmetic, truncation at |r| <= pi/4 has the following Taylor remainder bounds:

```text
sine:   (pi/4)^19 / 19!  approximately 8.35e-20
cosine: (pi/4)^20 / 20!  approximately 3.28e-21
```

These are bounds for polynomial truncation only. They are NOT end-to-end floating-point error bounds. Input rounding, constants, range reduction, individual multiplication/addition rounding, and quadrant-boundary behavior are separate sources of error. Near zeros, absolute error is more informative than relative error.

## Natural logarithm

For positive finite x, decompose x = 2^k * m. Subnormal x is first multiplied by 2^54 and the exponent is corrected by -54. The mantissa is selected so that approximately 1/sqrt(2) <= m <= sqrt(2).

Define z = (m - 1)/(m + 1). Then:

```text
log(x) = k*log(2) + 2*atanh(z)
log(m) approximately 2*z*(1 + z^2/3 + z^4/5 + ... + z^24/25)
```

The polynomial is evaluated with Horner's method. Within the intended mantissa interval, |z| is at most about 0.171573. In exact arithmetic the omitted series is bounded by:

```text
2*|z|^27 / (27*(1-z^2)), approximately 1.64e-22 at the endpoint.
```

Again, this excludes binary64 rounding. For very small or large x the final k*log(2) term can dominate the observed absolute rounding difference. This implementation does not promise the smallest possible ULP error or correct rounding for all positive binary64 values.

## Matrix arithmetic and actual SIMD behavior

Addition, subtraction, elementwise multiplication/division, and scalar broadcasting use two binary64 lanes per XMM register where possible. Odd final elements use scalar instructions. Unary negation changes sign bits with XOR; transposition copies cells to a fresh value without aliasing the source.

For matrix multiplication, the kernel computes each row-column dot product in pairs. It loads two contiguous A values, gathers the matching strided B values, executes `mulpd`, accumulates with `addpd`, and reduces the two partial sums with scalar addition. An odd tail uses scalar multiply/add. The trace's context index refers to the destination matrix element for this kernel, not necessarily a contiguous input load.

The summation order therefore differs from a simple sequential scalar loop and may differ from MATLAB or BLAS. Float64 matrix products must not be assumed bit-for-bit identical across algorithms. This MVP does not use compensated summation, cache-blocked BLAS kernels, CPU feature dispatch, AVX2, multithreading, or GPU acceleration.

`sum(A)` is a sum over every element, not MATLAB's default columnwise reduction. `/` only accepts a scalar right operand. `./` is elementwise division. No matrix right-division solver is hidden behind `/`.

## Accuracy evidence for the delivered executable

The fixed-seed suite uses host Python's standard-library `math` as a reference. It is not a high-precision MPFR oracle. The results below were reproduced on the directly NASM-built v0.4.0 release/debug profiles and development libc-reference backend. The14,410-assertion regression corpus preserves numerical cases; former17-axis and64th-variable rejection expectations were deliberately changed for dynamic support. Test-count continuity is not source identity.

| Function | Cases | Maximum observed absolute difference | Acceptance criterion |
|---|---:|---:|---|
| sin | 3,009 | 1.1102230246251565e-16 | Absolute difference <= 3e-14 |
| cos | 3,009 | 1.1102230246251565e-16 | Absolute difference <= 3e-14 |
| log | 3,008 | 1.1368683772161603e-13 | Absolute difference <= 3e-13 |
| sqrt | 1,004 | 0 in these samples | Relative difference <= 1e-15; exact comparison at zero |

The full suite includes 11,835 numerical expression cases and additional functional, malformed-input, capacity, replay, and instruction-capture checks. Its 14,410 total checks passed independently on release, debug and the libc-reference backend. A separate 1,254-assertion Native Gate contract covers constant encoding, instruction bytes, captured state and profile parity. These additional checks do not expand the stated mathematical error guarantees. A single matrix case may compare multiple cells; counts here are test cases, not independent floating-point operations.

No finite test sample establishes an all-input correctness theorem. In particular, zero observed square-root difference does not prove every behavior of the entire expression evaluator. See [VERIFICATION.md](VERIFICATION.md) and the machine-readable [verification report](../evidence/native/release-regression.json).

## v0.3.0 exact decimal tests

The native parser is tested against exact rational neighboring-binary64 midpoint intervals; the native formatter against exact Decimal quantization, independent spelling checks, capacity/precision errors and raw-bit round trips. ABI probes verify preserved callee-saved registers, DF and MXCSR; protected pages test boundary access. The old libc adapter fixture remains an additional development comparison, not the native implementation. See [decimal evidence](../evidence/l3/decimal-exact.json). These tests are finite, not a formal all-input proof and not MPFR validation of `sin/cos/log`.

## Trace precision and performance interpretation

Ordinary matrix tables print 8 significant digits. Register display prints 12; `--quiet` and `--json` print 17. `--bits` prints exact 64-bit register patterns, including signed zero and inactive scalar lanes. A display rounded to 8 digits is not the precision at which the computation was performed.

Trace capture and watched-instruction dispatch have intentional overhead. Even `:trace off` retains the central instruction-dispatch path and uses a scratch record. No claim is made that this teaching-oriented implementation is faster than compiled C, MATLAB, NumPy, or a tuned BLAS. The goal is observable arithmetic with a small, bounded numerical language.

## Primary technical references

- Intel 64 and IA-32 Software Developer's Manuals: instruction semantics, XMM registers, SSE2, and MXCSR. <https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html>
- NASM manual: ELF64 output and assembler syntax. <https://www.nasm.us/doc/nasm09.html>

The algorithms and bounds above are derived from the delivered implementation and elementary Taylor/atanh series, rather than copied from a third-party math library.

## v0.4.0 shape functions and dynamic storage

Changing storage to descriptors does not change scalar precision. `math.asm` and `exec_sse` dispatch/capture prefix remain identical to0.3.0; the matrix memory-addressing code follows `V_DATA` instead of inline storage. Row-major layout, pair-wise SSE2 accumulation order, MXCSR evaluation reset, domain rejection, gradual underflow and negative zero remain.

Constructors `zeros/ones/eye` initialize exact0/1 via integer stores. `size` converts dimensions at most1,048,576 to exactly representable float64. These metadata/initialization instructions are not advertised as fully traced computation. Named indexing validates integral1-based coordinates and returns an independent scalar via a watched register copy. No complex, sparse, empty, sliced or strided view is added.

`linspace(a,b,n)` returns b alone for n=1. For n>1 it copies first/last raw endpoint bits. Interior sample i computes t=i/(n-1), then `t*b+(1-t)*a`, using the selected observed SSE2 instructions. This avoids explicitly forming an overflowing `b-a` for opposite-sign large endpoints. It is still floating arithmetic with possible repeated/nonuniform rounded steps and no correctly-rounded-real-interpolation or MATLAB/NumPy bit-parity guarantee. Any nonfinite result is rejected normally. New tests compare the actual specified sequence, including opposite-sign large endpoints and signed zero; they do not certify every input.

One Value is limited to1,048,576 cells; one nonscalar matmul to16,777,216 scalar multiply terms. Actual available memory is determined by live page-rounded allocation budget, including old values and commit copies. A mathematically valid result can fail due to those explicit resource bounds.

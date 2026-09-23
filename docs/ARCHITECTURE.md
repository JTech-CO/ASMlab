# ASMlab 0.1.1 architecture / 아키텍처

## 1. Execution path

```text
TTY / -e expression / -f file
        |
        v
bounded whole-line reader and validation
        |
        v
NASM decimal lexer (strtod only converts an already scanned decimal token)
        |
        v
Pratt parser -> bounded AST arena
        |
        v
AST evaluator -> shape/domain checks -> temporary float64 arena
        |
        v
precompiled NASM scalar / matrix / transcendental kernels
        |
        +-> exec_sse: actual selected instruction and immediate register capture
        |               |
        |               v
        |          bounded trace records
        v
finite result check -> atomic user-variable copy -> ans update
        |
        v
NASM terminal renderer: AST -> instruction and lanes -> result
```

The AST is not compiled to new native code. Its operators select existing kernels. There is no executable-memory allocation, generated code cache, CPU emulator, or high-level numerical backend. The same static watched-instruction address can occur many times in a trace, because one instruction site is called with different operands.

## 2. Dependency boundary

The authored application is `.asm`/`.inc` only. libc/CRT supplies the process entry path, buffered I/O, input file handles, decimal-string conversion, `strcmp`/`strlen`, and `memcpy`/`memset`. It supplies no application mathematical function. `tests/verify.py` uses Python math as an independent development reference; this must not be mistaken for a runtime dependency. `tools/validation_bridge.py` is also development-only.

`readelf -d`, dynamic symbols and COPY relocations (including `stdin`) audit the executable's actual dependencies. In the delivered build, only `libc.so.6` is a `NEEDED` shared library. The dynamic loader and normal startup objects remain system dependencies.

## 3. Bounded layouts

| Object | Layout | Bound |
|---|---|---|
| AST node | 128 bytes: kind, operator, children, float, name, shape, result pointer, ID, source byte position, matrix sibling | 512 nodes |
| Value | rows, columns, then 256 contiguous float64 cells; 2,064 bytes | 512 temporary values |
| Workspace entry | 32-byte name plus a complete value; 2,096 bytes | 64 entries, one reserved for ans |
| Trace record | 96 bytes; see below | 8,192 records |
| Input | NUL-terminated storage after whole-line validation | 4,095 source bytes |

Matrix dimensions must each be 1..16. A 1x1 matrix is treated as a scalar for broadcasting. There is no view or alias into another variable's data. Evaluation outputs are newly allocated in the bounded temporary arena; assignments copy data into the workspace only after successful evaluation. All temporaries and ASTs are reset on the next expression. The application is single-threaded and not a reentrant library.

## 4. Trace contract

The following offsets are defined by the writer and consumed directly by the terminal view:

| Offset | Bytes | Field |
|---:|---:|---|
| 0 | 8 | opcode ID |
| 8 | 8 | AST node ID |
| 16 | 8 | context element index |
| 24 | 8 | address of the actual watched machine instruction |
| 32 | 16 | XMM0 before |
| 48 | 16 | XMM1 source before |
| 64 | 16 | XMM0 immediately after |
| 80 | 8 | MXCSR after, low 32 bits used |
| 88 | 8 | MXCSR before, low 32 bits used |

Captured registers are stored with `movupd` before any libc rendering call. The recorder itself preserves XMM1..XMM15; callers can use XMM4 as a matrix accumulator and XMM7 for polynomial arguments. The recorder clobbers RAX, RDX, R10, R11, flags, and XMM0 as documented at its entry. Every ordinary application function preserves the System V callee-saved general-purpose registers; external calls have a 16-byte-aligned stack.

Selected instructions are `addsd/subsd/mulsd/divsd/sqrtsd`, `addpd/subpd/mulpd/divpd/sqrtpd`, `movapd`, and `xorpd`. The suffix `SD` has one active arithmetic lane; `PD` arithmetic has two float64 lanes. All 128 destination/source bits are still shown, including a scalar instruction's preserved upper destination lane. Lane 0 means the low 64 bits; lane 1 means the high 64 bits. `xorpd` uses a sign-bit mask; its source should be interpreted as a bit mask, not a numeric addend.

The context element index is the flat start element for elementwise operations, the destination cell for matrix multiplication or transpose, and the current input element for unary functions and sum. It is not a universal source-memory address or loop iteration counter. MXCSR is captured state, including cumulative exception flags, not a per-instruction timing measurement.

Not captured: ordinary loads/stores, branch decisions, integer exponent-bit processing, range-reduction conversions, shuffles/unpacks, or libc internals. Consequently this is an instrumented numerical trace, **not a complete CPU trace**.

## 5. Matrix kernels

Elementwise operations process two float64 cells at a time with packed SSE2, then one scalar tail cell when the element count is odd. A scalar operand is duplicated into both lanes before a packed operation. Zero divisors are checked before division.

Matrix multiplication uses row-major arrays. For each result cell, two adjacent values of A are loaded into XMM0. Two corresponding strided values of B are gathered using scalar loads and `movhpd` into XMM1. `mulpd` forms two products; `addpd` accumulates the pair. `addsd` reduces the two accumulators and handles any odd final term. No AVX, FMA, SSE3 horizontal-add instruction, or external BLAS is required. This changes the summation order compared with a strictly serial dot product.

Transpose copies each scalar to its destination index through a watched register move. Unary minus flips the sign bit with `xorpd`, preserving signed zero and subnormals rather than implementing `0-x`.

## 6. Terminal states

Normal evaluation renders the AST, up to six trace frames, and the result. Larger matrices are printed completely in blocks of four columns. `:replay` or `:step on` activates a fullscreen **post-execution replay** for actual retained frames. The replay tree is limited to ten displayed nodes and explicitly identifies any omission. Regular output contains the bounded full tree.

No browser runtime, HTML renderer, ncurses dependency, or remote service is involved. ANSI is only used for terminal headings and replay clearing; plain output is available. The terminal uses canonical line input, so navigation keys require Enter. It does not implement shell-style history or an editor.

## 7. Error and state rules

Syntax must fully parse before evaluation. Nonrectangular matrices, dimension mismatch, undefined variables, domain failures, invalid numeric results, excessive recursion/nodes, or insufficient workspace prevent assignment commit. `ans` updates only on successful expressions. A script continues after expression errors but reports a nonzero final exit status.

Input streams are read through a bounded assembly loop around libc `fgetc`, rather than accepting a valid-looking prefix of an oversized line. Embedded NUL/terminal-control bytes are replaced for safe reporting and the entire line is rejected. The source language permits ASCII identifiers; comments can contain ordinary UTF-8 text. All reported positions are byte offsets.

## 8. Build and portability boundaries

NASM's `elf64` output is the verified native build path in v0.1.1. Both supplied release/debug executables were assembled directly with NASM 2.16.03 and tested. The GNU assembler bridge is a separate optional historical comparison, never a fallback for the Native Gate. The target is little-endian Linux x86-64, libc/CRT, and the System V AMD64 calling convention. Native Windows requires a different object format, ABI, and OS adaptation; ARM requires different instructions and kernels. Those ports are absent. The future Pi/server plan is documentation only; see [plan](plans/RASPBERRY-PI5-SERVER-PLAN-KR.md).

The binary is deliberately non-PIE for straightforward address/disassembly inspection, with a non-executable stack, RELRO, and immediate binding. It is an educational bounded interpreter, not a security sandbox for hostile multi-user execution or a performance replacement for optimized numerical libraries.

## References

- NASM manual, ELF output formats: https://www.nasm.us/doc/nasm09.html
- Intel architecture and instruction manuals: https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html
- Microsoft WSL installation: https://learn.microsoft.com/en-us/windows/wsl/install

These sources describe the toolchain/platform. They do not establish the correctness of ASMlab's implementation; that evidence is in the included tests and build report.

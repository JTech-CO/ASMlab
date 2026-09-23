# ASMlab

**See a mathematical expression become an AST, executed SSE2 instructions, actual XMM register snapshots, and a numerical result.**

ASMlab 0.1.0 is a small, assembly-authored numerical inspection environment for Linux x86-64 and x86-64 WSL2. The application is written entirely in NASM assembly. Its interface is a terminal workbench, not a browser mock-up or a Python calculator behind an assembly wrapper.

[한국어 설명](README-KR.md) | [Architecture](docs/ARCHITECTURE.md) | [Numerics](docs/NUMERICS.md) | [Language](docs/LANGUAGE.md) | [Verification](docs/VERIFICATION.md)

![Captured terminal output](docs/terminal-demo.png)

## Build provenance: read this first

The bundled `bin/asmlab` was executed and tested, but **a NASM-native build was not run in the authoring environment**. NASM was unavailable, and attempts to obtain it failed. The validation build used the explicit `tools/validation_bridge.py` syntax bridge, GNU `as`, and the GCC linker driver. The bridge translates the authored NASM subset to GNU Intel syntax; it does not supply any numerical implementation and is not part of the runtime.

Default `make` uses NASM directly. The supplied GitHub Actions workflow also uses NASM, but that remote workflow has **not** been executed for this delivery. See [bin/BUILD_ORIGIN.txt](bin/BUILD_ORIGIN.txt) and the [verification report](docs/VERIFICATION.md). Passing the validation build does not establish that NASM's parser, relocations, or link output have been independently tested.

## Scope

| Component | Implementation |
|---|---|
| Lexer, Pratt parser, AST, evaluator | NASM x86-64 |
| Scalars, variables, row/column vectors, matrices | Real float64, row-major storage |
| Operators | `+`, `-`, `*`, `/`, `.*`, `./`, scalar integer `^`, unary signs |
| Matrix operations | Addition/subtraction, scalar broadcast, matrix multiplication, elementwise operations, transpose |
| Functions | `sin`, `cos`, `sqrt`, natural `log`, `transpose`, aggregate `sum` |
| Register inspection | Real before/source/after XMM snapshots, optional raw IEEE-754 bits, MXCSR before/after, instruction addresses |
| Interface | ANSI/plain terminal views, REPL, capture replay, files, quiet and JSON result modes |
| External runtime facilities | libc/CRT for console, file input, decimal conversion, string/memory operations |
| External mathematical libraries | **None: no libm, BLAS, LAPACK, NumPy, or other evaluator** |

This is the Level 2 interpretation used here: application logic is assembly-only; standard system facilities are allowed. It is **not** a no-libc/no-CRT freestanding executable. Python is used only by development tests and the optional validation bridge. There are no C, C++, Rust, JavaScript, or Python application source files.

## Run the bundled validation executable

Inside a Linux x86-64 shell, or the Ubuntu shell in x86-64 WSL2:

```sh
cd ASMlab-v0.1.0
chmod +x bin/asmlab
./bin/asmlab
```

The bundled ELF executable requires glibc 2.34 or newer. It is not a Windows `.exe`, a macOS binary, or an ARM/Raspberry Pi build. WSL2 is a target, but this delivery was tested in a Linux container, not on a separate Windows/WSL machine.

A terminal of approximately 100 columns by 42 rows is comfortable for replay. Regular output uses scrollback and does not require a fullscreen terminal. Matrix results wider than four columns are displayed in column blocks rather than omitted.

## Build with NASM

On Debian/Ubuntu:

```sh
sudo apt update
sudo apt install -y nasm gcc make binutils
make clean
make
./bin/asmlab --bits -e 'sqrt([1,4,9,16]) + 2'
```

NASM assembles `src/asmlab.asm` as ELF64; it includes the separately maintained modules. GCC is used as a linker driver for the normal libc/CRT entry path, not to compile application C code. The executable is non-PIE so instruction addresses remain easy to inspect; stack execution is disabled, with RELRO and immediate binding enabled.

## Try it

```text
x = 3
x^2 + 4^2
A = [1,2;3,4]
B = [5,6;7,8]
A*B
A.*B
transpose(A)
sqrt([1,4,9,16]) + 2
sin(pi/4)
log(e)
```

For `sqrt([1,4,9,16]) + 2`, the retained register transitions include:

```text
sqrtpd xmm0, xmm1 : source [1, 4]  -> result [1, 2]
sqrtpd xmm0, xmm1 : source [9,16]  -> result [3, 4]
addpd  xmm0, xmm1 : lhs    [1, 2]  + rhs    [2, 2] -> [3, 4]
addpd  xmm0, xmm1 : lhs    [3, 4]  + rhs    [2, 2] -> [5, 6]
result: [3, 4, 5, 6]
```

These values are captured from executing CPU instructions. They are not recomputed for display. The capture routine calls no formatting function between a watched instruction and its post-state store.

## Inspect and replay

```text
:bits on
sqrt([1,4,9,16]) + 2
:replay
```

During replay, type `n` then Enter for the next frame, `p` then Enter for the previous frame, or `q` then Enter to finish. Enter alone also advances. `:step on` automatically enters replay after subsequent evaluations. Replay requires both stdin and stdout to be terminals; scripts cannot accidentally consume keyboard-step input.

**Replay happens after evaluation.** This is not a debugger single-stepping the CPU, nor a JIT compiling each expression. The AST evaluator invokes precompiled assembly kernels. The displayed instruction address identifies the watched instruction inside those kernels. Loads, branches, shuffles, conversions, and other uninstrumented instructions are not presented as a complete instruction trace.

The first six retained frames are printed by default. `:trace all` shows all retained frames on later evaluations; `:trace on` returns to six-frame previews. Up to 8,192 frames are retained per expression. If the cap is reached, the display explicitly reports truncation and the computation continues. `:trace off` disables retention; the kernel dispatch and scratch-capture overhead remain, so it is not a performance benchmark mode.

## Batch and structured output

```sh
./bin/asmlab --bits -f examples/walkthrough.asmlab
./bin/asmlab --quiet -e '[1,2;3,4]*[5,6;7,8]'
./bin/asmlab --json -f examples/numeric.asmlab
```

A JSON result is one line:

```json
{"ok":true,"rows":2,"cols":2,"data":[19,22,43,50]}
```

The `data` array is row-major. JSON and quiet modes print 17 significant digits; the table view prints eight and register views print twelve. Raw-bit mode exposes the complete captured register bits. JSON mode describes results/errors, not ASTs or trace records. Keep interactive display commands such as `:vars` out of machine-output scripts.

`:vars` displays the workspace; `:clear` resets variables and `ans`; `:help` lists syntax; `:quit` exits. A failed expression does not commit its assignment or alter `ans`. Scripts continue after expression errors and return status 1 if any expression failed. Status 2 indicates a command-line or file-I/O error.

## Limits and deliberate exclusions

Real float64 only. Matrices are limited to 16 x 16; there are 63 user variables plus reserved `ans`, 512 AST nodes, and a recursion depth limit of 64. Input lines are limited to 4,095 bytes. Oversized lines and embedded control bytes are rejected as whole lines, not evaluated as truncated prefixes.

Matrix columns require commas. `/` requires a scalar divisor; it is not MATLAB right division. `sum` aggregates all elements; it is not MATLAB's default columnwise `sum`. Exponentiation is scalar with an integer exponent in `[-1024,1024]`. `sin/cos` reject arguments outside `|x| <= 1,000,000` radians. Domain errors and non-finite arithmetic results are errors. Gradual underflow is permitted.

No matrix inverse/determinant/linear solver, complex numbers, symbolic differentiation/integration, indexing, plotting, editor/history, GUI, AVX/AVX2 backend, or MATLAB compatibility layer is claimed in this release. These are not hidden behind dummy controls.

## Verify

Development checks require Python 3.10+ and binutils, not application execution:

```sh
sudo apt install -y python3
make test                         # native NASM build, tests, runtime audit
python3 tests/verify.py bin/asmlab # verify the existing binary without rebuilding
make audit
make disasm
```

`make validate-gas` explicitly builds a separate `bin/asmlab-validation`; it is never a silent fallback for `make`. The delivered verification run passed **14,410 checks**, including 10,030 elementary-function reference cases, matrix tests, malformed-input fuzzing, transactional state checks, PTY replay controls, register-bit checks, and instruction-address/disassembly matching. Finite test coverage is not a proof of correct rounding or complete input safety.

## Repository map

```text
include/core.inc        shared layouts, limits, ABI macros, state
src/parser.asm         decimal lexer and Pratt parser
src/evaluator.asm      AST evaluation, domain/shape checks, atomic workspace
src/kernels.asm        SSE2 execution/capture and matrix kernels
src/math.asm           bounded sin/cos/log and integer power
src/runtime.asm        arenas, workspace, error handling
src/view.asm           AST, register, matrix, JSON, and replay terminal views
src/main.asm           CLI, input loop, commands
examples/              runnable expression sessions
tests/                 development-only reference, fuzz, PTY, audit tests
tools/                 explicit validation-only syntax bridge
evidence/              reports, build provenance, actual captured output
```

Original application code is MIT licensed. System runtimes and development tools retain their own licenses.

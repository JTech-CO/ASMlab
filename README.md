# ASMlab 0.1.1

**Expression → AST → actual assembly instruction → SIMD registers → result.**

A bounded numerical workbench whose application implementation is NASM x86-64 assembly. [한국어](README-KR.md) · [Changelog](CHANGELOG.md) · [Verification](docs/VERIFICATION.md)

## Native Gate completed

Both delivered executables were assembled **directly with NASM 2.16.03**, not through the earlier GNU-as syntax bridge. The existing numerical algorithms, grammar and data layout are unchanged.

| Test execution | Passed | Failed |
|---|---:|---:|
| Original regression corpus, release | 14,410 | 0 |
| Original regression corpus, debug | 14,410 | 0 |
| Native constants/instructions/trace/profile contract | 1,254 | 0 |
| **Native Gate total** | **30,074** | **0** |
| Separate fail-closed/relocation guard tests | 6 | 0 |

The total counts repeated execution of the original corpus on two profiles, not 30,074 distinct expressions. ELF audits pass separately. [Machine-readable gate result](evidence/native/gate-summary.json)

**This remains Level 2.** libc/CRT provides startup, I/O, strings/memory and decimal conversion. No external libm, BLAS, LAPACK or Python runtime evaluates mathematics. libc removal is a later milestone.

## Run / build

Target: **Linux x86-64**. Delivered binaries require glibc 2.34 or later. WSL2 Linux on x64 Windows is an intended target but was not separately device-tested. No Windows-native, ARM64, Raspberry Pi or web-server executable is supplied.

```sh
chmod +x bin/asmlab bin/asmlab-debug
./bin/asmlab
./bin/asmlab --bits -e 'sqrt([1,4,9,16]) + 2'
./bin/asmlab --json -e '[1,2;3,4] * [5,6;7,8]'
```

Build and test on an Ubuntu-family Linux x86-64 machine:

```sh
sudo apt-get update
sudo apt-get install -y nasm gcc make binutils python3
make clean
make -j2 test
python3 tests/gate_guards.py --report build/gate-guards.json
```

`make` builds release (`bin/asmlab`, NASM `-Ox`); `make debug` builds `bin/asmlab-debug` (`-O0`, DWARF). `make test` rebuilds both and runs the gate. `make verify` tests the existing delivered binaries without rebuilding, requiring Python 3.10+ and binutils but not NASM. Input/binary hashes must match their sidecars. `make audit` checks both ELF files; `make disasm` rebuilds and disassembles both.

GCC is a linker driver only; no project C sources are compiled. Python tools are development-only. Default NASM warnings are promoted to errors; optional relocation diagnostics are not all enabled. Missing NASM/build failure cannot silently use GAS or retain a stale successful executable. The optional historical `make validate-gas` target is not a Native Gate substitute.

## Examples and observation

```text
A = [1,2;3,4]
B = [5,6;7,8]
A * B
A .* B
A + 2
A'
sin(pi/4)
log(e)
sum(A)
:bits on
sqrt([1,4,9,16]) + 2
:replay
```

Replay uses `n`/`p`/`q` followed by Enter. Each frame maps an AST node to the actual watched instruction address, XMM inputs/output, raw bits and MXCSR. [Actual native capture](evidence/native/sqrt-vector-trace.txt)

This is **post-execution replay of instrumented instructions**, not live CPU single-stepping, JIT compilation or full CPU tracing. `:trace off` still uses the central dispatch/scratch path. Debug/release refer to assembler encoding profiles, not different numerical algorithms.

## Contracts and limits

Real dense row-major float64 only. Matrix dimensions 1..16, 63 user variables, 512 AST nodes, recursion depth 64, input lines up to 4,095 bytes, and 8,192 retained trace frames per expression. Overflowing trace storage is explicitly reported.

Comma-separated columns; no implicit multiplication. `*` is matrix/scalar multiplication; `.*` is elementwise. `/` only accepts a scalar right operand. `sum(A)` sums all cells, unlike MATLAB's default column reduction. Failed assignments preserve both the variable and `ans`.

`sin/cos`: radians, `abs(x) <= 1,000,000`; `sqrt`: nonnegative real; `log`: positive real; powers: scalar integer exponent -1024..1024. Subnormal/underflow results are allowed, but NaN/infinity results are errors. No all-input correctly-rounded mathematics claim.

## Scope and provenance

Verification ran in a Linux x86-64 container. GitHub Actions is configured for Ubuntu 22.04 and 24.04, but **remote CI was not executed in this delivery**. There is no public-service security validation, ARM/Windows port or cross-device performance claim.

The NASM tool used here was a **third-party prebuilt NASM** from a public `holepunchto/nasm-runtime` workflow artifact. It was not rebuilt from official NASM sources in this environment and is not bundled. [Exact toolchain provenance](docs/TOOLCHAIN-PROVENANCE.md)

The [Pi 5 / server / ARM64 / web graphics plan](docs/plans/RASPBERRY-PI5-SERVER-PLAN-KR.md) is documentation only. No networking, browser UI, plot function or ARM implementation was added. [Roadmap](docs/ROADMAP-KR.md)

[Language](docs/LANGUAGE.md) · [Architecture](docs/ARCHITECTURE.md) · [Numerics](docs/NUMERICS.md) · [L3 boundary](docs/LEVEL3-CONTRACT.md)

Current evidence lives in `evidence/native/`. `evidence/baseline-0.1.0/` contains historical GAS-bridge results, not current native results. Sidecars in `bin/` record exact commands and hashes. `sha256sum -c MANIFEST.sha256` checks the delivered package after extraction, not authenticity or a security certification.

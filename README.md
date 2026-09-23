# ASMlab 0.2.0

**Expression → AST → actual assembly instruction → SIMD register state → numerical result.**

[한국어](README-KR.md) · [Changelog](CHANGELOG.md) · [Runtime ABI](docs/RUNTIME-ABI.md) · [Verification](docs/VERIFICATION.md)

## Runtime Foundation, not yet Level 3

The default application now uses original NASM memory/string primitives. Application code calls only the project `rt_*` runtime API; console/file/decimal conversion and libc globals reside in a separate transitional adapter. A libc-backed primitive implementation is built only as a development reference.

Independent integer conversion, raw Linux syscalls, buffered fd I/O and an own `_start` are implemented and tested in **runtime-smoke**, not yet integrated as the full numerical application's runtime. The application still uses CRT/main, libc I/O, strtod and printf-compatible formatting. No libm, BLAS, LAPACK or Python numerical backend is linked.

| Executed checks | Passed |
|---|---:|
| Existing regression, release/debug/libc-reference | 14,410 each |
| Native constant/instruction/capture contract | 1,254 |
| Independent runtime unit assertions | 26,123 |
| Runtime boundaries and backend parity | 712 |
| **Full gate** | **71,319, zero failures** |
| Separate fail-closed guards | 15, zero failures |

Counts include repeated corpora and per-call ABI assertions, not 71,319 distinct formulas or a proof. [Machine-readable release result](evidence/release-summary.json)

## Run

Target: Linux x86-64. Bundled application executables require glibc 2.34 or later. WSL2 x64 is an intended environment, not separately tested in this delivery. Windows-native, ARM64/Pi and web service targets are not implemented.

```sh
chmod +x bin/asmlab bin/asmlab-debug bin/asmlab-runtime-smoke
./bin/asmlab
./bin/asmlab --bits -e 'sqrt([1,4,9,16]) + 2'
./bin/asmlab --json -e '[1,2;3,4] * [5,6;7,8]'
```

The last expression returns `{"ok":true,"rows":2,"cols":2,"data":[19,22,43,50]}`. No NASM or Python is needed to execute the numerical application.

## Build and verify

```sh
sudo apt-get update
sudo apt-get install -y nasm gcc make binutils python3
make clean
make -j2 test
make test-guards
```

`make` builds release, `make debug` builds the debug profile, `make reference` builds the development libc-primitive comparison, and `make foundation` builds standalone smoke and shared test fixtures. `make test` rebuilds all of them and runs the full gate. `make runtime-test` rebuilds and runs the runtime/reference checks.

`make verify` tests already-delivered artifacts without NASM. It requires Python 3.10+ and binutils. This verification package includes the required **object files and link maps in build/** because provenance is checked before execution. After `make clean`, run `make test` to regenerate them. Sidecar metadata, exact source inventories, object/target hashes and module membership are enforced. These integrity records are not signatures.

GCC/cc is a linker driver, not a compiler for project C code. The old GAS translator is historical only; `make validate-gas` explicitly fails for v0.2.0. Failed native tool lookup/build does not silently reuse stale successful binaries.

## Standalone runtime smoke

```sh
./bin/asmlab-runtime-smoke --version
./bin/asmlab-runtime-smoke --i64 -9223372036854775808
./bin/asmlab-runtime-smoke --u64 18446744073709551615
./bin/asmlab-runtime-smoke --hex64 18446744073709551615
printf 'hello\n' | ./bin/asmlab-runtime-smoke --echo
./bin/asmlab-runtime-smoke --cat examples/walkthrough.asmlab
```

The smoke has no libc/CRT, interpreter or shared-library dependency, but **also has no mathematical evaluator**. Its binary echo/file copying, integer parsing/formatting and buffered I/O exercise the new foundation. The decimal input to `--hex64` is unsigned; its output is 16 lowercase hex digits. [ABI/error/ownership contract](docs/RUNTIME-ABI.md) · [Actual smoke output](evidence/runtime/smoke-demo.txt)

## Numerical language and trace

```text
x = 3
x^2 + 4^2
A = [1,2;3,4]
A*A
A.*A
A+2
A/2
A'
sin(pi/4)
log(e)
sum(A)
```

All values remain float64 dense matrices, scalars being 1×1. Matrices require comma-separated columns. `/` accepts a scalar right operand; `./` is elementwise. `sum` reduces all elements. Failed assignments preserve previous variables and ans. [Language](docs/LANGUAGE.md) · [Numerics](docs/NUMERICS.md)

`:bits on`, then an expression and `:replay` reveal actual retained SSE2 state. `n`+Enter advances, `p`+Enter goes back, and `q`+Enter leaves. `:step on` automatically opens **post-execution replay**. There is no JIT or complete CPU trace. `:trace off` is not an optimized compute backend. `src/math.asm` and `src/kernels.asm` are unchanged from v0.1.1.

## Limits and evidence

The previous 16×16 matrix, 63 user-variable, 512 AST-node, 64 recursion-depth, 4,095-byte line and 8,192-frame trace bounds remain. sin/cos are restricted to |x|≤1,000,000 radians, sqrt to nonnegative and log to positive real inputs. Powers use scalar integer exponents -1024..1024. Nonfinite results are errors; subnormals/underflow remain allowed.

Tests include protected-page subprocesses, preserved registers/DF/MXCSR, injected partial I/O/EINTR/errors, exact integer limits, independent decimal-adapter rounding checks, default/reference parity and artifact tampering. No all-input correctness, complete memory safety, public-server security or performance superiority is claimed.

Actual tests ran in a Linux x86-64 container. The updated Ubuntu 22.04/24.04 CI has **not been remotely executed**. The previously attached third-party prebuilt NASM 2.16.03 was rechecked and reused; the tool itself is not shipped. [Toolchain provenance](docs/TOOLCHAIN-PROVENANCE.md)

[Pi/ARM/server/2D/3D plan](docs/plans/RASPBERRY-PI5-SERVER-PLAN-KR.md) remains documentation only. [Runtime scope, KR](docs/RUNTIME-FOUNDATION-KR.md) · [Roadmap, KR](docs/ROADMAP-KR.md)

Current evidence is in `evidence/native/` and `evidence/runtime/`; archived baseline evidence is not a current test run. Check `sha256sum -c MANIFEST.sha256` immediately after unpacking.

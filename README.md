# ASMlab 0.3.0 - L3-Core

**Expression → AST → real assembly instruction → SIMD register state → result.**

[한국어](README-KR.md) · [Changelog](CHANGELOG.md) · [Verification](docs/VERIFICATION.md) · [Runtime ABI](docs/RUNTIME-ABI.md)

A NASM x86-64 numerical environment with an observable SSE2 evaluator. The complete release/debug application now runs from its own `_start`, using its own decimal conversion and buffered Linux syscall I/O. **No libc, CRT, libm, BLAS, LAPACK or dynamic interpreter is linked into the production executables.** This is not just the standalone runtime smoke: the parser, variables, matrix engine, terminal views and capture replay are included.

## Run

Linux x86-64 is required. There is no glibc version requirement for the production ELF. Windows x64 users need a Linux environment such as WSL2; separate WSL hardware testing was not performed. This is not a Windows `.exe`, ARM64/Pi build, browser app or API server.

```sh
chmod +x bin/asmlab bin/asmlab-debug
./bin/asmlab
./bin/asmlab --bits -e 'sqrt([1,4,9,16]) + 2'
./bin/asmlab --json -e '[1,2;3,4] * [5,6;7,8]'
```

The matrix result is `{"ok":true,"rows":2,"cols":2,"data":[19,22,43,50]}`. Python/NASM are not runtime dependencies.

## Build and verify

```sh
sudo apt-get update
sudo apt-get install -y nasm gcc make binutils python3
make clean
make -j2 test
make test-guards
```

`make` builds release and `make debug` builds DWARF debug with NASM + ld (Python records provenance). `make verify` validates and tests the delivered binaries/objects/maps without rebuilding (Python 3.10+ and binutils required). `sudo make empty-root-test` requires chroot privilege. The ordinary gate reports an explicit skip when not privileged; the delivered artifacts were actually tested in an empty root with only the executable and a script, running as UID 65534.

The **development-only** `asmlab-libc-reference` and `decimal-adapter.so` intentionally retain libc. The delivered comparison executable requires glibc 2.34+ on the test host; this does not apply to the production application. GCC is used only for those comparison links, never to compile project application code. The new `decimal-native.so` has no libc imports and is only a test fixture. No automatic GAS fallback is permitted.

## Scope

Binary64 scalars, variables, row/column vectors, matrices, arithmetic, integer powers, transpose, elementwise operations, matrix product, `sin/cos/sqrt/log/sum`. Existing math and kernel sources are unchanged from v0.2.0. Matrices remain limited to 16×16; there are 63 user variables, 512 AST nodes and 8,192 retained trace frames. Failed assignments preserve variables and `ans`.

Raw XMM values and MXCSR are captured around selected real SSE2 instructions. Replay is after evaluation, not live debugging/JIT. `:trace off` is not a fast uninstrumented backend. The evaluator begins with MXCSR `0x1f80`; decimal conversion is integer-only and does not pollute its flags. Correctly rounded decimal conversion is a separate target from elementary-function accuracy: no all-input numerical proof is claimed.

`rt_console_format` implements only the trusted view-format subset (strings, signed integers, hex, widths and general decimal), not full ISO printf. The underlying typed Writer and decimal converter are standalone assembly modules. Returned output/flush failure exits with code 2; default SIGPIPE/SIGINT signal termination is retained.

## Evidence and roadmap

[Release gate](evidence/release-summary.json) · [Exact decimal](evidence/l3/decimal-exact.json) · [Empty-root / integration](evidence/l3/l3-core.json) · [Numeric contract](docs/NUMERICS.md) · [Build tool provenance](docs/TOOLCHAIN-PROVENANCE.md)

Counts include repeated corpora and ABI assertions, not distinct expressions. Local Linux x86-64 testing only; configured remote CI was not executed. This bounded single-user educational program is not certified as an untrusted multi-user compute server. Non-PIE linking is used for simple instruction observation, not an ASLR hardening claim.

[Pi 5 / server / ARM64 / 2D–3D graphs](docs/plans/RASPBERRY-PI5-SERVER-PLAN-KR.md) remain **planning only**. Dynamic arrays, new math functions, linear solvers, GUI, ARM64 and web serving are not implemented in this release. Check the untouched archive with `sha256sum -c MANIFEST.sha256` before rebuilding; hashes are not signatures.

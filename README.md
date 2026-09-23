# ASMlab 0.4.0 - Dynamic Workspace

**Expression → AST → actual assembly instruction → SIMD registers → result.** NASM x86-64 numerical computing with a libc/CRT-free production runtime.

[한국어](README-KR.md) · [Changes](CHANGELOG.md) · [Dynamic Workspace](docs/DYNAMIC-WORKSPACE-KR.md) · [Verification](docs/VERIFICATION.md)

## What's new

Fixed inline16×16 values are replaced by 64-byte descriptors and quota-accounted anonymous mappings. Temporary evaluation arenas and persistent symbols have separate lifetimes. Assignment stages both the target and `ans` before committing; failed evaluation/allocation preserves both previous values. Symbols are dynamically linked rather than limited to63 users.

```text
A = ones(32,48)
B = A
A = A + 2
B(32,48)
A(32,48)
x = linspace(-10,10,1001)
y = sin(x)
size(y)
:memory
:drop B
:clear
```

`B(32,48)` is1; `A(32,48)` is3. Indexing is **1-based, exactly two scalar indexes, read-only and named-variable only**. Internal table coordinates remain explicitly zero-based. No slices, indexed assignment, empty matrices, block concatenation or MATLAB compatibility is implied.

| API | Meaning |
|---|---|
| `zeros(n[,m])`, `ones(n[,m])` | n×n or n×m dense arrays |
| `eye(n[,m])` | square/rectangular diagonal ones |
| `size(A)` / `size(A,1|2)` | 1×2 shape / scalar dimension |
| `linspace(a,b,n)` | 1×n samples; n=1 returns b; endpoint bits copied |
| `A(row,col)` | scalar read from a named variable |
| `--memory-mib N` | quota1..1024 MiB; default64 MiB |
| `:memory` / `:drop NAME` / `:clear` | inspect allocations / delete user symbol / release dynamic values |

## Run / build

```sh
chmod +x bin/asmlab bin/asmlab-debug
./bin/asmlab
./bin/asmlab --json -e 'size(ones(32,48))'
./bin/asmlab --bits -e 'linspace(-1,1,5)'
./bin/asmlab -f examples/dynamic-workspace.asmlab

# Debian/Ubuntu x86-64 native development environment
sudo apt-get install -y nasm gcc make binutils python3
make clean
make -j2 test
make test-guards
```

Production is a static **Linux x86-64** ELF built directly by NASM and GNU ld, with no interpreter, libc, CRT, external math library or Python dependency. A kernel, terminal and filesystem remain OS dependencies. Separate WSL hardware and Windows-native/ARM/Pi execution are not tested. Development comparison binaries intentionally retain libc; the included comparison executable requires glibc2.34+ on the test host, not in production.

`make verify` tests delivered artifacts without rebuilding (Python3.10+ and binutils required). `make workspace-test` rebuilds and tests the dynamic subsystem. Build/source/object/map provenance is verified before normal gates execute binaries; keep the packaged `.o` and `.map` files for no-rebuild verification. GAS translation is not an automatic fallback.

## Bounds and ownership

Maximum1,048,576 float64 elements **per value**, plus total page-rounded dynamic quota. Default64 MiB is not total RSS or a security sandbox. Old values, evaluation intermediates, target copies and staged `ans` may coexist. A large result can fail to commit even if its own buffer fits. Anonymous mmap success is not a guarantee against host OOM-killer termination.

AST512, temporary descriptors512, recursion64, input4095bytes, decimal token127bytes, trace8192frames remain. Each matrix product is capped at16,777,216 scalar multiply terms. Large tables preview16×16; JSON/quiet export the full array. User-variable previews show at most64 entries (including `ans`). No limit is silently removed or presented as unlimited memory.

`math.asm` and the real `exec_sse` capture implementation are unchanged from0.3.0. Matrix address handling changed to follow data pointers; the whole kernels file is therefore **not** identical. Constructors/metadata and allocator instructions are not full-instruction trace events. `linspace` uses observed weighted floating arithmetic; it is not a correctly-rounded real-number interpolator.

## Evidence

Local release: **186,731 assertions, 0 failures**, plus **32 separate fail-closed checks**. Repeated profiles/backends and ABI checks are included; not unique equations or a formal proof. Dynamic tests cover allocator arithmetic/alignment/accounting,320variables, repeated allocation/deletion, commit-time quota failures, OS-returned mmap failure, replay lifetimes, malformed calls and library-free execution. [Reports](evidence/release-summary.json) · [Dynamic report](evidence/dynamic/dynamic-workspace.json)

Remote CI is configured, not executed in this delivery. Raspberry Pi/ARM64/web/2D–3D graphics remain [planning-only](docs/plans/RASPBERRY-PI5-SERVER-PLAN-KR.md). This is not a public multi-user service, JIT or live debugger. Full Observe/Compute separation belongs to the next roadmap stage.

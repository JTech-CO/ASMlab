# Changelog


## v0.4.0 - Dynamic Workspace (2026-09-24)

- Replaced inline16×16 Values with64-byte descriptors and contiguous dynamic payloads.
- Added quota-accounted anonymous mmap allocator and per-expression bump arenas; persistent symbols/values have explicit independent ownership. Default64MiB, configurable1..1024MiB.
- Removed63-user-variable cap; added linked workspace entries, `:memory`, `:drop NAME`, complete dynamic release on`:clear` and normal exit.
- Transactional commit stages a new symbol, target and `ans` before publishing; late allocation failure preserves old target/ans and frees staged allocations.
- Added multiargument `zeros/ones/eye/size/linspace` and1-based named two-dimensional read indexing. No slices/indexed assignment/empty arrays.
- Added explicit per-value1,048,576-element and per-matmul16,777,216-term bounds. Large human-readable outputs use16×16 previews; JSON/quiet export full data.
- Retained L3-Core static no-libc/no-CRT linking (13 NASM objects). `math.asm` and actual SSE2 dispatch/capture prefix unchanged; payload access follows descriptors.
- Added independent allocator ABI tests, rollback/quota/kernel-allocation-failure tests,320variables, churn, replay lifetime, new syntax fuzz, extra empty-root execution and fail-closed artifact checks.
- Local complete gate:186,731 assertions /0 failures; separate guards:32 /0. Counts include repeated profiles/corpus and ABI checks, not unique expressions/proofs.
- Runtime remains Linux x86-64. ARM/Pi/server/graphics remain documentation-only. Remote CI was not executed.


## v0.3.0 - L3-Core (2026-09-23)

### Implemented
- Full production release/debug now start at own `_start` and link directly with GNU ld. No libc/CRT/interpreter/NEEDED or external runtime helpers.
- Exact bounded decimal-to-binary64 rational conversion with nearest-even rounding; signs, subnormal/normal boundaries, underflow and overflow handled. No `strtod` fallback.
- Exact binary64-to-decimal significant-digit formatter (1..17); JSON/quiet17, raw-bit round-trip tests, no-write-on-capacity-failure. No `printf` numerical formatting.
- Small `rt_console_format` for trusted view format strings, backed by own Writer, integer/float conversion and syscall I/O. It is not a full ISO printf implementation.
- Full app input uses shared Reader contexts for REPL/replay and an owned script slot. All early/final returns flush; output/flush failure exits2. Script close errors no longer disappear.
- Numerical evaluation explicitly resets MXCSR after parsing; decimal conversion no longer adds incidental FP flags to the first traced instruction.
- Native exact-decimal test fixture, exact rational/Decimal oracles, guard-page/ABI tests, real process mapping and empty-root execution checks, added L3 tamper guards and CI steps.

### Preserved / not included
- `math.asm` and `kernels.asm` unchanged from v0.2.0. Existing bounded language, matrix shape limits, operators, function domains, AST/XMM capture and post-evaluation replay retained.
- Development libc reference/adapter remains separate. Python is testing/build automation only.
- No dynamic matrices, extra math functions, solver, new SIMD backend, API/server, ARM64/Pi port, browser UI or 2D/3D graph implementation.
- No mathematical all-input proof, security certification or remote CI execution claimed.

[Verification](docs/VERIFICATION.md) · [Runtime ABI](docs/RUNTIME-ABI.md) · [Decimal algorithms](docs/DECIMAL-CONVERSION.md)

---


## 0.2.0 - Runtime Foundation (2026-09-23)

### Implemented
- Separate `rt_*` application API; all FILE pointers, libc globals, console/file and binary64 conversion imports reside in `src/rt/adapters/libc_io.asm`.
- Native NASM memory/string primitives in default release/debug; development-only libc reference primitive backend for differential tests.
- Storage-free ABI/layout headers and one `core_storage.asm` definition; runtime modules linked as separate ELF objects.
- Independent bounded uint64/int64/hex formatting and strict integer parsing with explicit overflow/capacity errors.
- Independent Linux syscall/fd foundation, buffered Reader/Writer, partial-write progress, sticky errors and EOF/error separation.
- Own `_start` and libc/CRT-free **runtime-smoke**, not the full evaluator.
- ABI probes, protected-page subprocesses, deterministic syscall fault injection, integer boundaries and exact-rational checks of the retained libc decimal adapter.
- Strict multi-object provenance, complete input inventories, reference/default parity and fail-closed artifact tests.

### Preserved / deferred
- `src/math.asm` and `src/kernels.asm` unchanged from v0.1.1. Existing grammar, fixed limits, error/assignment behavior and captured numerical trace retained.
- Full application remains Level 2: CRT/libc, strtod and printf-compatible output adapter are still present. Own binary64 decimal I/O and whole-app runtime integration are v0.3.0 work.
- No ARM64/Pi, Windows native, API server, web UI, plotting, dynamic allocator or optimized compute backend added. Pi/web plan preserved as documentation only.
- Historical GAS converter retained as an archive tool; `make validate-gas` now explicitly rejects use as a v0.2.0 build path.

[Runtime scope](docs/RUNTIME-FOUNDATION-KR.md) · [ABI](docs/RUNTIME-ABI.md) · [Evidence](docs/VERIFICATION.md)

## 0.1.1 - 2026-09-23 - Native Gate

- Built and tested native NASM release (`-Ox`) and debug (`-O0`, DWARF) executables, replacing the unverified-native status of v0.1.0.
- Added strict per-profile build records: exact commands, source/object/binary/map hashes and tool versions. Missing tools and failed builds remove stale outputs; the official path never falls back to GAS.
- Kept the original 14,410-case regression script and ran it on each profile. Added 1,254 native contract assertions and separate fail-closed guard tests.
- Froze 50 numeric 64-bit words across 19 constant symbols; checked all 12 watched SSE2 instruction byte sequences, actual trace addresses, register bits and MXCSR. Compared 520 result records and normalized traces between profiles.
- Strengthened the Level 2 ELF import/dependency, NX-stack, RWX-segment, RELRO and immediate-binding audit.
- Added Ubuntu 22.04/24.04 GitHub Actions configuration and artifact retention. Remote workflow execution is not claimed.
- Updated bilingual guides, build provenance, verification evidence and Level 3 boundary/roadmap.
- Added a **documentation-only** Raspberry Pi 5/server/ARM64/web graphics plan. No ARM port, HTTP listener, web UI or graph runtime was implemented.
- Runtime source changes are limited to the displayed version string. Existing grammar, layout and numerical algorithms are unchanged; libc/CRT remain.

## 0.1.0 - 2026-09-22

Initial bounded NASM x86-64 numerical workbench.

- Added assembly lexer, Pratt parser, AST evaluator, atomic variable workspace and bounded float64 matrix storage.
- Added scalar expressions, vectors/matrices, matrix and elementwise multiplication, broadcasting, division, transpose and full-element sum.
- Implemented sin/cos with bounded range reduction, positive-real log, hardware SSE2 sqrt, and bounded scalar integer powers without external math libraries.
- Added actual selected-instruction addresses, AST association, XMM before/source/after captures, exact register bits, MXCSR before/after, and terminal capture replay.
- Added REPL, script and expression CLI modes, JSON result mode, bounded-input checks and explicit capacity/shape/domain errors.
- Added English and Korean guides, architecture/language/numerics specifications, examples and executable verification evidence.
- Passed 14,410 checks on the bundled GNU-as validation-bridge executable. Native NASM and remote GitHub CI execution remain unverified in this delivery.

There was no earlier released ASMlab version. Development fixes are incorporated into this initial MVP rather than represented as changes to a previously delivered release.

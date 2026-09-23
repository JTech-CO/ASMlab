# Changelog

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

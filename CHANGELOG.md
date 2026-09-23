# Changelog

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

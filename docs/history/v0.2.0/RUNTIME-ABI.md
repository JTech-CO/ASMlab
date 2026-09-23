# ASMlab v0.2.0 Runtime ABI

Status: implemented for Linux x86-64. This is an internal project contract, not a cross-platform C ABI or a stable network protocol. See [implementation scope](RUNTIME-FOUNDATION-KR.md) and [verification](VERIFICATION.md).

## 1. Shared calling rules

Arguments use System V AMD64: RDI, RSI, RDX, RCX, R8, R9. Return values are specified below. The caller aligns RSP to 16 bytes immediately before `call`; the callee sees RSP modulo 16 equal to 8. Preserve RBX, RBP, R12–R15. Callers provide valid readable/writable spans and sufficient context storage. Pointers are not validated against arbitrary process memory. Unless explicitly allowed by a zero-length contract, NULL is not a valid pointer.

DF must be clear on entry and is clear on return. Own memory/string/integer/fd routines do not change MXCSR. This is stricter than merely preserving its control bits, and is tested. RAX, RCX, RDX, RSI, RDI, R8–R11 and arithmetic flags are caller-saved. No preservation guarantee is added for XMM registers across libc calls. `exec_sse` retains its existing, separately documented specialized contract.

Return pairs use RAX and RDX, not a C structure-return convention. A zero in RAX means success only for APIs explicitly defined as status-returning. Byte counts, pointers and signed 32-bit comparison results are different return types; do not treat them as errno values.

`include/abi.inc`, `include/layout.inc`, `include/rt/api.inc`, and `include/rt/foundation.inc` contain declarations/layouts/macros, not application storage. `src/core_storage.asm` owns the old constants and BSS once. Application numerical modules remain one translation unit; runtime modules are separate ELF objects.

## 2. Own primitives: default application and foundation

Implementation: `src/rt/primitives.asm`. No libc imports.

| API | Arguments | Result and preconditions |
|---|---|---|
| `rt_memcpy` | dst, src, n | RAX=original dst. Non-overlapping spans; n=0 performs no memory access. |
| `rt_memmove` | dst, src, n | RAX=original dst. Overlap and identical pointers allowed; n=0 performs no access. |
| `rt_memset` | dst, value, n | RAX=original dst. Fill with low 8 bits; n=0 performs no access. |
| `rt_memcmp` | a, b, n | EAX is a signed int32 whose sign compares unsigned bytes. n=0 returns 0 without access. Do not interpret the whole RAX as a sign-extended int64. |
| `rt_strlen` | NUL-terminated string | RAX=bytes before NUL. Trusted terminated storage required; no arbitrary-input safety guarantee. |
| `rt_strnlen` | bytes, maximum | RAX=min(first NUL offset, maximum). maximum=0 performs no access. |
| `rt_strcmp` | two NUL-terminated strings | EAX signed int32 comparison by unsigned byte values; both strings must be readable through their terminators. |

The development-only `dev/runtime/libc_primitives.asm` exports the same names and delegates to libc. Only `bin/asmlab-libc-reference` uses it. Core/default builds must not import libc `memcpy`, `memmove`, `memset`, `memcmp`, `strlen`, `strnlen` or `strcmp`.

## 3. Transitional application I/O and decimal adapter

Implementation: `src/rt/adapters/libc_io.asm`. These functions intentionally retain libc and the CRT. They are not aliases for the standalone fd API below.

| API | Arguments | Result / ownership |
|---|---|---|
| `rt_console_printf` | format, varargs | libc printf-compatible result in EAX. **Temporary** formatting sink; forwards via a tail jump to preserve AL and stack varargs. |
| `rt_console_puts` | NUL text | puts-style output with newline; libc return conventions. |
| `rt_output_flush` | none | fflush(NULL); EAX=0 or EOF. |
| `rt_is_tty` | fd | libc isatty boolean; not a -errno API. |
| `rt_input_stdin` | none | Borrowed opaque handle. Core must not dereference it or assume FILE layout. |
| `rt_input_open_read` | NUL path | One owned script handle, or NULL on failure/busy. Read-only mode fixed inside adapter. |
| `rt_input_close` | handle | Closes owned script; invalidates slot even if fclose fails. Borrowed stdin is not closed. Invalid/closed slot returns -1. |
| `rt_input_getc` | valid live handle | EAX=0..255 or EOF(-1). Query `rt_input_error` to distinguish an error from EOF. |
| `rt_input_error` | valid live handle | ferror-style boolean. |
| `rt_input_gets` | dst, int capacity, handle | fgets-compatible result: dst or NULL. |
| `rt_decimal_from_cstr` | NUL decimal token, end-pointer slot | XMM0=libc strtod result. Lexer and evaluator retain grammar, length and finite-value checks. |

Handles are process-local and the adapter is single-threaded, with one stdin slot and one script slot. It does not support concurrent API sessions. A stale script handle must not be reused. Invalid arbitrary pointers to getc/gets/error are outside the contract.

The interface still contains a printf-compatible bridge. v0.2.0 does **not** implement a full printf engine, own binary64 decimal input/output, or a libc-free application. Integer-only foundation tests below do not change the application's float64 language.

## 4. Independent integer conversion

Implementation: `src/rt/integer.asm`, linked to foundation fixtures/smoke, not the application parser.

| API | Arguments | Result |
|---|---|---|
| `rt_format_u64` | dst, capacity, uint64 | RAX=decimal digit count, or -28 (-ENOSPC). |
| `rt_format_i64` | dst, capacity, int64 bits | RAX=character count including optional minus, or -28. INT64_MIN supported. |
| `rt_format_hex64` | dst, capacity, uint64 | Exactly 16 lowercase hex digits, no prefix; RAX=16 or -28. |
| `rt_parse_u64` | bytes, length | RAX=0, RDX=value; or RAX=-22/-34 and RDX=0. Digits only, no sign. |
| `rt_parse_i64` | bytes, length | Same pair; optional ASCII +/-, followed by at least one digit. |

Format capacity includes the trailing NUL. Failure leaves the destination unchanged. Parsers consume the exact span or reject it; no whitespace, NUL byte, decimal point, base prefix, exponent or partial prefix acceptance. Leading zeros are accepted. Signed `-0` becomes integer zero. Overflow returns -ERANGE; invalid syntax returns -EINVAL. For inputs with both defects the first detected failure wins. No floating-point instructions, locale, heap allocation or external calls are used.

## 5. Linux syscall and fd layer

Implementation: `src/platform/linux/syscalls.asm` and `src/rt/fd_io.asm`.

`rt_sys_read/write/openat/close/ioctl` expose the corresponding raw syscall result. Negative errno is returned in RAX; no libc errno/TLS is consulted. `rt_sys_openat` moves function-ABI argument 4 from RCX to syscall R10. `syscall` clobbers RCX and R11. `rt_sys_exit(status)` calls exit_group and does not return. This layer is Linux x86-64-specific.

| API | Arguments | Result / retry policy |
|---|---|---|
| `rt_fd_open_read` | path | fd or -errno; AT_FDCWD, O_RDONLY and O_CLOEXEC. No generic retry loop. |
| `rt_fd_close` | fd | 0 or -errno; deliberately does **not** retry close after EINTR. |
| `rt_fd_read` | fd, dst, capacity | byte count, 0 EOF, or -errno. Retries EINTR only. |
| `rt_fd_write_all` | fd, src, count | RAX=0/-errno, RDX=bytes actually written. Retries EINTR; advances after short writes. EAGAIN propagates, not busy-spun. Zero progress becomes -EIO. count=0 succeeds without accessing src or fd. |

This is a blocking-oriented foundation, not an event loop. There is no blanket syscall retry policy. Default SIGPIPE behavior is retained; callers needing a returned EPIPE must arrange their own signal policy. Success from write is not an fsync/durability guarantee. No timeout/cancellation/signal runtime is supplied yet.

## 6. Buffered Reader/Writer

Allocate at least `RT_READER_SIZE` / `RT_WRITER_SIZE` (4,128 bytes each). Each owns a 4,096-byte buffer but **borrows** the fd; contexts never close it. Call init before use. Contexts are not thread-safe; spans supplied to a writer must not alias its internal buffer.

| API | Arguments | Result |
|---|---|---|
| `rt_reader_init` | reader, fd | RAX=0; resets position/end/status. |
| `rt_reader_getc` | reader | RAX=0..255 and RDX=0; EOF RAX=-1/RDX=0; error RAX=-2/RDX=raw -errno. |
| `rt_reader_error` | reader | negative errno or 0; EOF is not an error. |
| `rt_writer_init` | writer, fd | RAX=0; resets used/status, discards any old buffered data. |
| `rt_writer_write` | writer, bytes, n | RAX=0/-errno; RDX=**input bytes accepted this call**, possibly only buffered. |
| `rt_writer_flush` | writer | RAX=0/-errno; RDX=**bytes actually written by this flush**. |
| `rt_writer_cstr` | writer, NUL text | write semantics; no appended newline. |
| `rt_writer_u64/i64/hex64` | writer, value | Formats into local stack storage then calls writer_write. No NUL is sent to fd. |

Reader status is internally 0=ready, +1=EOF, negative errno=error. Thus errno -1 (EPERM) cannot be confused with EOF. EOF/error is sticky and subsequent getc calls do not issue another read until reinitialized.

On partial flush failure the written prefix is retired, the unwritten suffix remains buffered, and an error is latched. Later calls return the error rather than duplicating already-written bytes. Inspect/report failure; there is no implicit retry/resume API. Reinitialization is an explicit discard/reset. Always check the final flush; accepted bytes do not imply externally visible output.

## 7. Standalone entry and fixtures

`src/platform/linux/start.asm` is linked only into `bin/asmlab-runtime-smoke`. It reads argc/argv/envp from the process stack, clears DF, aligns the stack, calls `rt_program_main(argc,argv,envp)` and terminates with its EAX exit status. No CRT initialization or cleanup runs. The smoke entry does not host the AST/evaluator.

`runtime-primitives.so` and `runtime-faults.so` are test-only NASM fixtures with no libc imports. The former has real syscalls; the latter has injected test callbacks. `decimal-adapter.so` intentionally links libc and tests the current float conversion boundary. The Python process that loads these fixtures is a test host, not an application runtime dependency.

## 8. Tests and limits

`tests/runtime_suite.py`: value/buffer bounds, no-write-on-failure, overlap, ABI, direct fd/PTY, injected I/O, protected pages, integer limits, decimal adapter and smoke CLI.

`tests/runtime_boundary.py`: source imports plus ELF object boundaries, no test providers in production, default/reference equality and trace equality excluding instruction addresses.

`tools/check_provenance.py`: all build inputs, objects, link maps, target hashes and module groups are validated before standard gates execute artifacts. These are integrity checks, not signed attestations; code outside preconditions can still corrupt memory.

### Primary platform references

- NASM ELF format: https://www.nasm.us/doc/nasm09.html
- Linux syscall ABI: https://man7.org/linux/man-pages/man2/syscall.2.html
- write and partial I/O: https://man7.org/linux/man-pages/man2/write.2.html
- close/EINTR policy: https://man7.org/linux/man-pages/man2/close.2.html

These references describe platform contracts. ASMlab implementation evidence is in the included test reports.

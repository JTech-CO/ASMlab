# ASMlab v0.5.0 Runtime ABI

Implemented internal contract, Linux x86-64. Not a C standard-library replacement or a stable network API.

## Calling convention and storage

System V AMD64 arguments use RDI, RSI, RDX, RCX, R8, R9; each caller aligns RSP to 16 immediately before `call`. Preserve RBX, RBP, R12–R15; DF is clear on entry/return. Scalar status/value pairs use RAX/RDX as documented, not a C struct-return ABI. Memory, integer, exact-decimal and own I/O routines preserve MXCSR. Pointers must reference valid spans/contexts; arbitrary pointers are not made safe by these APIs. Fixed context adapters are single-threaded and not reentrant.

`include/abi.inc`, `layout.inc`, `rt/api.inc`, `rt/foundation.inc` and `rt/biguint.inc` contain no application storage. `src/core_storage.asm` owns the existing numerical BSS/constants once. Core modules form one translation unit and separately link the runtime modules.

## Own primitive API

| Function | Arguments | Return / precondition |
|---|---|---|
| rt_memcpy | dst, src, n | original dst; non-overlapping spans; n=0 no access |
| rt_memmove | dst, src, n | original dst; overlap allowed; n=0 no access |
| rt_memset | dst, value, n | original dst; low byte used; n=0 no access |
| rt_memcmp | a, b, n | signed int32 in EAX, unsigned-byte ordering; n=0 returns0 |
| rt_strlen | NUL text | length; readable through terminator required |
| rt_strnlen | bytes, limit | first NUL offset or limit; limit0 no access |
| rt_strcmp | two NUL texts | signed int32 EAX, unsigned-byte ordering |

## Integer and float64 conversion

| Function | Arguments | Return |
|---|---|---|
| rt_format_u64 / rt_format_i64 | dst, capacity, value | length or -28; NUL included in capacity |
| rt_format_hex64 | dst, capacity, bits | 16 lowercase digits, no prefix; length16 or -28 |
| rt_parse_u64 / rt_parse_i64 | bytes, length | RAX0 and RDXvalue, or -22/-34 and RDX0 |
| rt_parse_f64 | bytes, length1..127 | RAX0 and RDXbinary64 bits; -22 invalid with bits0; -34 overflow with signed infinity bits |
| rt_format_f64 | dst, capacity, bits, precision1..17 | length or -22/-28; failed call does not modify destination |
| rt_decimal_from_cstr | bounded NUL token, optional end-pointer slot | XMM0 bits; success end=token+length; failure end=token and nonfinite sentinel |

Integer parsing consumes the whole span; u64 admits digits only, i64 an optional sign. Integer format failure leaves the output unchanged. INT64_MIN/UINT64_MAX are supported.

Float64 parsing accepts decimal mantissas/exponents, no whitespace/locale/hex/nonfinite literal. Signed zero and gradual underflow are supported. Decimal rounding is nearest-even independently of MXCSR. Formatting implements general notation, not shortest output; precision17 is for round trips. `nan/inf` text is formatting-only for trace metadata, not valid expression input. The lexer wrapper is **not a general strtod-compatible API**. See [algorithm/bounds](DECIMAL-CONVERSION.md).

## Raw syscall and fd API

`rt_sys_read/write/openat/close/ioctl` expose raw Linux negative-errno returns. `openat` moves SysV RCX argument4 into R10; syscall clobbers RCX/R11. `rt_sys_exit(status)` executes exit_group and does not return. No TLS/errno/libc syscall function is used.

| Function | Arguments | Return / policy |
|---|---|---|
| rt_fd_open_read | NUL path | fd or -errno; O_RDONLY/O_CLOEXEC, AT_FDCWD |
| rt_fd_close | fd | 0/-errno; no close retry after EINTR |
| rt_fd_read | fd, dst, capacity | byte count / EOF0 / -errno; retries EINTR only |
| rt_fd_write_all | fd, bytes, count | RAX0/-errno, RDXbytes written; short writes advance; EINTR retry; EAGAIN propagates; zero progress -> -EIO |

These are blocking-oriented routines, not an event loop. Default SIGPIPE/SIGINT actions remain; SIGPIPE may terminate the process rather than returning EPIPE. No fsync durability guarantee or arbitrary syscall policy is provided. The optional native Workbench has its own terminal/signal host described below; this is not generic in-expression cancellation.

## Reader / Writer

Each context requires 4,128 bytes, owns a 4,096-byte buffer and **borrows** its fd. Init before use. Contexts do not close descriptors. Writer source spans must not alias the Writer's own buffer.

| Function | Arguments | Return |
|---|---|---|
| rt_reader_init | context, fd | 0; reset buffered state |
| rt_reader_getc | reader | RAX0..255/RDX0; EOF RAX-1/RDX0; error RAX-2/RDX-errno |
| rt_reader_error | reader | negative error or0, EOF not error |
| rt_writer_init | context, fd | 0; resets/discards old buffer/status |
| rt_writer_write | writer, bytes, length | RAX0/-errno; RDXinput bytes accepted, possibly buffered |
| rt_writer_flush | writer | RAX0/-errno; RDXbytes actually written in this flush |
| rt_writer_cstr | writer, NUL text | write semantics, no newline |
| rt_writer_u64/i64/hex64 | writer, value | integer conversion into local scratch then write |

EOF/error is sticky until explicit reinitialization. After a partially successful flush fails, written bytes are retired, unwritten bytes remain buffered and an error is latched. Subsequent calls do not duplicate a previously written prefix. Final flush must be checked. Context reset is an explicit discard, not transparent resumption.

## Full application adapter

Implemented in `src/rt/adapters/app_io.asm`; no FILE or libc data exists here. There is one borrowed stdin Reader, one owned script Reader and one stdout Writer. `rt_host_init` is called once at process entry. Calling it as a multi-session reset API is unsupported.

| Function | Arguments | Return / ownership |
|---|---|---|
| rt_input_stdin | none | same borrowed Reader every call; never resets buffered replay input |
| rt_input_open_read | NUL path | owned script handle or NULL on failure/busy |
| rt_input_close | handle | 0/-1; borrowed stdin not closed; script invalidated even on failure |
| rt_input_getc | live handle | EAX0..255 or -1; inspect rt_input_error to distinguish error/EOF |
| rt_input_error | live handle | boolean |
| rt_input_gets | dst, int capacity, handle | fgets-like bounded line read: dst or NULL; same Reader as REPL |
| rt_is_tty | fd | boolean via TCGETS ioctl; does not change terminal settings |
| rt_console_write_bytes | bytes, length | status via stdout Writer |
| rt_console_puts | NUL text | append text and newline; Writer status |
| rt_console_format | trusted static format, varargs | submitted byte count or negative failure |
| rt_console_fault | negative error | latch first format/output error |
| rt_output_flush | none | Writer flush status/bytes |
| rt_host_finish | main status | final status after close/flush; output failure -> 2 and stderr diagnostic |

`rt_console_format` is a small view renderer, **not full printf**. Supported forms are `%%`, `%s`, `%c`, `%d/%ld`, `%x/%lx`, and `%g`, with space/zero width0..4096 or a nonnegative dynamic `*` width; decimal precision1..17. SysV AL identifies vector varargs; at most8 FP arguments. No `%n`, pointers, arbitrary string precision, locale, left alignment, positional arguments or user-controlled format strings. Unsupported forms latch -EINVAL. A format failure can occur after a prefix was buffered; this is not an atomic whole-format transaction.

The existing quiet/JSON text contract is preserved. General language/CLI diagnostics remain in their existing stdout forms; new low-level output-failure diagnostics use stderr. One successful expression may already have committed before its output fails; output failure is not a workspace transaction rollback.

## Entry and comparison boundaries

`app_start.asm`: `_start → rt_host_init → main → rt_host_finish → exit_group`. The initial stack supplies argc/argv. `main` is an assembly label, not CRT startup. Stack alignment, clear DF and initial MXCSR are established explicitly. Numerical evaluation resets MXCSR to0x1f80 immediately before entering the evaluator, isolating parser side effects in the comparison backend.

`start.asm` serves only `asmlab-runtime-smoke` and calls its separate `rt_program_main`.

`dev/runtime/libc_primitives.asm` and `src/rt/adapters/libc_io.asm` are linked **only** into the explicit development comparison target. `decimal-adapter.so` retains libc; `decimal-native.so` and primitive/fault/dynamic-memory fixtures are test-only without external runtime imports. Python ctypes is the test host, not a numerical backend.

## Dynamic mapping API (v0.4.0)

`src/rt/dynamic_memory.asm` is shared by the production app and a development-only fixture. It is single-threaded, not a general-purpose malloc ABI. Heap operations preserve SysV callee-saved registers, clear DF, and preserve all MXCSR bits. Invalid pointers or duplicate free are outside the contract.

| API | Arguments | Return |
|---|---|---|
| `rt_heap_alloc` | positive payload byte count | RAX=16-byte aligned pointer, RDX=0; failure RAX=0/RDX=-errno |
| `rt_heap_free` | own live pointer or NULL | RAX=0 on release/no-op; unexpected munmap failure exits2 |
| `rt_memory_set_limit` | bytes1MiB..1GiB, at least live mapped bytes | RAX=0; -22 invalid, -16 below live |
| `rt_memory_stats` | writable48bytes | RAX=0, six uint64s: used,peak,quota,live,maps,unmaps |
| `rt_sys_mmap` | addr,len,prot,flags,fd,offset using SysV registers | raw pointer or negative Linux errno; RCX→R10 |
| `rt_sys_munmap` | addr,len | raw Linux status |

Each allocation owns one anonymous privateRW mapping, charged in4096-byte pages including a32-byte private header. Length/rounding/used additions are checked before mapping; invalid size0 is -22, arithmetic overflow -75, quota/kernel allocation failure negative errno. No MAP_NORESERVE/executable mapping is requested. Header contents are internal and not caller-mutable. Release accounting changes only after munmap succeeds. Counts refer to mappings, not application Value counts or physicalRSS.

The application `value_allocate` additionally checks positive shape multiplication and at most1,048,576 elements before multiplication by8. Its64-byte descriptor and48-byte linked symbol layout are [specified here](DYNAMIC-WORKSPACE-KR.md). Temporary bump chunks and persistent copies share quota but not lifetime. `workspace_commit` stages all new state before publishing. No public/reentrant multi-session ABI or reference counting exists.

Normal `main` return now releases temporary and persistent mappings before `rt_host_finish`; final output errors retain the earlier documented exit2 behavior. Kernel cleanup on abnormal signal/process exit is not an application-level rollback guarantee.

## References and evidence

[Tests](VERIFICATION.md) · [L3 boundary](LEVEL3-CONTRACT.md)

Platform references: NASM ELF output <https://www.nasm.us/doc/nasm09.html>; Linux syscall ABI <https://man7.org/linux/man-pages/man2/syscall.2.html>; partial writes <https://man7.org/linux/man-pages/man2/write.2.html>; close policy <https://man7.org/linux/man-pages/man2/close.2.html>. These describe platform contracts, not an independent certification of this implementation.

## Native Workbench ABI (v0.5.0)

Implemented by `src/platform/linux/terminal.asm`; project SysV rules apply. Main/Reader/Writer remain single-session. These routines are not linked into the libc reference. No test callbacks or foreign toolkit runs in the production UI.

| API | Input | Result and state |
|---|---|---|
| rt_terminal_enter | none | 0 success, negative errno failure. Save kernel termios36bytes and selected sigactions; set cbreak; enter alternate screen; hide cursor. Best-effort unwind on partial setup failure. |
| rt_terminal_leave | none | Restore saved terminal/action state, cursor and alternate screen. Idempotent when not live; negative terminal/output error can be returned. |
| rt_terminal_poll | timeout milliseconds | RAX0..255 byte; -1 timeout/interruption; -2 EOF/I/O failure; -3 handled termination with RDX=signal. Checks the pre-read stdin buffer before poll/read. |
| rt_terminal_size | none | RAX columns, RDX rows, RCX dirty/resize flag. ioctl failure/zero dimension falls back to80×24. |
| rt_input_try_byte | none | Borrowed shared Reader buffered byte0..255, or -1 if no buffered byte. No fd read/reset. Private native adapter boundary. |

Terminal handlers for HUP/INT/QUIT/PIPE/TERM only set flags; WINCH/CONT request redraw; TSTP requests suspend. `rt_terminal_poll` handles suspend at a safe boundary: restore terminal/screen, SIGSTOP self, restore UI after CONT. Native screen output uses explicit CRLF with OPOST disabled. ISIG remains enabled. Handled exit status is128+signal. Old dispositions are restored when leaving.

The UI edits source in bounded static buffers and uses the existing `process_line`; it does not bypass parser/value/domain/quota/commit checks. A failed expression invalidates root/result/trace before any pane or value-navigation action can dereference a Value. AST `N_END` occupies byte120; `node_starts` is a parallel table. `Trace` grows to192bytes, [layout and meaning](TRACE-V2.md).

`OP`/`TRACE_SET`/`TRACE_SHAPE` are assembly-time specialization macros, not runtime ABI entry points. `eval_node_compute` and the `_compute` numerical functions do not call the observed arithmetic dispatcher. Shared allocation/validation/commit routines remain ordinary calls. The dispatch decision occurs once per expression. No reentrant, multithreaded, network, or dynamically loaded plugin ABI is introduced.

Uncatchable SIGKILL/SIGSTOP or crashes cannot guarantee restoration. Cleanup during long evaluation is deferred; a successful evaluation can commit before the termination flag is handled. This is not a transactional cancel mechanism. Fixed trace/TUI/history storage lies outside the mmap quota. An I/O failure after computation does not undo a workspace commit.

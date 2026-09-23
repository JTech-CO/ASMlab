# ASMlab v0.3.0 architecture

L3-Core, Linux x86-64; bounded single-process REPL, not a network service.

## Production path

```text
platform/linux/app_start.asm
  _start → rt_host_init → main → rt_host_finish → exit_group

src/asmlab.asm
  core_storage + workspace + lexer/parser + evaluator
  + math + observed SSE2 kernels + terminal views + main
        │ runtime API
        ├─ rt/primitives.asm
        ├─ rt/integer.asm
        ├─ rt/biguint.asm + decimal_parse.asm + decimal_format.asm
        ├─ rt/console_format.asm
        └─ rt/adapters/app_io.asm
              └─ rt/fd_io.asm → platform/linux/syscalls.asm
```

The core still forms one translation unit. Runtime modules are separate NASM objects. No dynamic loader, libc/CRT, external math library or test fixture is linked into the production image. `dev/runtime/libc_primitives.asm` + `rt/adapters/libc_io.asm` are a **development-only** comparison route, not a fallback selected at runtime.

## Preserved contracts

Float64 scalars/row-major matrices, dimensions1..16, deep-copy symbols, reserved `ans`, 512 AST nodes, fixed scratch value arena, bounded input and trace. Failed evaluation does not overwrite a variable or `ans`. `math.asm` and `kernels.asm` are unchanged from v0.2.0. The evaluator explicitly starts with MXCSR0x1f80 independently of parser conversion effects.

Observation captures selected SSE2 instructions in precompiled kernels. Node ID, actual PC, active lanes, XMM before/source/after and MXCSR snapshots are stored before rendering. Replay is post-computation, not JIT or live stepping. Formatting does not recompute a numerical result or emulate an XMM value. The converter's multiword integer work is not part of the selected SSE2 trace.

## Decimal and UI

Exact integer-based conversions are bounded by the existing127-byte token and binary64 range. Local stack scratch avoids shared decimal state. The original terminal layout uses a trusted, limited format interpreter backed by typed Writer operations. It is not a general printf engine. Replay and REPL share one Reader; calling `rt_input_stdin` does not reset it.

The adapter has one script handle. Final cleanup checks buffered stdout errors and exits nonzero. No allocator, dynamic matrix descriptor, event loop, signal handler or external renderer is introduced.

## Development artifacts

- `asmlab` / `asmlab-debug`: full L3-Core production binaries.
- `asmlab-libc-reference`: intentionally libc/CRT-linked comparison.
- `asmlab-runtime-smoke`: independent integer/fd foundation demonstration.
- `runtime-primitives.so`, `runtime-faults.so`, `decimal-native.so`: NASM test fixtures.
- `decimal-adapter.so`: intentionally libc-linked conversion reference fixture.
- Python scripts: build provenance and verification only.

NASM/ld inputs and SHA256 are recorded in build sidecars. The gate inspects object membership and link arguments as well as ELF headers and process mappings; an empty-root test runs the full application without userspace libraries or shell. Neither checksum audits nor chroot imply a security certification.

[ABI](RUNTIME-ABI.md) · [Decimal](DECIMAL-CONVERSION.md) · [Verification](VERIFICATION.md) · [Future plans](plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)

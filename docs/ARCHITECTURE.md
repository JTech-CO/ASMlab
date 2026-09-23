# ASMlab v0.4.0 architecture

L3-Core + Dynamic Workspace. Linux x86-64, single process/session, not a network service.

```text
_start → rt_host_init → main → temp_release/workspace_clear → rt_host_finish → exit_group

Parser → AST → Evaluator + workspace_functions
                  │             │
                  └── runtime.asm: 64-byte Value / ownership / atomic commit
                         ├── per-expression bump arena
                         ├── linked workspace symbols + owned value copies
                         └── rt_heap_alloc/free
                                └── platform/linux/virtual_memory.asm
                                      mmap / munmap

Numerical operations → descriptor.data → original observed SSE2 dispatch → real trace
Views → preview/full export → own decimal / Writer → syscalls
```

Production uses13 independently generated NASM objects and direct static GNU ld linking; the core remains one translation unit of assembly modules. No allocator from libc, CRT, external math library, test fixture or language runtime is linked into production. A separate libc comparison executable uses the same dynamic storage and numerical code with development I/O/primitive adapters.

Values own contiguous f64 payloads. `rows*cols` is checked before allocating; element cap1,048,576 and default64MiB dynamic-mapping quota apply independently. A 48-byte symbol stores a name, persistent Value pointer and next pointer. Static `ans` starts at a static immutable zero descriptor. No user-symbol count cap remains; lookup is linear and every live symbol is charged.

Temporary arenas survive successful rendering/replay and expire on the next expression. Persistent symbols survive across expressions. Trace records copy register bits and contain no pointer into freed workspace payloads. Clear invalidates consumers before freeing. Commit allocates all new copies before publishing and then releases old values. See [detailed ownership and failure contracts](DYNAMIC-WORKSPACE-KR.md).

Existing exact decimal, blocking Reader/Writer, final flush errors and shared REPL/replay input are preserved. `math.asm` and the real instruction dispatch/capture prefix are identical to0.3.0; kernels following that prefix have descriptor address changes and a matrix-product work preflight. Constructor metadata/copy initialization is not full CPU tracing.

Development artifacts add `dynamic-memory.so` to the previous no-libc primitive/fault/native-decimal fixtures. This fixture uses the actual mapping allocator plus a test ABI probe, not a production dependency. `decimal-adapter.so` and `asmlab-libc-reference` intentionally use libc. Python is build/test infrastructure only.

[ABI](RUNTIME-ABI.md) · [Language](LANGUAGE.md) · [Verification](VERIFICATION.md) · [Future Pi/web plan](plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)

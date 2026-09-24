# ASMlab v0.5.0 architecture

Native Linux x86-64, one process/session. Full L3-Core + Dynamic Workspace + Observable Workbench, not a server or GUI toolkit.

```text
_start → own host initialization → main → own cleanup/final flush → exit_group

own Reader → parser → AST (+ source spans)
                       |
                 per-expression mode selection
                   /                      \
          Observe evaluator           Compute evaluator
          same arithmetic source      same arithmetic source
          watched SSE2 dispatcher     inline SSE2 operations
          actual XMM/MXCSR records    no trace/scratch/dispatch
                   \                      /
                own dynamic Value + validation + atomic workspace commit
                                  |
        classic view/replay | Trace v2 JSON | optional linked terminal Workbench
                                  |
                     own decimal formatting / Writer
                                  |
                              Linux syscalls
```

`src/asmlab.asm` includes the numerical templates twice. NASM macros map functions/calls to `_compute` and replace OP with an inline instruction for the second inclusion. There is no compiler/JIT at runtime. Shared allocator/descriptor/validation/commit semantics remain unchanged. All14 production objects are NASM-generated and linked directly with GNU ld; the added14th object is the Linux terminal host. No libc/CRT/math/terminal library or fixture links into native release/debug.

`src/trace_v2.asm` owns new snapshot metadata and JSON export. Prefix-bounded records retain the previous96-byte raw capture prefix and append execution identity/span/stage/context/lane metadata. Events carry no pointer into persistent user data. Snapshot nodes/temporary Values are valid only for the latest successful expression; errors, next expressions and clear invalidate them. [Trace v2](TRACE-V2.md).

`src/workbench.asm` owns cell-buffer rendering, focus/selection linking, bounded source editor/history/search and value viewport. `src/platform/linux/terminal.asm` owns kernel termios/signals/poll/winsize. The view never evaluates another expression to fabricate a register value. Node values are completed values; instruction frames are actual retained state, not a live partially executed process. Screen layout/keys/cleanup limits: [Workbench](OBSERVABLE-WORKBENCH-KR.md).

Dynamic storage remains the v0.4.0 own mapping allocator,64-byte Values and48-byte linked symbols, with immutable initial ans zero and transactional staged copies. Mmap quota does not include static trace/UI/history/stack. Scalars, full dense arrays, shape/work caps and1-based indexing remain. [Dynamic workspace](DYNAMIC-WORKSPACE-KR.md).

Development builds/fixtures can intentionally use libc or Python as testing infrastructure. The reference build does not have the native terminal host. Actual browser/ARM/Pi/plotting implementations remain excluded; earlier plans are preserved without being promoted to finished features.

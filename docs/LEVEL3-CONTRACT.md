# ASMlab L3-Core contract - v0.3.0

**Implemented for the complete production application on Linux x86-64.** Level 3 is a project boundary, not an external certification.

| Boundary | v0.3.0 |
|---|---|
| Application sources | Project NASM `.asm` / `.inc` only |
| Entry/exit | Own `_start`, host initialization, main, final flush, exit_group |
| I/O, primitive and numeric conversion | Own NASM modules and direct Linux syscall instructions |
| Runtime dependencies | No libc, CRT, libm, BLAS, LAPACK, libgcc/compiler-rt, Python, shell or external process |
| OS dependencies | Linux kernel, ELF loader, terminals and filesystem are allowed |
| ELF | Non-PIE static EXEC, no PT_INTERP/DT_NEEDED/unresolved symbols, NX stack, no RWX LOAD |
| Build tools | NASM and GNU ld; make/Python development automation allowed |
| Test comparison | Separate libc-linked executable/fixture allowed, never linked into production |
| Validation | Exact link-input manifest, ELF/object audits, /proc mappings, empty-root execution, regression |

The numeric evaluator, matrix engine, AST/XMM views and replay are present in `bin/asmlab` and `bin/asmlab-debug`. `asmlab-runtime-smoke` remains a separate smaller tool, not a substitute for full-app validation. `asmlab-libc-reference` is explicitly development-only and is not L3-Core.

No dynamic dependencies alone would not exclude static libc. Therefore the gate checks the full list of separately NASM-generated project objects and the exact direct-ld link command, in addition to ELF imports. Build metadata/hashes are local integrity evidence, not signed build attestations.

The retained `main` symbol is an ordinary assembly function called by the project's `_start`; it does not imply CRT startup. Kernel-provided `[vdso]`/`[vvar]` mappings are normal OS mappings and are not imported userspace libraries.

L3-Core does not mean an operating system, a MATLAB clone, dynamically sized matrices, full libm correctness, a secure public server, or ARM64 portability. Existing bounded language/trace limits remain. The subsequent L3-Workbench roadmap is separate.

[Verification](VERIFICATION.md) · [Runtime ABI](RUNTIME-ABI.md) · [Future Pi/web plan](plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)
